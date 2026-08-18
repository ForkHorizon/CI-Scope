package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeRunnerServer struct {
	mu       sync.Mutex
	lost     map[string]bool
	paths    []string
	requests []ServerRequestEnvelope
	revision uint64
}

type runnerLifecycleFixture struct {
	runtime      *UnixSocketRuntime
	controller   *MacOSRunnerProcessController
	state        *fakeMacOSControllerState
	server       *fakeRunnerServer
	controlToken string
	correlation  map[string]any
}

func (f *fakeRunnerServer) Do(_ context.Context, path string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.paths = append(f.paths, path)
	f.requests = append(f.requests, request)
	f.revision++
	if f.lost != nil && f.lost[request.RequestID] {
		delete(f.lost, request.RequestID)
		return ServerResponseEnvelope{}, ErrResponseLost
	}
	payload := map[string]any{}
	if strings.HasSuffix(path, "/prepare-runner") {
		payload = map[string]any{"jitConfig": "jit-secret", "jitStatus": "CONFIG_READY"}
	}
	return ServerResponseEnvelope{
		ProtocolVersion: ServerProtocolVersion, RequestID: request.RequestID,
		OperationID: "operation-" + request.RequestID, ServerRevision: f.revision,
		Outcome: "completed", Payload: mustJSON(payload),
	}, nil
}

func newRunnerLifecycleFixture(t *testing.T) *runnerLifecycleFixture {
	t.Helper()
	controller, ownership, state := newFakeMacOSController(t)
	server := &fakeRunnerServer{lost: map[string]bool{"prepare-lost": true}}
	path := filepath.Join("/private/tmp", fmt.Sprintf("ci-scope-agent-%d-%d.sock", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.Remove(path) })
	runtime, err := NewUnixSocketRuntime(UnixSocketConfig{
		Path: path, LocalEpoch: ownership.LocalOwnerEpoch,
		ServerSessionEpoch: ownership.ServerSessionEpoch, InitialState: StateReady,
		Identity: ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: ownership.AgentInstanceID, SessionRequestID: "open-1", SessionID: "session-1"},
		Now:      func() time.Time { return time.Unix(1_700_000_000, 0) }, LeaseDuration: time.Minute, IOTimeout: time.Second,
		FencingToken: ownership.FencingToken, ProcessController: controller, ControlPlane: server,
	})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(func() { _ = runtime.Close(); cancel() })
	if err := runtime.Start(ctx); err != nil {
		t.Fatal(err)
	}
	acquired := socketRequest(t, runtime, "lease-runner", map[string]any{"command": "acquireControlLease", "appInstanceId": "ui-1"})
	var lease struct {
		ControlToken string `json:"controlToken"`
	}
	if err := json.Unmarshal(acquired.Payload, &lease); err != nil || lease.ControlToken == "" {
		t.Fatalf("lease payload = %s", acquired.Payload)
	}
	return &runnerLifecycleFixture{
		runtime: runtime, controller: controller, state: state, server: server, controlToken: lease.ControlToken,
		correlation: map[string]any{
			"runnerInstanceId": "runner-1", "runnerName": "runner-1", "runnerGroupId": float64(3),
			"organizationId": float64(1), "installationId": float64(2), "preparationId": "prep-1",
			"runnerAttempt": float64(1), "reservationToken": "reservation-token", "githubJobKey": nil, "runAttempt": nil,
		},
	}
}

func (f *runnerLifecycleFixture) command(t *testing.T, requestID, name string) SocketResponseEnvelope {
	t.Helper()
	return socketRequest(t, f.runtime, requestID, map[string]any{
		"command": name, "appInstanceId": "ui-1", "controlToken": f.controlToken,
		"operationId": requestID, "reservationId": "reservation-1", "runnerInstanceId": "runner-1",
		"executable": f.controller.config.Executable, "workspace": filepath.Join(f.controller.config.WorkspaceRoot, "workspace"),
		"runnerCorrelation": f.correlation,
	})
}

func assertRunnerLifecyclePaths(t *testing.T, server *fakeRunnerServer) {
	t.Helper()
	server.mu.Lock()
	paths := append([]string(nil), server.paths...)
	server.mu.Unlock()
	expectedPaths := []string{
		"/api/ci/v2/reservations/reservation-1/prepare-runner",
		"/api/ci/v2/reservations/reservation-1/prepare-runner",
		"/api/ci/v2/runner-instances/runner-1/config-ack",
		"/api/ci/v2/runner-instances/runner-1/started",
		"/api/ci/v2/runner-instances/runner-1/observed",
		"/api/ci/v2/runner-instances/runner-1/stop-requested",
		"/api/ci/v2/runner-instances/runner-1/stopped",
	}
	if len(paths) != len(expectedPaths) {
		t.Fatalf("server lifecycle paths = %#v", paths)
	}
	for index, expected := range expectedPaths {
		if paths[index] != expected {
			t.Fatalf("server lifecycle path %d = %q, want %q", index, paths[index], expected)
		}
	}
}

func TestUnixSocketRuntimeConfiguredRunnerLifecycleHandlesLostResponseAndCleansUp(t *testing.T) {
	fixture := newRunnerLifecycleFixture(t)
	controller, state := fixture.controller, fixture.state
	command := func(requestID, name string) SocketResponseEnvelope {
		return fixture.command(t, requestID, name)
	}

	lost := command("prepare-lost", "reservation.prepare")
	if lost.Outcome != "ambiguous" || lost.Error == nil || lost.Error.Code != "external_control_ambiguous" || controller.prepared != nil {
		t.Fatalf("lost prepare response=%+v prepared=%+v", lost, controller.prepared)
	}
	prepared := command("prepare-1", "reservation.prepare")
	if prepared.Outcome != "succeeded" || controller.prepared == nil || strings.Contains(string(prepared.Payload), "jit-secret") {
		t.Fatalf("prepare response=%+v prepared=%+v", prepared, controller.prepared)
	}
	privateDirectory := controller.prepared.directory
	if info, err := os.Stat(controller.prepared.jitPath); err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("JIT file metadata = %v, %v", info, err)
	}
	started := command("start-1", "runner.start")
	if started.Outcome != "succeeded" || len(state.cmdArgs) == 0 {
		t.Fatalf("start response=%+v args=%v", started, state.cmdArgs)
	}
	observed := command("observe-1", "runner.observe")
	if observed.Outcome != "succeeded" {
		t.Fatalf("observe response=%+v", observed)
	}
	stale := socketRequestWithContext(t, fixture.runtime, "stale-runner", map[string]any{
		"command": "runner.stop", "appInstanceId": "ui-1", "controlToken": fixture.controlToken,
		"runnerInstanceId": "runner-1", "runnerCorrelation": fixture.correlation,
	}, socketRequestOptions{
		session: SocketSessionContext{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1", SessionEpoch: 4},
		fencing: SocketFencingContext{LocalOwnerEpoch: 7, SessionEpoch: 4, FencingToken: "stale"},
	})
	if stale.Outcome != "rejected" || stale.Error == nil || stale.Error.Code != "invalid_fencing_context" || len(state.signals) != 0 {
		t.Fatalf("stale response=%+v signals=%v", stale, state.signals)
	}
	stopped := command("stop-1", "runner.stop")
	if stopped.Outcome != "succeeded" || len(state.signals) != 1 {
		t.Fatalf("stop response=%+v signals=%v", stopped, state.signals)
	}
	released := command("release-1", "runner.release")
	if released.Outcome != "succeeded" {
		t.Fatalf("release response=%+v", released)
	}
	if _, err := os.Stat(privateDirectory); !os.IsNotExist(err) {
		t.Fatalf("private runner directory still exists: %v", err)
	}
	assertRunnerLifecyclePaths(t, fixture.server)
}

func TestUnixSocketRuntimeOwnsRunnerInstanceRequiresLiveProcess(t *testing.T) {
	runtime, controller := schedulerTestRuntime(t, &schedulerTestPlane{})
	ownership := testRunnerOwnership()
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if err := controller.Prepare(context.Background(), ownership, RunnerPrepareRequest{
		Executable: controller.config.Executable,
		JITConfig:  "jit",
		Workspace:  filepath.Join(controller.config.WorkspaceRoot, "workspace"),
	}); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	runtime.mu.Lock()
	runtime.runnerInstanceID = ownership.RunnerInstanceID
	runtime.mu.Unlock()
	if !runtime.OwnsRunnerInstance(ownership.RunnerInstanceID) {
		t.Fatal("live runner was not considered owned")
	}
	// A process can disappear while the runtime ID remains set until the
	// scheduler reconciles the server reservation.
	controller.ops.alive = func(*startedRunnerProcess) (bool, error) { return false, nil }
	if runtime.OwnsRunnerInstance(ownership.RunnerInstanceID) {
		t.Fatal("dead runner was still considered owned")
	}
}
