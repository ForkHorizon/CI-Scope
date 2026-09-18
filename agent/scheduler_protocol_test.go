package agent

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"
)

func TestSchedulerRunnerCorrelationMarshalsUnboundPairAsNull(t *testing.T) {
	encoded, err := json.Marshal(SchedulerRunnerCorrelation{RunnerInstanceID: "runner-1", RunnerName: "runner-1"})
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"githubJobKey", "runAttempt"} {
		value, ok := decoded[key]
		if !ok || value != nil {
			t.Fatalf("%s = %#v, want explicit null", key, value)
		}
	}
}

type schedulerEnvelopeTestPlane struct {
	request  ServerRequestEnvelope
	response ServerResponseEnvelope
}

func (p *schedulerEnvelopeTestPlane) DoServerRequest(_ context.Context, _ string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	p.request = request
	return p.response, nil
}

func newSchedulerTestServerClient(t *testing.T, plane *schedulerEnvelopeTestPlane) *SchedulerServerClient {
	t.Helper()
	client, err := NewSchedulerServerClient(
		plane,
		ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1"},
		ServerFencingFields{SessionEpoch: 1, FenceToken: "fence-1"},
		0,
	)
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestSchedulerRegisterSerializesUnboundPairAsExplicitNull(t *testing.T) {
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{Outcome: "completed"}}
	client := newSchedulerTestServerClient(t, plane)
	reservation := schedulerTestReservation()
	reservation.Correlation.GitHubJobKey = ""
	reservation.Correlation.RunAttempt = 0
	if err := client.Register(context.Background(), "register.runner-1", reservation); err != nil {
		t.Fatal(err)
	}
	var payload struct {
		RunnerCorrelation map[string]any `json:"runnerCorrelation"`
	}
	if err := json.Unmarshal(plane.request.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"githubJobKey", "runAttempt"} {
		value, ok := payload.RunnerCorrelation[key]
		if !ok || value != nil {
			t.Fatalf("runnerCorrelation.%s = %#v, want explicit null", key, value)
		}
	}
}

func TestSchedulerClaimResponseDecodesCanonicalDispatch(t *testing.T) {
	data := mustJSON(map[string]any{
		"type": "dispatch.next",
		"dispatch": map[string]any{
			"status": "claimed", "reservationId": "reservation-1", "expiresAt": "2099-01-01T00:00:00Z",
			"runnerCorrelation": map[string]any{
				"runnerInstanceId": "runner-1", "runnerName": "runner-1", "runnerGroupId": 3,
				"organizationId": 1, "installationId": 2, "preparationId": "preparation-1",
				"runnerAttempt": 1, "reservationToken": "token-1", "githubJobKey": nil, "runAttempt": nil,
			},
		},
	})
	var result SchedulerClaimResponse
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	if !result.Claimed {
		t.Fatal("canonical claimed dispatch was treated as empty")
	}
	if err := validateSchedulerReservation(result.Reservation); err != nil {
		t.Fatal(err)
	}

	var empty SchedulerClaimResponse
	if err := json.Unmarshal(mustJSON(map[string]any{"type": "dispatch.next", "dispatch": nil}), &empty); err != nil {
		t.Fatal(err)
	}
	if empty.Claimed || empty.Reservation.ReservationID != "" {
		t.Fatalf("empty dispatch decoded as reservation: %+v", empty)
	}
}

func TestSchedulerRetryUsesRetryAfterAndBoundsTransientBackoff(t *testing.T) {
	retryAfter := uint64(1500)
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{Outcome: "retry", RetryAfterMs: &retryAfter}}
	client := newSchedulerTestServerClient(t, plane)
	err := client.Register(context.Background(), "register.runner-1", schedulerTestReservation())
	var requestErr *schedulerRequestError
	if err == nil || !errors.As(err, &requestErr) {
		t.Fatalf("err = %v, want scheduler request error", err)
	}
	scheduler := &HeadlessScheduler{config: HeadlessSchedulerConfig{PollInterval: 100 * time.Millisecond}}
	if got := scheduler.nextRunDelay(err); got != 1500*time.Millisecond {
		t.Fatalf("RetryAfter delay = %s, want 1.5s", got)
	}

	transient := newSchedulerRequestError(ServerResponseEnvelope{Outcome: "retry"}, errors.New("HTTP 503"))
	wants := []time.Duration{time.Second, 2 * time.Second, 4 * time.Second, 8 * time.Second, 16 * time.Second, 30 * time.Second}
	for _, want := range wants {
		if got := scheduler.nextRunDelay(transient); got != want {
			t.Fatalf("backoff = %s, want %s", got, want)
		}
	}
	if got := scheduler.nextRunDelay(transient); got != schedulerRetryMax {
		t.Fatalf("backoff cap = %s, want %s", got, schedulerRetryMax)
	}
	if got := scheduler.nextRunDelay(nil); got != scheduler.config.PollInterval {
		t.Fatalf("successful poll delay = %s, want %s", got, scheduler.config.PollInterval)
	}
}

type schedulerRevisionRetryPlane struct {
	requests []ServerRequestEnvelope
}

func (p *schedulerRevisionRetryPlane) DoServerRequest(_ context.Context, _ string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	p.requests = append(p.requests, request)
	if len(p.requests) == 1 {
		return ServerResponseEnvelope{
			Outcome: "rejected",
			Error:   &ServerProtocolError{Code: "invalid_request", RequestID: request.RequestID},
		}, errors.New("stale server revision")
	}
	return ServerResponseEnvelope{Outcome: "completed", ServerRevision: 4, Payload: mustJSON(map[string]any{"state": "released"})}, nil
}

func TestSchedulerMutationRetriesOnceWithoutStaleRevisionFence(t *testing.T) {
	plane := &schedulerRevisionRetryPlane{}
	client, err := NewSchedulerServerClient(
		plane,
		ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1"},
		ServerFencingFields{SessionEpoch: 1, FenceToken: "fence-1"},
		3,
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.Release(context.Background(), "release.reservation-1", schedulerTestReservation()); err != nil {
		t.Fatal(err)
	}
	if len(plane.requests) != 2 {
		t.Fatalf("request count = %d, want one retry", len(plane.requests))
	}
	if plane.requests[0].Fencing.ExpectedServerRevision == nil {
		t.Fatal("first request did not carry optimistic revision")
	}
	if plane.requests[1].Fencing.ExpectedServerRevision != nil {
		t.Fatal("retry retained stale optimistic revision")
	}
}

func TestSchedulerNonSucceededSocketOutcomePreservesRetryBackoff(t *testing.T) {
	retryAfter := uint64(2500)
	err := newSchedulerSocketResponseError(SocketResponseEnvelope{
		Outcome:      "ambiguous",
		RetryAfterMs: &retryAfter,
	})
	if err == nil {
		t.Fatal("non-succeeded socket outcome returned nil error")
	}
	scheduler := &HeadlessScheduler{config: HeadlessSchedulerConfig{PollInterval: time.Second}}
	if got := scheduler.nextRunDelay(err); got != 2500*time.Millisecond {
		t.Fatalf("retry delay = %s, want 2.5s", got)
	}
}
