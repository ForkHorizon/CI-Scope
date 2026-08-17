package agent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func (c *MacOSRunnerProcessController) Start(ctx context.Context, ownership RunnerOwnership) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.checkLocked(ownership); err != nil {
		return err
	}
	if err := contextError(ctx); err != nil {
		return err
	}
	if c.process != nil {
		return ErrRunnerAlreadyRunning
	}
	if c.prepared == nil {
		return ErrRunnerNotPrepared
	}
	if err := validateConfiguredExecutable(c.config.Executable); err != nil {
		return err
	}
	jitConfig, err := os.ReadFile(c.prepared.jitPath)
	if err != nil {
		return fmt.Errorf("read private JIT config: %w", err)
	}
	if strings.TrimSpace(string(jitConfig)) == "" {
		return errors.New("private JIT config is empty")
	}
	cmd, err := NewRunnerCommandWithScript(c.prepared.executable, c.prepared.runnerScript, string(jitConfig), c.prepared.workspace, c.prepared.environment)
	if err != nil {
		return err
	}
	// The Actions listener resolves its local bin/config paths relative to the
	// runner installation, not the job workspace. Keep the workspace in the
	// JIT payload, but launch from the runner script's own directory.
	cmd.Dir = filepath.Dir(c.prepared.runnerScript)
	process, err := c.ops.start(cmd, ownership.RunnerInstanceID)
	if err != nil {
		return fmt.Errorf("start runner: %w", err)
	}
	if process == nil || process.identity.RunnerInstanceID != ownership.RunnerInstanceID {
		return errors.New("runner process returned invalid identity")
	}
	c.process = process
	return nil
}

func (c *MacOSRunnerProcessController) observeLocked(process *startedRunnerProcess) (bool, error) {
	if process == nil {
		return false, nil
	}
	alive, err := c.ops.alive(process)
	if err != nil {
		return false, err
	}
	return alive, nil
}

func waitRunner(ctx context.Context, process *startedRunnerProcess, duration time.Duration) bool {
	if process == nil {
		return true
	}
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-process.done:
		return true
	case <-timer.C:
		return false
	case <-func() <-chan struct{} {
		if ctx == nil {
			return nil
		}
		return ctx.Done()
	}():
		return false
	}
}

func (c *MacOSRunnerProcessController) Stop(ctx context.Context, ownership RunnerOwnership) (RunnerStopOutcome, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.checkLocked(ownership); err != nil {
		return RunnerStopAmbiguous, err
	}
	if err := contextError(ctx); err != nil {
		return RunnerStopAmbiguous, err
	}
	return c.stopLocked(ctx)
}

func (c *MacOSRunnerProcessController) stopLocked(ctx context.Context) (RunnerStopOutcome, error) {
	if c.process == nil {
		return RunnerStopCompleted, nil
	}
	alive, err := c.observeLocked(c.process)
	if err != nil {
		return RunnerStopAmbiguous, err
	}
	if !alive {
		c.process = nil
		return RunnerStopCompleted, nil
	}
	if err := c.ops.validateIdentity(c.process); err != nil {
		return RunnerStopAmbiguous, err
	}
	if err := c.ops.signal(c.process, syscall.SIGTERM); err != nil {
		return RunnerStopAmbiguous, err
	}
	if waitRunner(ctx, c.process, c.config.StopGracePeriod) {
		c.process = nil
		return RunnerStopCompleted, nil
	}
	if err := contextError(ctx); err != nil {
		return RunnerStopAmbiguous, err
	}
	alive, err = c.observeLocked(c.process)
	if err != nil {
		return RunnerStopAmbiguous, err
	}
	if !alive {
		c.process = nil
		return RunnerStopCompleted, nil
	}
	if err := c.ops.validateIdentity(c.process); err != nil {
		return RunnerStopAmbiguous, err
	}
	if err := c.ops.signal(c.process, syscall.SIGKILL); err != nil {
		return RunnerStopAmbiguous, err
	}
	if waitRunner(ctx, c.process, c.config.KillGracePeriod) {
		c.process = nil
		return RunnerStopCompleted, nil
	}
	return RunnerStopAmbiguous, ErrRunnerStopTimedOut
}

func removePrivateRunnerDirectory(directory string) error {
	info, err := os.Lstat(directory)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("private runner directory is not a real directory")
	}
	return os.RemoveAll(directory)
}

func (c *MacOSRunnerProcessController) Release(ctx context.Context, ownership RunnerOwnership) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.checkLocked(ownership); err != nil {
		return err
	}
	if err := contextError(ctx); err != nil {
		return err
	}
	if c.process != nil {
		alive, err := c.observeLocked(c.process)
		if err != nil {
			return err
		}
		if alive {
			return ErrRunnerProcessStillRunning
		}
		c.process = nil
	}
	if c.prepared != nil {
		if err := removePrivateRunnerDirectory(c.prepared.directory); err != nil {
			return fmt.Errorf("remove private runner directory: %w", err)
		}
		c.prepared = nil
	}
	c.claimed = false
	c.hasExpected = false
	c.expected = RunnerOwnership{}
	return nil
}

func (c *MacOSRunnerProcessController) Observe(ctx context.Context, ownership RunnerOwnership) (RunnerProcessObservation, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.checkLocked(ownership); err != nil {
		return RunnerProcessObservation{}, err
	}
	if err := contextError(ctx); err != nil {
		return RunnerProcessObservation{}, err
	}
	if c.process == nil {
		return RunnerProcessObservation{}, nil
	}
	alive, err := c.observeLocked(c.process)
	if errors.Is(err, ErrRunnerProcessOwnershipMismatch) {
		return RunnerProcessObservation{Identity: c.process.identity, Known: true, Owned: false}, err
	}
	if err != nil {
		return RunnerProcessObservation{Identity: c.process.identity, Known: true, Owned: false}, err
	}
	return RunnerProcessObservation{Identity: c.process.identity, Known: true, Alive: alive, Owned: true}, nil
}
