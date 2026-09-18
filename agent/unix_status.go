package agent

type AgentStatus struct {
	ProcessAlive          bool   `json:"processAlive"`
	SchedulerHealthy      bool   `json:"schedulerHealthy"`
	ControlLeaseActive    bool   `json:"controlLeaseActive"`
	SchedulerLeaseActive  bool   `json:"schedulerLeaseActive"`
	ServerConnected       bool   `json:"serverConnected"`
	ReadyToClaim          bool   `json:"readyToClaim"`
	Draining              bool   `json:"draining"`
	RecoveryBlocked       bool   `json:"recoveryBlocked"`
	ProjectionLagging     bool   `json:"projectionLagging"`
	State                 State  `json:"state"`
	LocalEpoch            uint64 `json:"localEpoch"`
	ServerSessionEpoch    uint64 `json:"serverSessionEpoch"`
	ControlLeaseExpiresAt int64  `json:"controlLeaseExpiresAt,omitempty"`
}

func (s AgentStatus) CanClaim() bool {
	return s.State == StateReady && s.ProcessAlive && s.SchedulerHealthy && (s.ControlLeaseActive || s.SchedulerLeaseActive) && s.ServerConnected &&
		!s.Draining && !s.RecoveryBlocked && !s.ProjectionLagging
}
