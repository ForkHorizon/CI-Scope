package agent

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

func (r *UnixSocketRuntime) runnerOwnershipFor(runnerInstanceID string) RunnerOwnership {
	return RunnerOwnership{
		AgentInstanceID: r.config.Identity.AgentInstanceID, LocalOwnerEpoch: r.config.LocalEpoch,
		ServerSessionEpoch: r.config.ServerSessionEpoch, FencingToken: r.config.FencingToken,
		RunnerInstanceID: runnerInstanceID,
	}
}

func (r *UnixSocketRuntime) parseDrainDeadline(raw json.RawMessage) (time.Time, error) {
	now := r.config.Now()
	if len(raw) == 0 {
		return now.Add(r.config.LeaseDuration), nil
	}
	var text string
	if json.Unmarshal(raw, &text) == nil {
		value, err := time.Parse(time.RFC3339Nano, text)
		if err != nil {
			return time.Time{}, err
		}
		if value.Before(now) || value.After(now.Add(MaxControlLeaseDuration)) {
			return time.Time{}, errors.New("drain deadline is outside allowed range")
		}
		return value, nil
	}
	var number float64
	if json.Unmarshal(raw, &number) != nil || number < 0 {
		return time.Time{}, errors.New("invalid drain deadline")
	}
	var value time.Time
	switch {
	case number > 1e12:
		value = time.UnixMilli(int64(number))
	case number > 1e9:
		value = time.Unix(int64(number), int64((number-float64(int64(number)))*1e9))
	default:
		value = time.Unix(978307200+int64(number), int64((number-float64(int64(number)))*1e9))
	}
	if value.Before(now) || value.After(now.Add(MaxControlLeaseDuration)) {
		return time.Time{}, errors.New("drain deadline is outside allowed range")
	}
	return value, nil
}

func (r *UnixSocketRuntime) submitTransition(ctx context.Context, operationID string, to State) TransitionResult {
	if ctx == nil {
		ctx = context.Background()
	}
	snapshot := r.owner.Snapshot()
	if snapshot.State == to {
		return TransitionResult{OperationID: operationID, Applied: true, State: snapshot.State, LocalEpoch: snapshot.LocalEpoch, ServerSessionEpoch: snapshot.ServerSessionEpoch}
	}
	resultCh := r.owner.Submit(ctx, TransitionRequest{
		OperationID: operationID, To: to, ExpectedState: snapshot.State,
		LocalEpoch: snapshot.LocalEpoch, ServerSessionEpoch: snapshot.ServerSessionEpoch,
	})
	select {
	case result := <-resultCh:
		if err := ctx.Err(); err != nil {
			return TransitionResult{OperationID: operationID, State: snapshot.State, LocalEpoch: snapshot.LocalEpoch, ServerSessionEpoch: snapshot.ServerSessionEpoch, Err: err}
		}
		return result
	case <-ctx.Done():
		return TransitionResult{OperationID: operationID, State: snapshot.State, LocalEpoch: snapshot.LocalEpoch, ServerSessionEpoch: snapshot.ServerSessionEpoch, Err: ctx.Err()}
	}
}

func (r *UnixSocketRuntime) runtimeContext() context.Context {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.ctx != nil {
		return r.ctx
	}
	return context.Background()
}

func (r *UnixSocketRuntime) SetProcessAlive(value bool) {
	r.mu.Lock()
	r.processAlive = value
	r.mu.Unlock()
}

func (r *UnixSocketRuntime) SetSchedulerHealthy(value bool) {
	r.mu.Lock()
	r.schedulerHealthy = value
	r.mu.Unlock()
}

func (r *UnixSocketRuntime) SetServerConnected(value bool) {
	r.mu.Lock()
	r.serverConnected = value
	r.mu.Unlock()
}

func (r *UnixSocketRuntime) SetProjectionLagging(value bool) {
	r.mu.Lock()
	r.projectionLagging = value
	r.mu.Unlock()
}

func (r *UnixSocketRuntime) Status() AgentStatus { return r.statusPayload() }

func (r *UnixSocketRuntime) CurrentServerRevision() uint64 {
	if r == nil {
		return 0
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.serverRevision
}

// SetServerRevision lets the session heartbeat advance the scheduler's
// optimistic-concurrency baseline even when no lifecycle command ran during
// that heartbeat interval.

func (r *UnixSocketRuntime) SetServerRevision(value uint64) {
	if r == nil || value == 0 {
		return
	}
	r.mu.Lock()
	if value > r.serverRevision {
		r.serverRevision = value
	}
	r.mu.Unlock()
}

// OwnsRunnerInstance reports whether this runtime still owns a live local
// process-controller runner. A scheduler record can survive an Agent restart,
// while the in-memory controller ownership cannot; callers use this
// distinction to enter server-side recovery instead of retrying a
// start/observe command forever.

func (r *UnixSocketRuntime) OwnsRunnerInstance(runnerID string) bool {
	if r == nil || strings.TrimSpace(runnerID) == "" {
		return false
	}
	r.mu.Lock()
	owned := r.runnerInstanceID == runnerID
	controller := r.config.ProcessController
	r.mu.Unlock()
	if !owned || controller == nil {
		return false
	}
	// Checking the process controller is important after an externally removed
	// or crashed ephemeral runner: the runtime ID can remain set until the
	// scheduler has a chance to reconcile the server state.
	observation, err := controller.Observe(context.Background(), r.runnerOwnershipFor(runnerID))
	return err == nil && observation.Known && observation.Alive && observation.Owned
}

// HasRunnerInstance distinguishes this Agent's in-memory controller claim
// from a live process. It is used only during graceful cleanup, where a
// prepared or already-stopped runner still needs a fenced Release call.

func (r *UnixSocketRuntime) HasRunnerInstance(runnerID string) bool {
	if r == nil || strings.TrimSpace(runnerID) == "" {
		return false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.runnerInstanceID == runnerID
}

func (r *UnixSocketRuntime) DoServerRequest(ctx context.Context, path string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	if r == nil || r.config.ControlPlane == nil {
		return ServerResponseEnvelope{}, ErrExternalControlUnavailable
	}
	response, err := r.config.ControlPlane.Do(ctx, path, request)
	if err != nil {
		return response, err
	}
	r.mu.Lock()
	if response.ServerRevision > r.serverRevision {
		r.serverRevision = response.ServerRevision
	}
	r.serverConnected = true
	r.mu.Unlock()
	return response, nil
}
