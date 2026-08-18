package agent

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type revisionRetryServer struct {
	calls int
}

type socketRequestOptions struct {
	session SocketSessionContext
	fencing SocketFencingContext
}

func (s *revisionRetryServer) Do(_ context.Context, _ string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	s.calls++
	if request.Fencing.ExpectedServerRevision != nil {
		return ServerResponseEnvelope{
			ProtocolVersion: ServerProtocolVersion, RequestID: request.RequestID, OperationID: request.RequestID,
			ServerRevision: 9, Outcome: "rejected", RetryAfterMs: nil,
			Error: &ServerProtocolError{Code: "invalid_request", Message: "The request is invalid.", RequestID: request.RequestID},
		}, fmt.Errorf("stale revision")
	}
	return ServerResponseEnvelope{
		ProtocolVersion: ServerProtocolVersion, RequestID: request.RequestID, OperationID: request.RequestID,
		ServerRevision: 10, Outcome: "completed", RetryAfterMs: nil, Payload: mustJSON(map[string]any{"ok": true}),
	}, nil
}

func mustJSON(value any) []byte {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return data
}

func runtimeForTest(t *testing.T, controller RunnerController) (*UnixSocketRuntime, context.CancelFunc) {
	t.Helper()
	directory, err := os.MkdirTemp("/tmp", "cs-agent-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	path := filepath.Join(directory, "agent.sock")
	now := time.Unix(1_700_000_000, 0)
	runtime, err := NewUnixSocketRuntime(UnixSocketConfig{
		Path: path, LocalEpoch: 7, ServerSessionEpoch: 4, InitialState: StateRecovering,
		Identity: ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionRequestID: "open-1", SessionID: "session-1"},
		Now:      func() time.Time { return now }, LeaseDuration: time.Minute, IOTimeout: time.Second, FencingToken: "fence-1",
		ProcessAlive: true, SchedulerHealthy: true, ServerConnected: true, RunnerController: controller,
	})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	if err := runtime.Start(ctx); err != nil {
		cancel()
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = runtime.Close(); cancel() })
	return runtime, cancel
}

func TestListenUnixSocketRecoversOwnedStaleSocket(t *testing.T) {
	path := filepath.Join("/private/tmp", fmt.Sprintf("ci-scope-stale-%d-%d.sock", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.Remove(path) })
	stale, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	stale.SetUnlinkOnClose(false)
	if err := stale.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(path); err != nil {
		t.Fatalf("stale socket was not retained for the test: %v", err)
	}

	listener, err := listenUnixSocket(path, uint32(os.Getuid()))
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if info, err := os.Lstat(path); err != nil || info.Mode()&os.ModeSocket == 0 {
		t.Fatalf("recovered path is not a Unix socket: %v", err)
	}
}

func TestAgentStatusCanClaimRequiresReadyState(t *testing.T) {
	base := AgentStatus{
		ProcessAlive: true, SchedulerHealthy: true, ControlLeaseActive: true, ServerConnected: true,
	}
	for _, state := range []State{
		StateStarting, StateRecovering, StatePausedNoControl, StateDraining, StateDormant, StateRecoveryBlocked,
	} {
		base.State = state
		if base.CanClaim() {
			t.Fatalf("state %s was claimable", state)
		}
	}
	base.State = StateReady
	if !base.CanClaim() {
		t.Fatal("ready state was not claimable")
	}
}

func TestServerCommandRetriesStaleRevisionWithoutDroppingFencing(t *testing.T) {
	server := &revisionRetryServer{}
	socketPath := filepath.Join("/private/tmp", fmt.Sprintf("ci-scope-revision-%d-%d.sock", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.Remove(socketPath) })
	runtime, err := NewUnixSocketRuntime(UnixSocketConfig{
		Path: socketPath, LocalEpoch: 7, ServerSessionEpoch: 4,
		Identity:     ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionRequestID: "open-1", SessionID: "session-1"},
		FencingToken: "fence-1", ControlPlane: server,
	})
	if err != nil {
		t.Fatal(err)
	}
	runtime.SetServerRevision(8)
	response, err := runtime.serverCommand(context.Background(), "prepare-1", "/api/ci/v2/test", map[string]any{"type": "test"})
	if err != nil {
		t.Fatal(err)
	}
	if response.Outcome != "completed" || server.calls != 2 || runtime.CurrentServerRevision() != 10 {
		t.Fatalf("response = %+v, calls = %d, revision = %d", response, server.calls, runtime.CurrentServerRevision())
	}
}

func socketRequest(t *testing.T, runtime *UnixSocketRuntime, requestID string, payload map[string]any) SocketResponseEnvelope {
	return socketRequestWithContext(t, runtime, requestID, payload, socketRequestOptions{
		session: SocketSessionContext{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1", SessionEpoch: 4},
		fencing: SocketFencingContext{LocalOwnerEpoch: 7, SessionEpoch: 4, FencingToken: "fence-1"},
	})
}

func socketRequestFrame(t *testing.T, requestID string, payload map[string]any, session SocketSessionContext, fencing SocketFencingContext) []byte {
	t.Helper()
	hash, err := HashPayload(payload)
	if err != nil {
		t.Fatal(err)
	}
	request := SocketRequestEnvelope{
		ProtocolVersion: ServerProtocolVersion, RequestID: requestID, PayloadHash: hash,
		Session: &session,
		Fencing: fencing,
	}
	request.Payload, err = json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	frame, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	return append(frame, '\n')
}

func socketRequestWithContext(t *testing.T, runtime *UnixSocketRuntime, requestID string, payload map[string]any, options socketRequestOptions) SocketResponseEnvelope {
	t.Helper()
	frame := socketRequestFrame(t, requestID, payload, options.session, options.fencing)
	var err error
	conn, err := net.Dial("unix", runtime.config.Path)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.Write(frame); err != nil {
		t.Fatal(err)
	}
	responseFrame, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		t.Fatal(err)
	}
	var response SocketResponseEnvelope
	if err := json.Unmarshal(responseFrame[:len(responseFrame)-1], &response); err != nil {
		t.Fatal(err)
	}
	return response
}
