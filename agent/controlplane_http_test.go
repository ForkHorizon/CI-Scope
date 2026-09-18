package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestServerRequestEnvelopeUsesWorkerWireShape(t *testing.T) {
	payload := map[string]any{"type": "session.heartbeat", "sessionId": "session-1"}
	envelope, err := NewServerRequestEnvelope(
		"request-1",
		ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1"},
		ServerFencingFields{SessionEpoch: 1, FenceToken: "fence-1"},
		payload,
	)
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if strings.Contains(text, `"session":`) || !strings.Contains(text, `"identity":`) || !strings.Contains(text, `"fenceToken":`) {
		t.Fatalf("unexpected wire shape: %s", text)
	}
	if envelope.PayloadHash == "" {
		t.Fatal("payload hash is empty")
	}
}

func TestHTTPControlPlaneSendsCredentialProofAndValidatesResponse(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/ci/v2/sessions/session-1/heartbeat" {
			t.Errorf("path = %s", r.URL.Path)
		}
		if got := r.Header.Get("x-ci-scope-credential-proof"); got != "proof-1" {
			t.Errorf("proof = %q", got)
		}
		var request ServerRequestEnvelope
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		response := ServerResponseEnvelope{ProtocolVersion: 2, RequestID: request.RequestID, OperationID: "op-1", ServerRevision: 2, Outcome: "completed", RetryAfterMs: nil, Payload: json.RawMessage(`{}`)}
		w.Header().Set("content-type", "application/json")
		_ = json.NewEncoder(w).Encode(response)
	}))
	defer server.Close()
	client, err := NewHTTPControlPlane(server.URL, server.Client(), "proof-1")
	if err != nil {
		t.Fatal(err)
	}
	request, err := NewServerRequestEnvelope("request-1", ServerMachineIdentity{MachineID: "m", BootID: "b", AgentInstanceID: "a", SessionID: "session-1"}, ServerFencingFields{SessionEpoch: 1, FenceToken: "f"}, map[string]any{"type": "session.heartbeat"})
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(context.Background(), "/api/ci/v2/sessions/session-1/heartbeat", request)
	if err != nil {
		t.Fatal(err)
	}
	if response.OperationID != "op-1" {
		t.Fatalf("operation id = %q", response.OperationID)
	}
}

func TestNewHTTPControlPlaneRequiresHTTPS(t *testing.T) {
	if _, err := NewHTTPControlPlane("http://example.test", nil, ""); err == nil {
		t.Fatal("expected HTTPS validation")
	}
}

func TestHTTPControlPlanePreservesSimpleIngressError(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("content-type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"invalid_request"}`))
	}))
	defer server.Close()
	client, err := NewHTTPControlPlane(server.URL, server.Client(), "proof-1")
	if err != nil {
		t.Fatal(err)
	}
	request, err := NewServerRequestEnvelope("request-1", ServerMachineIdentity{MachineID: "m", BootID: "b", AgentInstanceID: "a", SessionID: "session-1"}, ServerFencingFields{SessionEpoch: 1, FenceToken: "f"}, map[string]any{"type": "scheduler.reconcile"})
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(context.Background(), "/api/ci/v2/scheduler/reconcile", request)
	if err == nil || !strings.Contains(err.Error(), "invalid_request") {
		t.Fatalf("err=%v", err)
	}
	if response.Error == nil || response.Error.Code != "invalid_request" || response.RequestID != request.RequestID {
		t.Fatalf("response=%+v", response)
	}
}

func TestHTTPControlPlaneMapsNonJSONServerFailureToRetry(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("content-type", "text/html")
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte("upstream failure"))
	}))
	defer server.Close()
	client, err := NewHTTPControlPlane(server.URL, server.Client(), "proof-1")
	if err != nil {
		t.Fatal(err)
	}
	request, err := NewServerRequestEnvelope("request-1", ServerMachineIdentity{MachineID: "m", BootID: "b", AgentInstanceID: "a", SessionID: "session-1"}, ServerFencingFields{SessionEpoch: 1, FenceToken: "f"}, map[string]any{"type": "session.open"})
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(context.Background(), "/api/ci/v2/sessions/open", request)
	if err == nil || !strings.Contains(err.Error(), "http_502") {
		t.Fatalf("err=%v", err)
	}
	if response.Outcome != "retry" || response.Error == nil || response.Error.Code != "http_502" {
		t.Fatalf("response=%+v", response)
	}
}
