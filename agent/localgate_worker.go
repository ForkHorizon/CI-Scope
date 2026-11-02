// Worker loop that claims queued pull requests, keeps the lease and reports the result.
package agent

import (
	"context"
	"fmt"
	"sync/atomic"
	"time"
)

const (
	localGateHeartbeatEvery = 20 * time.Second
	localGateIdleWait       = 10 * time.Second
	localGateRetryWait      = 30 * time.Second
	localGateCompleteWait   = 30 * time.Second
)

type localGateServer interface {
	Claim(ctx context.Context, leaseID string) (*LocalGateJob, error)
	Heartbeat(ctx context.Context, requestID, jobID, leaseID string) (bool, error)
	Complete(ctx context.Context, jobID, leaseID string, report LocalGateReport) error
}

// LocalGateRunner checks one job and returns the report to publish.
type LocalGateRunner interface {
	Run(ctx context.Context, job LocalGateJob) (LocalGateReport, error)
}

// LocalGateWorker claims queued pull requests and checks them one at a time.
type LocalGateWorker struct {
	Server         localGateServer
	Runner         LocalGateRunner
	HeartbeatEvery time.Duration
	newID          func(prefix string) (string, error)
	now            func() time.Time
}

func NewLocalGateWorker(server localGateServer, runner LocalGateRunner) *LocalGateWorker {
	return &LocalGateWorker{Server: server, Runner: runner, HeartbeatEvery: localGateHeartbeatEvery, newID: newSchedulerRequestID, now: time.Now}
}

// RunOnce claims and processes at most one job; it reports whether a job was found.
func (w *LocalGateWorker) RunOnce(ctx context.Context) (bool, error) {
	leaseID, err := w.newID("lease")
	if err != nil {
		return false, err
	}
	job, err := w.Server.Claim(ctx, leaseID)
	if err != nil || job == nil {
		return false, err
	}
	runCtx, stop := context.WithCancel(ctx)
	defer stop()
	var cancelled atomic.Bool
	heartbeatDone := make(chan struct{})
	go func() {
		defer close(heartbeatDone)
		w.heartbeat(runCtx, stop, job.ID, leaseID, &cancelled)
	}()
	report, runErr := w.Runner.Run(runCtx, *job)
	stop()
	<-heartbeatDone
	if ctx.Err() != nil && !cancelled.Load() {
		// The agent is shutting down: leave the lease to expire so the server queues the job again.
		return true, ctx.Err()
	}
	return true, w.complete(ctx, job.ID, leaseID, w.finalReport(report, runErr, cancelled.Load()))
}

func (w *LocalGateWorker) heartbeat(ctx context.Context, stop context.CancelFunc, jobID, leaseID string, cancelled *atomic.Bool) {
	ticker := time.NewTicker(w.HeartbeatEvery)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			requestID, err := w.newID("local-gate-heartbeat")
			if err != nil {
				continue
			}
			cancel, err := w.Server.Heartbeat(ctx, requestID, jobID, leaseID)
			if err == nil && cancel {
				cancelled.Store(true)
				stop()
				return
			}
		}
	}
}

func (w *LocalGateWorker) finalReport(report LocalGateReport, runErr error, cancelled bool) LocalGateReport {
	switch {
	case cancelled:
		return LocalGateReport{Status: "cancelled", Summary: "CI Scope: CANCELLED — the run was stopped before it finished", Checks: []LocalGateCheck{}, CompletedAt: w.now().UnixMilli()}
	case runErr != nil:
		return LocalGateReport{Status: "failed", Summary: fmt.Sprintf("CI Scope: FAILED — %s", clip(runErr.Error(), 300)), Checks: []LocalGateCheck{}, CompletedAt: w.now().UnixMilli()}
	}
	return report
}

func (w *LocalGateWorker) complete(ctx context.Context, jobID, leaseID string, report LocalGateReport) error {
	// A shutting-down agent still owes the server an answer, so completion does not depend on the run context.
	completeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), localGateCompleteWait)
	defer cancel()
	return w.Server.Complete(completeCtx, jobID, leaseID, report)
}

// Loop processes jobs until ctx ends, waiting when the queue is empty and backing off on errors.
func (w *LocalGateWorker) Loop(ctx context.Context) {
	for ctx.Err() == nil {
		found, err := w.RunOnce(ctx)
		wait := time.Duration(0)
		switch {
		case err != nil:
			wait = localGateRetryWait
		case !found:
			wait = localGateIdleWait
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(wait):
		}
	}
}
