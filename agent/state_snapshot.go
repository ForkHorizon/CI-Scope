package agent

type StateSnapshot struct {
	State              State
	LocalEpoch         uint64
	ServerSessionEpoch uint64
}
