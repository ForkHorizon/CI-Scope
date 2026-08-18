package agent

type SocketSessionContext struct {
	MachineID       string `json:"machineId"`
	BootID          string `json:"bootId"`
	AgentInstanceID string `json:"agentInstanceId"`
	SessionID       string `json:"sessionId"`
	SessionEpoch    uint64 `json:"sessionEpoch"`
}

type SocketFencingContext struct {
	LocalOwnerEpoch  uint64 `json:"localOwnerEpoch"`
	SessionEpoch     uint64 `json:"sessionEpoch"`
	FencingToken     string `json:"fencingToken,omitempty"`
	RunnerInstanceID string `json:"runnerInstanceId,omitempty"`
}
