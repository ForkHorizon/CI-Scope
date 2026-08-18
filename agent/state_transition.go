package agent

type TransitionRequest struct {
	OperationID        string
	To                 State
	ExpectedState      State
	LocalEpoch         uint64
	ServerSessionEpoch uint64
}

type TransitionResult struct {
	OperationID        string
	Applied            bool
	Stale              bool
	State              State
	LocalEpoch         uint64
	ServerSessionEpoch uint64
	Err                error
}
