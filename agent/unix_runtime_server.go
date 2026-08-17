package agent

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
)

func runnerCommandError(err error) string {
	switch {
	case errors.Is(err, ErrRunnerOwnershipRequired), errors.Is(err, ErrRunnerOwnershipMismatch):
		return "runner_identity_invalid"
	case errors.Is(err, ErrRunnerNotPrepared):
		return "runner_not_prepared"
	case errors.Is(err, ErrRunnerProcessControlUnavailable):
		return "external_control_unavailable"
	default:
		return "runner_lifecycle_failed"
	}
}

func (r *UnixSocketRuntime) commandRunnerIdentity(command socketCommand, allowNew bool) (string, map[string]any, error) {
	correlation := command.RunnerCorrelation
	runnerID := strings.TrimSpace(command.RunnerInstanceID)
	if runnerID == "" && correlation != nil {
		if value, ok := correlation["runnerInstanceId"].(string); ok {
			runnerID = strings.TrimSpace(value)
		}
	}
	if runnerID == "" || correlation == nil || len(correlation) == 0 {
		return "", nil, ErrRunnerOwnershipRequired
	}
	if value, ok := correlation["runnerInstanceId"].(string); !ok || strings.TrimSpace(value) != runnerID {
		return "", nil, ErrRunnerOwnershipMismatch
	}
	r.mu.Lock()
	current := r.runnerInstanceID
	r.mu.Unlock()
	if current != "" && current != runnerID {
		return "", nil, ErrRunnerOwnershipMismatch
	}
	if !allowNew && current == "" {
		return "", nil, ErrRunnerOwnershipMismatch
	}
	return runnerID, correlation, nil
}

func (r *UnixSocketRuntime) serverCommand(ctx context.Context, requestID, path string, payload any) (ServerResponseEnvelope, error) {
	if r.config.ControlPlane == nil {
		return ServerResponseEnvelope{}, ErrExternalControlUnavailable
	}
	r.mu.Lock()
	identity := r.config.Identity
	fencing := ServerFencingFields{SessionEpoch: r.config.ServerSessionEpoch, FenceToken: r.config.FencingToken}
	if r.serverRevision > 0 {
		revision := r.serverRevision
		fencing.ExpectedServerRevision = &revision
	}
	r.mu.Unlock()
	if requestID == "" {
		return ServerResponseEnvelope{}, errors.New("server operation ID is required")
	}
	serverRequest, err := NewServerRequestEnvelope(requestID, identity, fencing, payload)
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	response, err := r.DoServerRequest(ctx, path, serverRequest)
	// The scheduler shares the server revision with webhook projection work.
	// A webhook can legitimately advance it between claim and prepare; retry
	// that one optimistic-concurrency miss against the current server state.
	// Session/fence identity and the stable request ID remain unchanged, so a
	// real duplicate or malformed request is still rejected normally.
	if err != nil && response.Error != nil && response.Error.Code == "invalid_request" && serverRequest.Fencing.ExpectedServerRevision != nil {
		serverRequest.Fencing.ExpectedServerRevision = nil
		response, err = r.DoServerRequest(ctx, path, serverRequest)
	}
	if err != nil {
		if response.Error != nil {
			log.Printf("server lifecycle rejected: path=%s request=%s code=%s message=%s", path, requestID, response.Error.Code, response.Error.Message)
		}
		return response, err
	}
	if response.Outcome != "accepted" && response.Outcome != "completed" {
		if response.Error != nil {
			log.Printf("server lifecycle rejected: path=%s request=%s code=%s message=%s", path, requestID, response.Error.Code, response.Error.Message)
		}
		return response, fmt.Errorf("server lifecycle response was %s", response.Outcome)
	}
	return response, nil
}

// schedulerEnvelope is the in-process equivalent of the authenticated Unix
// socket operator envelope. It uses the Agent-owned lease when available and
// falls back to the UI lease for embedded/test runtimes that do not start the
// headless lease loop.

func (r *UnixSocketRuntime) schedulerEnvelope(requestID string, command socketCommand) (SocketRequestEnvelope, error) {
	if requestID == "" {
		return SocketRequestEnvelope{}, errors.New("scheduler request ID is required")
	}
	r.mu.Lock()
	r.expireLeaseLocked()
	r.expireSchedulerLeaseLocked()
	lease := r.schedulerLease
	if lease.token == "" {
		lease = r.lease
	}
	if lease.token == "" || lease.draining {
		r.mu.Unlock()
		return SocketRequestEnvelope{}, ErrControlLeaseRequired
	}
	command.AppInstanceID = lease.appInstanceID
	command.ControlToken = lease.token
	r.mu.Unlock()
	payload, err := CanonicalJSON(command)
	if err != nil {
		return SocketRequestEnvelope{}, err
	}
	hash, err := HashPayload(command)
	if err != nil {
		return SocketRequestEnvelope{}, err
	}
	request := SocketRequestEnvelope{
		ProtocolVersion: ServerProtocolVersion, RequestID: requestID, PayloadHash: hash,
		Session: func() *SocketSessionContext { value := r.sessionContext(); return &value }(), Fencing: r.fencingContext(), Payload: payload,
	}
	if err := r.validateRequestContext(request); err != nil {
		return SocketRequestEnvelope{}, err
	}
	return request, nil
}

func (r *UnixSocketRuntime) schedulerDispatch(requestID string, command socketCommand) (SocketResponseEnvelope, error) {
	request, err := r.schedulerEnvelope(requestID, command)
	if err != nil {
		return SocketResponseEnvelope{}, fmt.Errorf("scheduler envelope: %w", err)
	}
	response := r.dispatch(request)
	if err := newSchedulerSocketResponseError(response); err != nil {
		return response, err
	}
	return response, nil
}

func pathComponent(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || strings.ContainsAny(value, "/?#") {
		return "", errors.New("invalid path component")
	}
	return value, nil
}

func (r *UnixSocketRuntime) runnerLifecycle(ctx context.Context, requestID, runnerID, event string, correlation map[string]any) (ServerResponseEnvelope, error) {
	id, err := pathComponent(runnerID)
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	payload := runnerLifecyclePayload{Type: "runner." + strings.ReplaceAll(event, "-", "_"), RunnerInstanceID: runnerID, RunnerCorrelation: correlation}
	return r.serverCommand(ctx, requestID, runnerInstancePathPrefix+id+"/"+event, payload)
}
