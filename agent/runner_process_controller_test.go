package agent

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
)

func testRunnerOwnership() RunnerOwnership {
	return RunnerOwnership{
		AgentInstanceID: "agent-1", LocalOwnerEpoch: 7, ServerSessionEpoch: 4,
		FencingToken: "fence-1", RunnerInstanceID: "runner-1",
	}
}

func TestFailClosedRunnerProcessControllerNeverPerformsSideEffects(t *testing.T) {
	controller := FailClosedRunnerProcessController{}
	ownership := testRunnerOwnership()
	ctx := context.Background()

	if err := controller.Claim(ctx, ownership); !errors.Is(err, ErrRunnerProcessControlUnavailable) {
		t.Fatalf("claim error = %v", err)
	}
	if err := controller.Prepare(ctx, ownership, RunnerPrepareRequest{Executable: "/runner", JITConfig: "jit", Workspace: "/workspace"}); !errors.Is(err, ErrRunnerProcessControlUnavailable) {
		t.Fatalf("prepare error = %v", err)
	}
	if err := controller.Start(ctx, ownership); !errors.Is(err, ErrRunnerProcessControlUnavailable) {
		t.Fatalf("start error = %v", err)
	}
	outcome, err := controller.Stop(ctx, ownership)
	if outcome != RunnerStopAmbiguous || !errors.Is(err, ErrRunnerProcessControlUnavailable) {
		t.Fatalf("stop = %q, %v", outcome, err)
	}
	if err := controller.Release(ctx, ownership); !errors.Is(err, ErrRunnerProcessControlUnavailable) {
		t.Fatalf("release error = %v", err)
	}
	observation, err := controller.Observe(ctx, ownership)
	if !errors.Is(err, ErrRunnerProcessControlUnavailable) || observation.Known || observation.Alive || observation.Owned {
		t.Fatalf("observation = %+v, error = %v", observation, err)
	}
}

func TestFailClosedRunnerProcessControllerRejectsStaleOwnership(t *testing.T) {
	expected := testRunnerOwnership()
	controller, err := NewFailClosedRunnerProcessController(expected)
	if err != nil {
		t.Fatal(err)
	}

	stale := expected
	stale.LocalOwnerEpoch++
	if err := controller.Claim(context.Background(), stale); !errors.Is(err, ErrRunnerOwnershipMismatch) {
		t.Fatalf("stale claim error = %v", err)
	}
	if _, err := controller.Observe(context.Background(), stale); !errors.Is(err, ErrRunnerOwnershipMismatch) {
		t.Fatalf("stale observe error = %v", err)
	}

	missing := expected
	missing.FencingToken = ""
	if err := controller.Release(context.Background(), missing); !errors.Is(err, ErrRunnerOwnershipRequired) {
		t.Fatalf("missing ownership error = %v", err)
	}
	if err := controller.Start(context.Background(), expected); !errors.Is(err, ErrRunnerProcessControlUnavailable) {
		t.Fatalf("valid start error = %v", err)
	}
}

func TestRunnerOwnershipMatchesAllFencingAndIdentityFields(t *testing.T) {
	expected := testRunnerOwnership()
	if !expected.Matches(expected) {
		t.Fatal("identical ownership must match")
	}
	for name, mutate := range map[string]func(*RunnerOwnership){
		"agent":  func(value *RunnerOwnership) { value.AgentInstanceID = "other" },
		"local":  func(value *RunnerOwnership) { value.LocalOwnerEpoch++ },
		"server": func(value *RunnerOwnership) { value.ServerSessionEpoch++ },
		"fence":  func(value *RunnerOwnership) { value.FencingToken = "other" },
		"runner": func(value *RunnerOwnership) { value.RunnerInstanceID = "other" },
	} {
		candidate := expected
		mutate(&candidate)
		if expected.Matches(candidate) {
			t.Fatalf("%s mutation bypassed ownership fencing", name)
		}
	}
}

type fakeMacOSControllerState struct {
	alive                bool
	signals              []syscall.Signal
	startTime            int64
	processGroupID       int
	stopOnSignal         bool
	mutateGroupAfterTerm bool
	cmdArgs              []string
	cmdDir               string
	cmdEnv               []string
	done                 chan error
}

func newFakeMacOSControllerFiles(t *testing.T) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	executable := filepath.Join(root, "runner")
	if err := os.WriteFile(executable, []byte("fake executable"), 0o700); err != nil {
		t.Fatal(err)
	}
	workspace := filepath.Join(root, "workspace")
	if err := os.Mkdir(workspace, 0o700); err != nil {
		t.Fatal(err)
	}
	for _, script := range []string{filepath.Join(root, "run.sh"), filepath.Join(workspace, "run.sh")} {
		if err := os.WriteFile(script, []byte("#!/bin/bash\n"), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	tempRoot := filepath.Join(root, "tmp")
	if err := os.Mkdir(tempRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	return root, executable, tempRoot
}

func newFakeMacOSControllerState() *fakeMacOSControllerState {
	return &fakeMacOSControllerState{alive: true, startTime: 9, processGroupID: 43, stopOnSignal: true}
}

func newFakeMacOSControllerOps(state *fakeMacOSControllerState) runnerProcessOps {
	return runnerProcessOps{
		start: func(cmd *exec.Cmd, runnerInstanceID string) (*startedRunnerProcess, error) {
			state.cmdArgs = append([]string(nil), cmd.Args...)
			state.cmdDir = cmd.Dir
			state.cmdEnv = append([]string(nil), cmd.Env...)
			state.done = make(chan error)
			return &startedRunnerProcess{identity: ProcessIdentity{PID: 42, StartTime: 9, ProcessGroupID: 43, Executable: cmd.Path, RunnerInstanceID: runnerInstanceID}, done: state.done}, nil
		},
		alive: func(*startedRunnerProcess) (bool, error) { return state.alive, nil },
		validateIdentity: func(process *startedRunnerProcess) error {
			if state.startTime != process.identity.StartTime || state.processGroupID != process.identity.ProcessGroupID {
				return ErrRunnerProcessOwnershipMismatch
			}
			return nil
		},
		signal: func(_ *startedRunnerProcess, signal syscall.Signal) error {
			state.signals = append(state.signals, signal)
			if signal == syscall.SIGTERM && state.mutateGroupAfterTerm {
				state.processGroupID++
			}
			if state.stopOnSignal || signal == syscall.SIGKILL {
				state.alive = false
				close(state.done)
			}
			return nil
		},
	}
}

func newFakeMacOSController(t *testing.T) (*MacOSRunnerProcessController, RunnerOwnership, *fakeMacOSControllerState) {
	t.Helper()
	root, executable, tempRoot := newFakeMacOSControllerFiles(t)
	state := newFakeMacOSControllerState()
	ops := newFakeMacOSControllerOps(state)
	controller, err := newMacOSRunnerProcessController(MacOSRunnerProcessControllerConfig{
		Executable: executable, WorkspaceRoot: root, RunnerScript: filepath.Join(root, "run.sh"), TempRoot: tempRoot,
		Environment:        map[string]string{"HOME": filepath.Join(root, "home")},
		AllowedEnvironment: map[string]bool{"PATH": true}, StopGracePeriod: 10, KillGracePeriod: 10,
	}, ops)
	if err != nil {
		t.Fatal(err)
	}
	return controller, testRunnerOwnership(), state
}

func TestConfiguredRunnerControllerIsFailClosedWithoutExplicitConfig(t *testing.T) {
	controller, err := NewConfiguredRunnerProcessController(MacOSRunnerProcessControllerConfig{})
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := controller.(*FailClosedRunnerProcessController); !ok {
		t.Fatalf("controller type = %T", controller)
	}
	if _, err := NewConfiguredRunnerProcessController(MacOSRunnerProcessControllerConfig{Executable: "/runner"}); err == nil {
		t.Fatal("partial runner config unexpectedly accepted")
	}
}

func TestConfiguredRunnerControllerAcceptsExplicitNestedRunnerScript(t *testing.T) {
	root := t.TempDir()
	install := filepath.Join(root, "forkhorizon-org-ci")
	if err := os.Mkdir(install, 0o700); err != nil {
		t.Fatal(err)
	}
	script := filepath.Join(install, "run.sh")
	if err := os.WriteFile(script, []byte("#!/bin/bash\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	tempRoot := filepath.Join(root, "tmp")
	if err := os.Mkdir(tempRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	controller, err := NewMacOSRunnerProcessController(MacOSRunnerProcessControllerConfig{
		Executable: "/bin/bash", WorkspaceRoot: root, RunnerScript: script, TempRoot: tempRoot,
	})
	if err != nil {
		t.Fatal(err)
	}
	if controller.config.RunnerScript != script {
		t.Fatalf("runner script = %q, want %q", controller.config.RunnerScript, script)
	}
}
