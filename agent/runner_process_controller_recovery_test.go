package agent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestMacOSRunnerProcessControllerBlocksSIGTERMOnStartTimeMismatch(t *testing.T) {
	controller, ownership, state := newFakeMacOSController(t)
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	request := RunnerPrepareRequest{Executable: controller.config.Executable, JITConfig: "jit", Workspace: filepath.Join(controller.config.WorkspaceRoot, "workspace")}
	if err := controller.Prepare(context.Background(), ownership, request); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	state.startTime++

	outcome, err := controller.Stop(context.Background(), ownership)
	if outcome != RunnerStopAmbiguous || !errors.Is(err, ErrRunnerProcessOwnershipMismatch) {
		t.Fatalf("stop = %q, %v", outcome, err)
	}
	if len(state.signals) != 0 {
		t.Fatalf("signals = %v, want none", state.signals)
	}
}

func TestMacOSRunnerProcessControllerBlocksSIGKILLOnProcessGroupMismatch(t *testing.T) {
	controller, ownership, state := newFakeMacOSController(t)
	controller.config.StopGracePeriod = time.Nanosecond
	state.stopOnSignal = false
	state.mutateGroupAfterTerm = true
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	request := RunnerPrepareRequest{Executable: controller.config.Executable, JITConfig: "jit", Workspace: filepath.Join(controller.config.WorkspaceRoot, "workspace")}
	if err := controller.Prepare(context.Background(), ownership, request); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}

	outcome, err := controller.Stop(context.Background(), ownership)
	if outcome != RunnerStopAmbiguous || !errors.Is(err, ErrRunnerProcessOwnershipMismatch) {
		t.Fatalf("stop = %q, %v", outcome, err)
	}
	if len(state.signals) != 1 || state.signals[0] != syscall.SIGTERM {
		t.Fatalf("signals = %v, want only SIGTERM", state.signals)
	}
}

func TestMacOSRunnerProcessControllerLifecycleUsesPrivateJITAndFencing(t *testing.T) {
	controller, ownership, state := newFakeMacOSController(t)
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	request := RunnerPrepareRequest{Executable: controller.config.Executable, JITConfig: "jit-secret", Workspace: filepath.Join(controller.config.WorkspaceRoot, "workspace"), Environment: map[string]string{"PATH": "/usr/bin", "GITHUB_TOKEN": "must-not-pass"}}
	if err := controller.Prepare(context.Background(), ownership, request); err != nil {
		t.Fatal(err)
	}
	prepared := controller.prepared
	info, err := os.Stat(prepared.jitPath)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("private JIT metadata = %v, %v", info, err)
	}
	content, err := os.ReadFile(prepared.jitPath)
	if err != nil || string(content) != "jit-secret" {
		t.Fatalf("private JIT content = %q, %v", content, err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if len(state.cmdArgs) != 4 || state.cmdArgs[0] != controller.config.Executable || state.cmdArgs[1] != prepared.runnerScript || state.cmdArgs[2] != "--jitconfig" || state.cmdArgs[3] != "jit-secret" {
		t.Fatalf("runner args = %#v", state.cmdArgs)
	}
	if state.cmdDir != filepath.Dir(prepared.runnerScript) {
		t.Fatalf("runner working directory = %q, want %q", state.cmdDir, filepath.Dir(prepared.runnerScript))
	}
	for _, value := range state.cmdEnv {
		if value == "must-not-pass" {
			t.Fatal("forbidden credential entered runner environment")
		}
	}
	observation, err := controller.Observe(context.Background(), ownership)
	if err != nil || !observation.Known || !observation.Alive || !observation.Owned {
		t.Fatalf("observation = %+v, error = %v", observation, err)
	}
	outcome, err := controller.Stop(context.Background(), ownership)
	if err != nil || outcome != RunnerStopCompleted || len(state.signals) != 1 {
		t.Fatalf("stop = %q, %v, signals=%v", outcome, err, state.signals)
	}
	if err := controller.Release(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(prepared.directory); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("private runner directory still exists: %v", err)
	}
}

func TestMacOSRunnerProcessControllerRejectsStaleOwnershipOnEveryOperation(t *testing.T) {
	controller, ownership, _ := newFakeMacOSController(t)
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	stale := ownership
	stale.FencingToken = "stale"
	request := RunnerPrepareRequest{Executable: controller.config.Executable, JITConfig: "jit", Workspace: filepath.Join(controller.config.WorkspaceRoot, "workspace")}
	checks := []struct {
		name string
		call func() error
	}{
		{"prepare", func() error { return controller.Prepare(context.Background(), stale, request) }},
		{"start", func() error { return controller.Start(context.Background(), stale) }},
		{"stop", func() error { _, err := controller.Stop(context.Background(), stale); return err }},
		{"release", func() error { return controller.Release(context.Background(), stale) }},
		{"observe", func() error { _, err := controller.Observe(context.Background(), stale); return err }},
	}
	for _, check := range checks {
		t.Run(check.name, func(t *testing.T) {
			if err := check.call(); !errors.Is(err, ErrRunnerOwnershipMismatch) {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

func TestMacOSRunnerProcessControllerCanRestartAfterFencedRelease(t *testing.T) {
	controller, ownership, _ := newFakeMacOSController(t)
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	request := RunnerPrepareRequest{
		Executable: controller.config.Executable,
		JITConfig:  "first-jit",
		Workspace:  filepath.Join(controller.config.WorkspaceRoot, "workspace"),
	}
	if err := controller.Prepare(context.Background(), ownership, request); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if _, err := controller.Stop(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if err := controller.Release(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}

	next := ownership
	next.LocalOwnerEpoch++
	next.FencingToken = "fence-2"
	next.RunnerInstanceID = "runner-2"
	if err := controller.Claim(context.Background(), next); err != nil {
		t.Fatal(err)
	}
	request.JITConfig = "second-jit"
	request.Executable = controller.config.Executable
	if err := controller.Prepare(context.Background(), next, request); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), next); err != nil {
		t.Fatal(err)
	}
	if _, err := controller.Stop(context.Background(), next); err != nil {
		t.Fatal(err)
	}
	if err := controller.Release(context.Background(), next); err != nil {
		t.Fatal(err)
	}
}
