package agent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type MacOSRunnerProcessControllerConfig struct {
	Executable         string
	WorkspaceRoot      string
	RunnerScript       string
	TempRoot           string
	Environment        map[string]string
	AllowedEnvironment map[string]bool
	StopGracePeriod    time.Duration
	KillGracePeriod    time.Duration
}

// MacOSRunnerProcessController implements the real local runner lifecycle.
// It is intentionally not the default: callers must provide an explicit
// executable and workspace root through NewConfiguredRunnerProcessController.
type MacOSRunnerProcessController struct {
	mu          sync.Mutex
	config      MacOSRunnerProcessControllerConfig
	ops         runnerProcessOps
	expected    RunnerOwnership
	hasExpected bool
	claimed     bool
	prepared    *preparedRunnerProcess
	process     *startedRunnerProcess
}

func NewMacOSRunnerProcessController(config MacOSRunnerProcessControllerConfig) (*MacOSRunnerProcessController, error) {
	return newMacOSRunnerProcessController(config, defaultRunnerProcessOps())
}

func newMacOSRunnerProcessController(config MacOSRunnerProcessControllerConfig, ops runnerProcessOps) (*MacOSRunnerProcessController, error) {
	config.Executable = strings.TrimSpace(config.Executable)
	config.WorkspaceRoot = strings.TrimSpace(config.WorkspaceRoot)
	config.RunnerScript = strings.TrimSpace(config.RunnerScript)
	config.TempRoot = strings.TrimSpace(config.TempRoot)
	if config.Executable == "" || !filepath.IsAbs(config.Executable) || filepath.Clean(config.Executable) != config.Executable || config.Executable == "/" {
		return nil, errors.New("runner executable must be an absolute clean path")
	}
	if config.WorkspaceRoot == "" || !filepath.IsAbs(config.WorkspaceRoot) || filepath.Clean(config.WorkspaceRoot) != config.WorkspaceRoot || config.WorkspaceRoot == "/" {
		return nil, errors.New("runner workspace root must be an absolute clean path")
	}
	if config.RunnerScript == "" || !filepath.IsAbs(config.RunnerScript) || filepath.Clean(config.RunnerScript) != config.RunnerScript || config.RunnerScript == "/" {
		return nil, errors.New("runner script must be an absolute clean path")
	}
	if err := validateRunnerScript(config.WorkspaceRoot, config.RunnerScript); err != nil {
		return nil, err
	}
	if config.TempRoot == "" {
		config.TempRoot = os.TempDir()
	}
	if !filepath.IsAbs(config.TempRoot) || filepath.Clean(config.TempRoot) != config.TempRoot || config.TempRoot == "/" {
		return nil, errors.New("runner temp root must be an absolute clean path")
	}
	if config.StopGracePeriod == 0 {
		config.StopGracePeriod = 10 * time.Second
	}
	if config.KillGracePeriod == 0 {
		config.KillGracePeriod = 2 * time.Second
	}
	if config.StopGracePeriod <= 0 || config.KillGracePeriod <= 0 {
		return nil, errors.New("runner stop grace periods must be positive")
	}
	if ops.start == nil || ops.alive == nil || ops.validateIdentity == nil || ops.signal == nil {
		return nil, errors.New("runner process operations are incomplete")
	}
	return &MacOSRunnerProcessController{config: config, ops: ops}, nil
}

// NewConfiguredRunnerProcessController preserves the fail-closed default.
// Both values are required before any real local lifecycle implementation is
// constructed; a partial configuration fails startup rather than guessing.

func NewConfiguredRunnerProcessController(config MacOSRunnerProcessControllerConfig) (RunnerProcessController, error) {
	if strings.TrimSpace(config.Executable) == "" && strings.TrimSpace(config.WorkspaceRoot) == "" {
		return NewFailClosedRunnerProcessController(RunnerOwnership{})
	}
	return NewMacOSRunnerProcessController(config)
}

func (c *MacOSRunnerProcessController) checkLocked(ownership RunnerOwnership) error {
	if err := ownership.Validate(); err != nil {
		return err
	}
	if c.hasExpected && !ownership.Matches(c.expected) {
		return ErrRunnerOwnershipMismatch
	}
	if !c.claimed {
		return ErrRunnerControllerNotClaimed
	}
	return nil
}

func contextError(ctx context.Context) error {
	if ctx == nil {
		return nil
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
		return nil
	}
}

func (c *MacOSRunnerProcessController) Claim(ctx context.Context, ownership RunnerOwnership) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := ownership.Validate(); err != nil {
		return err
	}
	if err := contextError(ctx); err != nil {
		return err
	}
	if c.hasExpected && !ownership.Matches(c.expected) {
		return ErrRunnerOwnershipMismatch
	}
	if !c.hasExpected {
		c.expected, c.hasExpected = ownership, true
	}
	c.claimed = true
	return nil
}
