package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
)

type SchedulerServerClient struct {
	transport schedulerEnvelopeTransport
	identity  ServerMachineIdentity
	fencing   ServerFencingFields
	mu        sync.Mutex
	revision  uint64
}

type schedulerRequestError struct {
	err          error
	retryAfterMs uint64
}

func (e *schedulerRequestError) Error() string { return e.err.Error() }

func (e *schedulerRequestError) Unwrap() error { return e.err }

func newSchedulerRequestError(response ServerResponseEnvelope, err error) error {
	if err == nil {
		err = fmt.Errorf("scheduler response was %s", response.Outcome)
	}
	retryAfterMs := uint64(0)
	if response.RetryAfterMs != nil {
		retryAfterMs = *response.RetryAfterMs
	} else if response.Error != nil {
		retryAfterMs = response.Error.RetryAfterMs
	}
	return &schedulerRequestError{err: err, retryAfterMs: retryAfterMs}
}

func newSchedulerSocketResponseError(response SocketResponseEnvelope) error {
	if response.Outcome == "succeeded" {
		return nil
	}
	retryAfterMs := uint64(0)
	if response.RetryAfterMs != nil {
		retryAfterMs = *response.RetryAfterMs
	} else if response.Error != nil {
		retryAfterMs = response.Error.RetryAfterMs
	}
	message := fmt.Sprintf("scheduler command outcome was %q", response.Outcome)
	if response.Error != nil && response.Error.Code != "" {
		message = fmt.Sprintf("scheduler command rejected: %s", response.Error.Code)
	}
	return &schedulerRequestError{err: errors.New(message), retryAfterMs: retryAfterMs}
}

func NewSchedulerServerClient(transport schedulerEnvelopeTransport, identity ServerMachineIdentity, fencing ServerFencingFields, revision uint64) (*SchedulerServerClient, error) {
	if transport == nil {
		return nil, errors.New("scheduler transport is required")
	}
	if identity.MachineID == "" || identity.BootID == "" || identity.AgentInstanceID == "" || identity.SessionID == "" {
		return nil, errors.New("scheduler identity is incomplete")
	}
	if fencing.SessionEpoch == 0 || fencing.FenceToken == "" {
		return nil, errors.New("scheduler fencing is incomplete")
	}
	return &SchedulerServerClient{transport: transport, identity: identity, fencing: fencing, revision: revision}, nil
}

func (c *SchedulerServerClient) request(ctx context.Context, requestID, path string, payload any) (ServerResponseEnvelope, error) {
	c.mu.Lock()
	fencing := c.fencing
	revisionValue := c.revision
	if source, ok := c.transport.(schedulerRevisionSource); ok && source.CurrentServerRevision() > 0 {
		revisionValue = source.CurrentServerRevision()
	}
	if revisionValue > 0 {
		revision := revisionValue
		fencing.ExpectedServerRevision = &revision
	}
	c.mu.Unlock()
	request, err := NewServerRequestEnvelope(requestID, c.identity, fencing, payload)
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	response, err := c.transport.DoServerRequest(ctx, path, request)
	// Webhook projection can advance the shared pool revision between the
	// status check and this mutation. Retry once without the optimistic fence;
	// the stable request ID still protects the mutation from duplicate effects.
	if response.Error != nil && response.Error.Code == "invalid_request" && request.Fencing.ExpectedServerRevision != nil {
		request.Fencing.ExpectedServerRevision = nil
		response, err = c.transport.DoServerRequest(ctx, path, request)
	}
	if err != nil {
		return response, newSchedulerRequestError(response, err)
	}
	c.mu.Lock()
	if response.ServerRevision > c.revision {
		c.revision = response.ServerRevision
	}
	c.mu.Unlock()
	if response.Outcome != "accepted" && response.Outcome != "completed" {
		return response, newSchedulerRequestError(response, nil)
	}
	return response, nil
}

func decodeSchedulerPayload(response ServerResponseEnvelope, target any) error {
	if len(response.Payload) == 0 {
		return errors.New("scheduler response payload is missing")
	}
	if err := json.Unmarshal(response.Payload, target); err != nil {
		return fmt.Errorf("decode scheduler response: %w", err)
	}
	return nil
}
