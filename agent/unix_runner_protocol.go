package agent

import (
	"context"
	"time"
)

// RunnerController is deliberately injected. The Agent does not claim to have
// stopped a runner unless the platform-specific process implementation reports
// a completed effect.
type RunnerController interface {
	EmergencyStop(context.Context, string) (RunnerStopOutcome, error)
}

type UnixSocketConfig struct {
	Path               string
	ExpectedPeerUID    uint32
	MaxFrameBytes      int
	IOTimeout          time.Duration
	LeaseDuration      time.Duration
	InitialState       State
	LocalEpoch         uint64
	ServerSessionEpoch uint64
	Identity           ServerMachineIdentity
	FencingToken       string
	PeerUIDValidator   func(uint32) bool
	Now                func() time.Time
	RandomToken        func() (string, error)
	RunnerController   RunnerController
	ProcessController  RunnerProcessController
	RunnerInstanceID   string
	ControlPlane       ServerControlPlane
	ProcessAlive       bool
	SchedulerHealthy   bool
	ServerConnected    bool
	ProjectionLagging  bool
}
