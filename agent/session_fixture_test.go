package agent

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func newSessionTestServer(t *testing.T, paths, requestIDs *[]string) *httptest.Server {
	t.Helper()
	return httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		*paths = append(*paths, request.URL.Path)
		if request.Header.Get("x-ci-scope-credential-proof") != "device-secret" {
			t.Error("credential proof was not forwarded")
		}
		var envelope ServerRequestEnvelope
		if err := json.NewDecoder(request.Body).Decode(&envelope); err != nil {
			t.Fatal(err)
		}
		*requestIDs = append(*requestIDs, envelope.RequestID)
		if request.URL.Path == SessionOpenPath {
			if request.Header.Get("authorization") != "Bearer shadow-secret" {
				t.Error("shadow token was not forwarded")
			}
			writeSessionResponse(writer, envelope, 1, map[string]any{"sessionId": "session-1", "sessionEpoch": 7, "fenceToken": "server-fence-7"})
			return
		}
		if request.URL.Path == "/api/ci/v2/sessions/session-1/heartbeat" && envelope.Fencing.ExpectedServerRevision != nil {
			t.Error("heartbeat carried optimistic revision fencing")
		}
		writeSessionResponse(writer, envelope, 2, map[string]any{})
	}))
}

func writeSessionResponse(writer http.ResponseWriter, request ServerRequestEnvelope, revision uint64, payload any) {
	bytes, _ := json.Marshal(payload)
	writer.Header().Set("content-type", "application/json")
	writer.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(writer).Encode(ServerResponseEnvelope{ProtocolVersion: ServerProtocolVersion, RequestID: request.RequestID, OperationID: request.RequestID, ServerRevision: revision, Outcome: "accepted", RetryAfterMs: nil, Payload: bytes})
}
