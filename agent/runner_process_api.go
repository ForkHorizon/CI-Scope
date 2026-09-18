package agent

import "context"

type RunnerProcessController interface {
	Claim(context.Context, RunnerOwnership) error
	Prepare(context.Context, RunnerOwnership, RunnerPrepareRequest) error
	Start(context.Context, RunnerOwnership) error
	Stop(context.Context, RunnerOwnership) (RunnerStopOutcome, error)
	Release(context.Context, RunnerOwnership) error
	Observe(context.Context, RunnerOwnership) (RunnerProcessObservation, error)
}
