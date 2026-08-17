package agent

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

func defaultRunnerProcessOps() runnerProcessOps {
	return runnerProcessOps{
		start:            startRunnerCommand,
		alive:            runnerProcessAlive,
		validateIdentity: validateRunnerProcessIdentity,
		signal:           signalRunnerProcess,
	}
}

func readRunnerStartTime(pid int) (int64, error) {
	var lastErr error
	for attempt := 0; attempt < 20; attempt++ {
		startTime, err := processStartTime(pid)
		if err == nil {
			return startTime, nil
		}
		lastErr = err
		if !errors.Is(err, os.ErrNotExist) && !errors.Is(err, syscall.ESRCH) {
			return 0, err
		}
		if probeErr := syscall.Kill(pid, 0); probeErr != nil {
			return 0, err
		}
		time.Sleep(10 * time.Millisecond)
	}
	return 0, lastErr
}

func startRunnerCommand(cmd *exec.Cmd, runnerInstanceID string) (*startedRunnerProcess, error) {
	// Keep the runner in its own process group. The runner wrapper uses its
	// manually-trapped mode so a direct signal to the owned shell also tears
	// down its helper process without ever signalling the Agent's group.
	if cmd.SysProcAttr == nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	pid := cmd.Process.Pid
	pgid, err := syscall.Getpgid(pid)
	if err != nil {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
		return nil, fmt.Errorf("read runner process group: %w", err)
	}
	startTime, err := readRunnerStartTime(pid)
	if err != nil {
		// The child may have exited before its process metadata became
		// observable. Kill only the exact child here; using a negative PGID
		// on an inherited group could kill the Agent itself.
		_ = cmd.Process.Kill()
		_, waitErr := cmd.Process.Wait()
		if waitErr != nil {
			return nil, fmt.Errorf("read runner process start time: %w (runner exited: %v)", err, waitErr)
		}
		return nil, fmt.Errorf("read runner process start time: %w (runner exited cleanly)", err)
	}
	process := &startedRunnerProcess{identity: ProcessIdentity{PID: pid, StartTime: startTime, ProcessGroupID: pgid, Executable: cmd.Path, RunnerInstanceID: runnerInstanceID}, process: cmd.Process, done: make(chan error, 1)}
	go func() {
		process.done <- cmd.Wait()
		close(process.done)
	}()
	return process, nil
}

func runnerProcessAlive(process *startedRunnerProcess) (bool, error) {
	if process == nil || process.process == nil {
		return false, nil
	}
	if err := validateRunnerProcessIdentity(process); err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ESRCH) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func validateRunnerProcessIdentity(process *startedRunnerProcess) error {
	if process == nil || process.process == nil || process.identity.PID <= 1 {
		return errors.New("runner process identity is invalid")
	}
	if err := syscall.Kill(process.identity.PID, 0); err != nil && !errors.Is(err, syscall.EPERM) {
		return err
	}
	startTime, err := processStartTime(process.identity.PID)
	if err != nil {
		return err
	}
	pgid, err := syscall.Getpgid(process.identity.PID)
	if err != nil {
		return err
	}
	if startTime != process.identity.StartTime || pgid != process.identity.ProcessGroupID {
		return ErrRunnerProcessOwnershipMismatch
	}
	return nil
}

func signalRunnerProcess(process *startedRunnerProcess, signal syscall.Signal) error {
	if err := validateRunnerProcessIdentity(process); err != nil {
		return err
	}
	if process.identity.ProcessGroupID > 1 {
		if currentGroup, err := syscall.Getpgid(os.Getpid()); err == nil && currentGroup != process.identity.ProcessGroupID {
			return syscall.Kill(-process.identity.ProcessGroupID, signal)
		}
	}
	return syscall.Kill(process.identity.PID, signal)
}
