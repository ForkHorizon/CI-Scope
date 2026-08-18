package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestEnrollDeviceUsesIssuerHeaderAndDoesNotRequireSessionCredentialProof(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != EnrollmentPath || request.Header.Get("x-ci-scope-enrollment-issuer") != "issuer-secret" {
			t.Fatalf("unexpected enrollment request: %s %q", request.URL.Path, request.Header.Get("x-ci-scope-enrollment-issuer"))
		}
		var envelope ServerRequestEnvelope
		if err := json.NewDecoder(request.Body).Decode(&envelope); err != nil {
			t.Fatal(err)
		}
		writeSessionResponse(writer, envelope, 0, map[string]any{"credentialId": "credential-1"})
	}))
	defer server.Close()
	plane, err := NewHTTPControlPlane(server.URL, server.Client(), "")
	if err != nil {
		t.Fatal(err)
	}
	credentialID, err := EnrollDevice(context.Background(), plane, EnrollmentConfig{
		Token: "token.secret", DeviceSecret: "device-secret", CredentialID: "credential-1",
		MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionRequestID: "request-1",
		SessionID: "session-1", PoolIdentity: "runner-pool", IssuerSecret: "issuer-secret",
	})
	if err != nil || credentialID != "credential-1" {
		t.Fatalf("enrollment result = %q, error = %v", credentialID, err)
	}
}
