package agent

import "time"

type FencingToken struct {
	AgentInstanceID string
	LocalEpoch      uint64
}

type ownerRecord struct {
	AgentInstanceID string    `json:"agentInstanceId"`
	PID             int       `json:"pid"`
	AcquiredAt      time.Time `json:"acquiredAt"`
	LocalEpoch      uint64    `json:"localEpoch"`
}
