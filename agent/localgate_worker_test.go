// Tests for the local gate worker with a fake server and runner.
package agent

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type fakeGateServer struct {
	mu        sync.Mutex
	job       *LocalGateJob
	claimErr  error
	cancel    bool
	heartbeat int
	completed []LocalGateReport
}

func (f *fakeGateServer) Claim(context.Context, string) (*LocalGateJob, error) {
	return f.job, f.claimErr
}

func (f *fakeGateServer) Heartbeat(context.Context, string, string, string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.heartbeat++
	return f.cancel, nil
}

func (f *fakeGateServer) Complete(_ context.Context, _, _ string, report LocalGateReport) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.completed = append(f.completed, report)
	return nil
}

type fakeGateRunner struct {
	report LocalGateReport
	err    error
	block  bool
}

func (f fakeGateRunner) Run(ctx context.Context, _ LocalGateJob) (LocalGateReport, error) {
	if f.block {
		<-ctx.Done()
		return LocalGateReport{}, ctx.Err()
	}
	return f.report, f.err
}

func testGateWorker(server *fakeGateServer, runner LocalGateRunner) *LocalGateWorker {
	worker := NewLocalGateWorker(server, runner)
	worker.HeartbeatEvery = 5 * time.Millisecond
	worker.now = func() time.Time { return time.UnixMilli(1000) }
	return worker
}

func TestWorkerReportsAPassingRun(t *testing.T) {
	server := &fakeGateServer{job: &LocalGateJob{ID: "job-1"}}
	report := LocalGateReport{Status: "passed", Summary: "CI Scope: PASSED", Checks: []LocalGateCheck{}}
	found, err := testGateWorker(server, fakeGateRunner{report: report}).RunOnce(context.Background())
	if err != nil || !found {
		t.Fatalf("found = %v, err = %v", found, err)
	}
	if len(server.completed) != 1 || server.completed[0].Status != "passed" {
		t.Fatalf("completed = %#v", server.completed)
	}
}

func TestWorkerDoesNothingWhenTheQueueIsEmpty(t *testing.T) {
	server := &fakeGateServer{}
	found, err := testGateWorker(server, fakeGateRunner{}).RunOnce(context.Background())
	if err != nil || found || len(server.completed) != 0 {
		t.Fatalf("found = %v, err = %v, completed = %d", found, err, len(server.completed))
	}
}

func TestWorkerReturnsClaimErrors(t *testing.T) {
	server := &fakeGateServer{claimErr: errors.New("offline")}
	if _, err := testGateWorker(server, fakeGateRunner{}).RunOnce(context.Background()); err == nil {
		t.Fatal("expected the claim error")
	}
}

func TestWorkerTurnsARunnerErrorIntoAFailedReport(t *testing.T) {
	server := &fakeGateServer{job: &LocalGateJob{ID: "job-1"}}
	_, err := testGateWorker(server, fakeGateRunner{err: errors.New("ci-gates is not at the pinned commit")}).RunOnce(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	got := server.completed[0]
	if got.Status != "failed" || got.Summary != "CI Scope: FAILED — ci-gates is not at the pinned commit" || got.CompletedAt != 1000 {
		t.Fatalf("report = %#v", got)
	}
}

func TestWorkerStopsAndReportsCancelledWhenTheServerAsks(t *testing.T) {
	server := &fakeGateServer{job: &LocalGateJob{ID: "job-1"}, cancel: true}
	found, err := testGateWorker(server, fakeGateRunner{block: true}).RunOnce(context.Background())
	if err != nil || !found {
		t.Fatalf("found = %v, err = %v", found, err)
	}
	if len(server.completed) != 1 || server.completed[0].Status != "cancelled" {
		t.Fatalf("completed = %#v", server.completed)
	}
	if server.heartbeat == 0 {
		t.Fatal("expected at least one heartbeat")
	}
}

func TestWorkerLeavesTheLeaseAloneWhenTheAgentShutsDown(t *testing.T) {
	server := &fakeGateServer{job: &LocalGateJob{ID: "job-1"}}
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(20*time.Millisecond, cancel)
	_, err := testGateWorker(server, fakeGateRunner{block: true}).RunOnce(ctx)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	if len(server.completed) != 0 {
		t.Fatalf("a shutdown must not publish a verdict, got %#v", server.completed)
	}
}

func TestLoopProcessesJobsUntilCancelled(t *testing.T) {
	server := &fakeGateServer{job: &LocalGateJob{ID: "job-1"}}
	ctx, cancel := context.WithCancel(context.Background())
	worker := testGateWorker(server, fakeGateRunner{report: LocalGateReport{Status: "passed"}})
	done := make(chan struct{})
	go func() { worker.Loop(ctx); close(done) }()
	deadline := time.After(2 * time.Second)
	for {
		server.mu.Lock()
		n := len(server.completed)
		server.mu.Unlock()
		if n >= 2 {
			break
		}
		select {
		case <-deadline:
			t.Fatal("loop did not process jobs")
		case <-time.After(5 * time.Millisecond):
		}
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("loop did not stop")
	}
}
