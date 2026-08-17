package agent

// RunnerOwnership is the complete fencing context required for every runner
// side effect. A controller must not infer ownership from a PID or runner ID.
type RunnerOwnership struct {
	AgentInstanceID    string
	LocalOwnerEpoch    uint64
	ServerSessionEpoch uint64
	FencingToken       string
	RunnerInstanceID   string
}

func (o RunnerOwnership) Validate() error {
	if o.AgentInstanceID == "" || o.LocalOwnerEpoch == 0 || o.ServerSessionEpoch == 0 ||
		o.FencingToken == "" || o.RunnerInstanceID == "" {
		return ErrRunnerOwnershipRequired
	}
	return nil
}

func (o RunnerOwnership) Matches(expected RunnerOwnership) bool {
	return o.AgentInstanceID == expected.AgentInstanceID &&
		o.LocalOwnerEpoch == expected.LocalOwnerEpoch &&
		o.ServerSessionEpoch == expected.ServerSessionEpoch &&
		o.FencingToken == expected.FencingToken &&
		o.RunnerInstanceID == expected.RunnerInstanceID
}
