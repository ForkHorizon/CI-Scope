package agent

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func NewUnixSocketRuntime(config UnixSocketConfig) (*UnixSocketRuntime, error) {
	if err := validateUnixSocketPath(config.Path); err != nil {
		return nil, err
	}
	applyUnixSocketDefaults(&config)
	if err := validateUnixSocketConfig(config); err != nil {
		return nil, err
	}
	owner, err := NewStateOwner(config.InitialState, config.LocalEpoch, config.ServerSessionEpoch)
	if err != nil {
		return nil, err
	}
	return &UnixSocketRuntime{
		config:            config,
		owner:             owner,
		processAlive:      config.ProcessAlive,
		schedulerHealthy:  config.SchedulerHealthy,
		serverConnected:   config.ServerConnected,
		projectionLagging: config.ProjectionLagging,
		runnerInstanceID:  config.RunnerInstanceID,
	}, nil
}

func validateUnixSocketPath(path string) error {
	if strings.TrimSpace(path) == "" || filepath.Clean(path) != path || path == "." {
		return errors.New("unix socket path is required and must be clean")
	}
	return nil
}

func applyUnixSocketDefaults(config *UnixSocketConfig) {
	if config.MaxFrameBytes == 0 {
		config.MaxFrameBytes = DefaultUnixSocketFrameBytes
	}
	if config.IOTimeout == 0 {
		config.IOTimeout = DefaultUnixSocketTimeout
	}
	if config.LeaseDuration == 0 {
		config.LeaseDuration = DefaultControlLeaseDuration
	}
	if config.InitialState == "" {
		config.InitialState = StateRecovering
	}
	if config.Now == nil {
		config.Now = time.Now
	}
	if config.RandomToken == nil {
		config.RandomToken = randomControlToken
	}
	if config.ExpectedPeerUID == 0 {
		config.ExpectedPeerUID = uint32(os.Getuid())
	}
	if config.PeerUIDValidator == nil {
		expected := config.ExpectedPeerUID
		config.PeerUIDValidator = func(uid uint32) bool { return uid == expected }
	}
}

func validateUnixSocketConfig(config UnixSocketConfig) error {
	if config.MaxFrameBytes < 1024 || config.MaxFrameBytes > 16<<20 {
		return errors.New("unix socket frame limit is out of bounds")
	}
	if config.IOTimeout <= 0 {
		return errors.New("unix socket timeout must be positive")
	}
	if config.LeaseDuration <= 0 || config.LeaseDuration > MaxControlLeaseDuration {
		return errors.New("control lease duration is out of bounds")
	}
	if config.LocalEpoch == 0 {
		return errors.New("local epoch is required")
	}
	if config.Identity.MachineID == "" || config.Identity.BootID == "" || config.Identity.AgentInstanceID == "" || config.Identity.SessionID == "" || config.Identity.SessionRequestID == "" {
		return errors.New("machine, boot, agent, session and session request identities are required")
	}
	if config.ServerSessionEpoch == 0 {
		return errors.New("server session epoch is required")
	}
	if strings.TrimSpace(config.FencingToken) == "" {
		return errors.New("fencing token is required")
	}
	return nil
}

func randomControlToken() (string, error) {
	data := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, data); err != nil {
		return "", err
	}
	return hex.EncodeToString(data), nil
}
