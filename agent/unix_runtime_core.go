package agent

import (
	"context"
	"net"
	"sync"
)

type UnixSocketRuntime struct {
	config UnixSocketConfig
	owner  *StateOwner

	mu                sync.Mutex
	listener          net.Listener
	ctx               context.Context
	cancel            context.CancelFunc
	closeOnce         sync.Once
	wg                sync.WaitGroup
	lease             controlLease
	schedulerLease    controlLease
	processAlive      bool
	schedulerHealthy  bool
	serverConnected   bool
	projectionLagging bool
	serverRevision    uint64
	runnerInstanceID  string
	started           bool
}
