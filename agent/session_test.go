package agent

import (
	"context"
	"testing"
)

func TestSessionLifecycleOpensHeartbeatsAndClosesWithFencing(t *testing.T) {
	var paths []string
	var requestIDs []string
	server := newSessionTestServer(t, &paths, &requestIDs)
	defer server.Close()

	plane, err := NewHTTPControlPlane(server.URL, server.Client(), "device-secret")
	if err != nil {
		t.Fatal(err)
	}
	lifecycle, err := NewSessionLifecycle(plane, SessionLifecycleConfig{
		MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", CredentialID: "credential-1",
		SessionRequestID: "open-1", SessionID: "session-1", ShadowToken: "shadow-secret",
	})
	if err != nil {
		t.Fatal(err)
	}
	opened, err := lifecycle.Open(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if opened.Identity.SessionID != "session-1" || opened.Fencing.SessionEpoch != 7 || opened.Fencing.FenceToken != "server-fence-7" {
		t.Fatalf("unexpected open info: %+v", opened)
	}
	if _, err := lifecycle.Heartbeat(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := lifecycle.Heartbeat(context.Background()); err != nil {
		t.Fatal(err)
	}
	closed, err := lifecycle.Close(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if closed.Revision != 2 {
		t.Fatalf("unexpected close revision: %+v", closed)
	}
	if len(requestIDs) != 5 || requestIDs[1] == requestIDs[2] || requestIDs[0] == requestIDs[1] {
		t.Fatalf("session requests were not uniquely identified: %v", requestIDs)
	}
	if _, open := lifecycle.Info(); open {
		t.Fatal("closed session still reported open")
	}
	if len(paths) != 5 || paths[0] != SessionOpenPath || paths[1] != "/api/ci/v2/sessions/session-1/activate" || paths[2] != "/api/ci/v2/sessions/session-1/heartbeat" || paths[3] != "/api/ci/v2/sessions/session-1/heartbeat" || paths[4] != "/api/ci/v2/sessions/session-1/close" {
		t.Fatalf("unexpected paths: %v", paths)
	}
}
