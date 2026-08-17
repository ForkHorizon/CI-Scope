package agent

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestUnixSocketRuntimeRejectsMismatchedFencingContext(t *testing.T) {
	runtime, _ := runtimeForTest(t, nil)
	response := socketRequestWithContext(t, runtime, "bad-fence-1", map[string]any{"command": "status"},
		socketRequestOptions{
			session: SocketSessionContext{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1", SessionEpoch: 4},
			fencing: SocketFencingContext{LocalOwnerEpoch: 6, SessionEpoch: 4, FencingToken: "fence-1"},
		})
	if response.Outcome != "rejected" || response.Error == nil || response.Error.Code != "invalid_fencing_context" {
		t.Fatalf("response=%+v", response)
	}
}

func TestUnixSocketRuntimeRejectsWrongPeerAndOversizedFrame(t *testing.T) {
	directory, err := os.MkdirTemp("/tmp", "cs-agent-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(directory)
	path := filepath.Join(directory, "agent.sock")
	runtime, err := NewUnixSocketRuntime(UnixSocketConfig{
		Path: path, LocalEpoch: 1, ServerSessionEpoch: 1,
		Identity:         ServerMachineIdentity{MachineID: "m", BootID: "b", AgentInstanceID: "a", SessionRequestID: "r", SessionID: "s"},
		PeerUIDValidator: func(uint32) bool { return false }, MaxFrameBytes: 1024, FencingToken: "fence-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if err := runtime.Start(ctx); err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	conn, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
	_, _ = conn.Write([]byte(strings.Repeat("x", 1025) + "\n"))
	var response [1]byte
	if _, err := conn.Read(response[:]); err == nil {
		t.Fatal("wrong peer unexpectedly received a response")
	}
}
