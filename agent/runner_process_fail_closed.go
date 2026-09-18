package agent

import "context"

// FailClosedRunnerProcessController is the default when no explicit runner
// executable/workspace configuration is present. It performs no filesystem,
// process, signal, or network side effect.
type FailClosedRunnerProcessController struct {
	expected RunnerOwnership
}

func NewFailClosedRunnerProcessController(expected RunnerOwnership) (*FailClosedRunnerProcessController, error) {
	if expected.AgentInstanceID != "" {
		if err := expected.Validate(); err != nil {
			return nil, err
		}
	}
	return &FailClosedRunnerProcessController{expected: expected}, nil
}

func (c FailClosedRunnerProcessController) check(ownership RunnerOwnership) error {
	if err := ownership.Validate(); err != nil {
		return err
	}
	if c.expected.AgentInstanceID != "" && !ownership.Matches(c.expected) {
		return ErrRunnerOwnershipMismatch
	}
	return nil
}

func (c FailClosedRunnerProcessController) unavailable(ownership RunnerOwnership) error {
	if err := c.check(ownership); err != nil {
		return err
	}
	return ErrRunnerProcessControlUnavailable
}

func (c FailClosedRunnerProcessController) Claim(ctx context.Context, ownership RunnerOwnership) error {
	return c.unavailable(ownership)
}

func (c FailClosedRunnerProcessController) Prepare(ctx context.Context, ownership RunnerOwnership, _ RunnerPrepareRequest) error {
	return c.unavailable(ownership)
}

func (c FailClosedRunnerProcessController) Start(ctx context.Context, ownership RunnerOwnership) error {
	return c.unavailable(ownership)
}

func (c FailClosedRunnerProcessController) Stop(ctx context.Context, ownership RunnerOwnership) (RunnerStopOutcome, error) {
	return RunnerStopAmbiguous, c.unavailable(ownership)
}

func (c FailClosedRunnerProcessController) Release(ctx context.Context, ownership RunnerOwnership) error {
	return c.unavailable(ownership)
}

func (c FailClosedRunnerProcessController) Observe(ctx context.Context, ownership RunnerOwnership) (RunnerProcessObservation, error) {
	if err := c.check(ownership); err != nil {
		return RunnerProcessObservation{}, err
	}
	return RunnerProcessObservation{}, ErrRunnerProcessControlUnavailable
}
