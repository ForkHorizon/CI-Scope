package agent

import (
	"errors"
	"time"
)

const (
	DefaultUnixSocketFrameBytes = 1 << 20
	DefaultUnixSocketTimeout    = time.Second
	DefaultControlLeaseDuration = 30 * time.Second
	MaxControlLeaseDuration     = 24 * time.Hour
)

var (
	ErrRuntimeNotStarted          = errors.New("agent runtime is not started")
	ErrControlLeaseRequired       = errors.New("active control lease is required")
	ErrExternalControlUnavailable = errors.New("external runner control is unavailable")
	ErrExternalControlAmbiguous   = errors.New("external runner control result is ambiguous")
)
