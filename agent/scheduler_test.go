package agent

import (
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type schedulerTestPlane struct {
	mu              sync.Mutex
	claimCalls      int
	claimPath       string
	claimPayload    map[string]any
	emptyDispatch   bool
	prepareCalls    int
	configAckCalls  int
	statusCalls     int
	releaseCalls    int
	losePrepareOnce bool
	statusError     error
	recoverError    error
	observeError    error
	stopError       error
	status          []SchedulerStatusResponse
}

func (p *schedulerTestPlane) Do(_ context.Context, path string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	payload, err := p.handlePath(path, request)
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	return ServerResponseEnvelope{
		ProtocolVersion: ServerProtocolVersion, RequestID: request.RequestID,
		OperationID: "op-" + request.RequestID, ServerRevision: uint64(p.claimCalls + p.statusCalls + p.releaseCalls + p.prepareCalls + p.configAckCalls),
		Outcome: "completed", Payload: mustJSON(payload),
	}, nil
}

func (p *schedulerTestPlane) handlePath(path string, request ServerRequestEnvelope) (any, error) {
	switch {
	case path == SchedulerDispatchNextPath:
		return p.handleClaim(path, request), nil
	case path == SchedulerReconcilePath:
		return map[string]any{"state": "prepared", "jitConfig": "jit-after-lost-response", "jitStatus": "CONFIG_READY"}, nil
	case strings.HasSuffix(path, "/status"):
		return p.handleStatus()
	case strings.HasSuffix(path, "/release"):
		p.releaseCalls++
		return SchedulerStatusResponse{State: "released"}, nil
	case strings.HasSuffix(path, "/recover"):
		if p.recoverError != nil {
			return nil, p.recoverError
		}
		return SchedulerStatusResponse{State: "released"}, nil
	case strings.HasSuffix(path, "/prepare-runner"):
		return p.handlePrepare()
	case strings.HasSuffix(path, "/config-ack"):
		p.configAckCalls++
		return map[string]any{}, nil
	case strings.HasSuffix(path, "/observed"):
		return map[string]any{}, p.observeError
	case strings.HasSuffix(path, "/stop-requested"):
		return map[string]any{}, p.stopError
	}
	return map[string]any{}, nil
}

func (p *schedulerTestPlane) handleClaim(path string, request ServerRequestEnvelope) any {
	p.claimCalls++
	p.claimPath = path
	_ = json.Unmarshal(request.Payload, &p.claimPayload)
	if p.emptyDispatch {
		return map[string]any{"type": "dispatch.next", "dispatch": nil}
	} else if p.claimCalls == 1 {
		return map[string]any{"claimed": true, "reservation": schedulerTestReservation()}
	}
	return map[string]any{"claimed": false}
}

func (p *schedulerTestPlane) handleStatus() (any, error) {
	p.statusCalls++
	if p.statusError != nil {
		return nil, p.statusError
	}
	if len(p.status) > 0 {
		res := p.status[0]
		p.status = p.status[1:]
		return res, nil
	}
	return SchedulerStatusResponse{State: "running", JobState: "in_progress"}, nil
}

func (p *schedulerTestPlane) handlePrepare() (any, error) {
	p.prepareCalls++
	if p.losePrepareOnce {
		p.losePrepareOnce = false
		return nil, ErrResponseLost
	}
	return map[string]any{"jitConfig": "jit-from-server", "jitStatus": "CONFIG_READY"}, nil
}

func schedulerTestReservation() SchedulerReservation {
	return SchedulerReservation{
		ReservationID: "reservation-1", ReservationToken: "token-1", ExpiresAt: "2099-01-01T00:00:00Z",
		Correlation: SchedulerRunnerCorrelation{
			RunnerInstanceID: "runner-1", RunnerName: "runner-1", RunnerGroupID: 3,
			OrganizationID: 1, InstallationID: 2, PreparationID: "preparation-1",
			RunnerAttempt: 1, ReservationToken: "token-1", GitHubJobKey: "job-1", RunAttempt: 1,
		},
	}
}

func schedulerTestRuntime(t *testing.T, plane *schedulerTestPlane) (*UnixSocketRuntime, *MacOSRunnerProcessController) {
	t.Helper()
	controller, _, _ := newFakeMacOSController(t)
	runtime, err := NewUnixSocketRuntime(UnixSocketConfig{
		Path: filepath.Join(t.TempDir(), "agent.sock"), LocalEpoch: 7, ServerSessionEpoch: 4,
		InitialState: StateReady, Identity: ServerMachineIdentity{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionRequestID: "open-1", SessionID: "session-1"},
		Now: func() time.Time { return time.Unix(1_700_000_000, 0) }, LeaseDuration: time.Minute,
		FencingToken: "fence-1", ProcessController: controller, ControlPlane: plane,
		ProcessAlive: true, SchedulerHealthy: true, ServerConnected: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	lease := runtime.acquireLease(SocketRequestEnvelope{RequestID: "lease", PayloadHash: "hash"}, socketCommand{AppInstanceID: "ui-1"})
	if lease.Outcome != "succeeded" {
		t.Fatalf("lease response = %+v", lease)
	}
	return runtime, controller
}

func newTestScheduler(t *testing.T, runtime *UnixSocketRuntime, plane *schedulerTestPlane) (*HeadlessScheduler, *SQLiteStore) {
	t.Helper()
	store, err := OpenSQLiteStore(filepath.Join(t.TempDir(), "agent.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	server, err := NewSchedulerServerClient(runtime, runtime.config.Identity, ServerFencingFields{SessionEpoch: 4, FenceToken: "fence-1"}, 0)
	if err != nil {
		t.Fatal(err)
	}
	controller := runtime.config.ProcessController.(*MacOSRunnerProcessController)
	scheduler, err := NewHeadlessScheduler(HeadlessSchedulerConfig{
		Runtime: runtime, Store: store, Server: server, PoolIdentity: "shadow-default",
		RunnerExecutable: controller.config.Executable, RunnerWorkspace: controller.config.WorkspaceRoot,
		PollInterval: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	return scheduler, store
}

func TestHeadlessSchedulerClaimsOnceAndReleasesAfterTerminal(t *testing.T) {
	plane := &schedulerTestPlane{status: []SchedulerStatusResponse{
		{State: "running", JobState: "in_progress"},
		{State: "completed", JobState: "completed", Terminal: true},
		{State: "completed", JobState: "completed", Terminal: true},
	}}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	for i := 0; i < 8; i++ {
		if err := scheduler.RunOnce(context.Background()); err != nil {
			runtime.mu.Lock()
			lease := runtime.lease
			runtime.mu.Unlock()
			t.Fatalf("RunOnce %d: %v lease=%+v", i, err, lease)
		}
	}
	plane.mu.Lock()
	claimCalls, releaseCalls := plane.claimCalls, plane.releaseCalls
	plane.mu.Unlock()
	if claimCalls != 1 {
		t.Fatalf("claim calls = %d, want one while reservation is active", claimCalls)
	}
	if releaseCalls != 1 {
		t.Fatalf("release calls = %d, want one after terminal without local removal evidence", releaseCalls)
	}
	if plane.claimPath != SchedulerDispatchNextPath {
		t.Fatalf("claim path = %q, want canonical dispatch path", plane.claimPath)
	}
	if got := plane.claimPayload["type"]; got != "dispatch.next" {
		t.Fatalf("claim payload type = %#v, want dispatch.next", got)
	}
	if _, ok := plane.claimPayload["poolIdentity"]; ok {
		t.Fatal("canonical dispatch.next payload unexpectedly included poolIdentity")
	}
}

func TestHeadlessSchedulerTreatsEmptyDispatchAsNoWork(t *testing.T) {
	plane := &schedulerTestPlane{emptyDispatch: true}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, store := newTestScheduler(t, runtime, plane)
	if err := scheduler.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if scheduler.current() != nil {
		t.Fatal("empty dispatch created an active reservation")
	}
	intents, err := store.PendingIntents(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(intents) != 0 {
		t.Fatalf("pending claim intents = %d, want zero after empty dispatch acknowledgement", len(intents))
	}
}

func TestHeadlessSchedulerChecksTerminalStatusBeforeRunnerObserve(t *testing.T) {
	plane := &schedulerTestPlane{status: []SchedulerStatusResponse{{State: "completed", JobState: "completed", Terminal: true}}}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	record := &schedulerRecord{Reservation: schedulerTestReservation(), Phase: schedulerPhaseRunning}
	runtime.mu.Lock()
	runtime.runnerInstanceID = record.Reservation.Correlation.RunnerInstanceID
	runtime.mu.Unlock()
	command, err := scheduler.runnerCommand(record)
	if err != nil {
		t.Fatal(err)
	}
	if err := scheduler.running(context.Background(), record, command); err != nil {
		t.Fatal(err)
	}
	if record.Phase != schedulerPhaseStopping {
		t.Fatalf("running phase = %q, want stopping", record.Phase)
	}
	plane.mu.Lock()
	statusCalls := plane.statusCalls
	plane.mu.Unlock()
	if statusCalls != 1 {
		t.Fatalf("status calls = %d, want one terminal check", statusCalls)
	}
}
