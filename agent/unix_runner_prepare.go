package agent

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"strings"
)

func (r *UnixSocketRuntime) prepareRunnerWithJIT(request SocketRequestEnvelope, command socketCommand, jitConfig, jitStatus string) SocketResponseEnvelope {
	if r.config.ProcessController == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	runnerID, correlation, err := r.commandRunnerIdentity(command, true)
	if err != nil || command.ReservationID == "" || command.Executable == "" || command.Workspace == "" {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "runner_identity_invalid")
	}
	ownership := r.runnerOwnershipFor(runnerID)
	if err := r.config.ProcessController.Claim(context.Background(), ownership); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", runnerCommandError(err))
	}
	if err := r.config.ProcessController.Prepare(context.Background(), ownership, RunnerPrepareRequest{
		Executable: command.Executable, JITConfig: jitConfig, Workspace: command.Workspace, Environment: command.Environment,
	}); err != nil {
		_ = r.config.ProcessController.Release(context.Background(), ownership)
		log.Printf("runner prepare failed: %v", err)
		code := runnerCommandError(err)
		if errors.Is(err, ErrRunnerWorkspaceInvalid) {
			code = "runner_workspace_invalid"
		}
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", code)
	}
	r.mu.Lock()
	r.runnerInstanceID = runnerID
	r.mu.Unlock()
	if _, err := r.runnerLifecycle(context.Background(), firstNonEmpty(command.OperationID, request.RequestID)+".config-ack", runnerID, "config-ack", correlation); err != nil {
		log.Printf("runner config acknowledgement failed: %v", err)
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	return r.successResponse(request, map[string]any{"runnerInstanceId": runnerID, "jitStatus": firstNonEmpty(jitStatus, "CONFIG_READY"), "prepared": true})
}

func (r *UnixSocketRuntime) schedulerPrepareFromJIT(requestID string, command socketCommand, jitConfig, jitStatus string) (SocketResponseEnvelope, error) {
	request, err := r.schedulerEnvelope(requestID, command)
	if err != nil {
		return SocketResponseEnvelope{}, err
	}
	response := r.prepareRunnerWithJIT(request, command, jitConfig, jitStatus)
	if err := newSchedulerSocketResponseError(response); err != nil {
		return response, err
	}
	return response, nil
}

func (r *UnixSocketRuntime) reservationPrepare(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	if err := r.requireControlLease(command); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	if r.config.ProcessController == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	_, correlation, err := r.commandRunnerIdentity(command, true)
	if err != nil || command.ReservationID == "" || command.Executable == "" || command.Workspace == "" {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "runner_identity_invalid")
	}
	reservationID, err := pathComponent(command.ReservationID)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "runner_identity_invalid")
	}
	prepareRequest := reservationPreparePayload{Type: "reservation.prepare", ReservationID: command.ReservationID, RunnerCorrelation: correlation}
	response, err := r.serverCommand(context.Background(), firstNonEmpty(command.OperationID, request.RequestID), reservationPreparePathPrefix+reservationID+"/prepare-runner", prepareRequest)
	if err != nil {
		log.Printf("runner reservation prepare failed: %v", err)
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	var metadata reservationPrepareResponse
	if err := json.Unmarshal(response.Payload, &metadata); err != nil {
		log.Printf("runner reservation prepare response invalid: %v", err)
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "runner_jit_config_missing")
	}
	jitConfig := strings.TrimSpace(metadata.JITConfig)
	if jitConfig == "" {
		jitConfig = strings.TrimSpace(metadata.EncodedJITConfig)
	}
	if jitConfig == "" {
		log.Printf("runner reservation prepare response missing JIT config")
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "runner_jit_config_missing")
	}
	return r.prepareRunnerWithJIT(request, command, jitConfig, metadata.JITStatus)
}
