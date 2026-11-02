// Tests for the local gate client payloads and request IDs.
package agent

import (
	"context"
	"encoding/json"
	"testing"
)

func newLocalGateTestClient(t *testing.T, plane *schedulerEnvelopeTestPlane) *LocalGateClient {
	t.Helper()
	client, err := NewLocalGateClient(newSchedulerTestServerClient(t, plane))
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestLocalGateClaimDecodesJobAndUsesStableRequestID(t *testing.T) {
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{
		Outcome: "completed",
		Payload: mustJSON(map[string]any{"type": "local-gates.claim", "job": map[string]any{
			"id": "job-1", "repository": "ForkHorizon/Example", "pullRequest": 7,
			"headSha": "b", "baseSha": "a", "headBranch": "feature", "baseBranch": "main",
		}}),
	}}
	job, err := newLocalGateTestClient(t, plane).Claim(context.Background(), "lease-1")
	if err != nil {
		t.Fatal(err)
	}
	if job == nil || job.ID != "job-1" || job.PullRequest != 7 || job.HeadSHA != "b" {
		t.Fatalf("job = %#v", job)
	}
	if plane.request.RequestID != "local-gate-claim.lease-1" {
		t.Fatalf("request id = %q, want it derived from the lease", plane.request.RequestID)
	}
	var payload map[string]any
	if err := json.Unmarshal(plane.request.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	if payload["type"] != "local-gates.claim" || payload["leaseId"] != "lease-1" || len(payload) != 2 {
		t.Fatalf("payload = %#v", payload)
	}
}

func TestLocalGateClaimOfAnEmptyQueueReturnsNil(t *testing.T) {
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{Outcome: "completed", Payload: mustJSON(map[string]any{"type": "local-gates.claim", "job": nil})}}
	job, err := newLocalGateTestClient(t, plane).Claim(context.Background(), "lease-2")
	if err != nil || job != nil {
		t.Fatalf("job = %#v, err = %v, want nil, nil", job, err)
	}
}

func TestLocalGateHeartbeatReportsCancel(t *testing.T) {
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{Outcome: "completed", Payload: mustJSON(map[string]any{"type": "local-gates.heartbeat", "cancel": true})}}
	cancel, err := newLocalGateTestClient(t, plane).Heartbeat(context.Background(), "hb-1", "job-1", "lease-1")
	if err != nil || !cancel {
		t.Fatalf("cancel = %v, err = %v", cancel, err)
	}
}

func TestLocalGateCompleteSendsOnlyTheAllowedFields(t *testing.T) {
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{Outcome: "completed", Payload: mustJSON(map[string]any{"type": "local-gates.complete"})}}
	report := LocalGateReport{Status: "passed", Summary: "ok", Checks: []LocalGateCheck{{ID: "code-linter", Status: "passed", Required: true}}, CompletedAt: 5}
	if err := newLocalGateTestClient(t, plane).Complete(context.Background(), "job-1", "lease-1", report); err != nil {
		t.Fatal(err)
	}
	var payload map[string]json.RawMessage
	if err := json.Unmarshal(plane.request.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"type", "jobId", "leaseId", "report"} {
		if _, ok := payload[key]; !ok {
			t.Fatalf("payload is missing %q: %s", key, plane.request.Payload)
		}
	}
	if len(payload) != 4 {
		t.Fatalf("payload has unexpected fields: %s", plane.request.Payload)
	}
	if plane.request.RequestID != "local-gate-complete.lease-1" {
		t.Fatalf("request id = %q", plane.request.RequestID)
	}
}

func TestNewLocalGateClientNeedsAServer(t *testing.T) {
	if _, err := NewLocalGateClient(nil); err == nil {
		t.Fatal("expected an error without a scheduler client")
	}
}
