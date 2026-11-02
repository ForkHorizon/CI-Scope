// Tests for the gate runner's subprocess isolation and pinned config version.
package agent

import (
	"context"
	"strings"
	"testing"
	"time"
)

func TestGateCommandsDoNotInheritTheAgentEnvironment(t *testing.T) {
	t.Setenv("CI_SCOPE_SECRET_TOKEN", "leak-me")
	out, err := execCommand(context.Background(), t.TempDir(), "/usr/bin/env")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(out), "CI_SCOPE_SECRET_TOKEN") || !strings.Contains(string(out), "GIT_TERMINAL_PROMPT=0") {
		t.Fatalf("unexpected environment:\n%s", out)
	}
}

func TestCancelKillsTheWholeProcessGroup(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	started := time.Now()
	_, _ = execCommand(ctx, t.TempDir(), "/bin/sh", "-c", "sleep 30 & wait")
	if elapsed := time.Since(started); elapsed > 10*time.Second {
		t.Fatalf("cancel did not stop the child tree: %s", elapsed)
	}
}

func TestRunnerPassesTheQueuedConfigVersion(t *testing.T) {
	commands := &scriptedCommands{gitHead: gatePin, cliOut: passingOutput}
	job := gateJob()
	job.ConfigVersion = 7
	if _, err := newScriptedRunner(t, commands).Run(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, call := range commands.calls {
		found = found || (strings.HasPrefix(call.line, "python3") && strings.Contains(call.line, "--config-version 7"))
	}
	if !found {
		t.Fatalf("config version not passed: %+v", commands.calls)
	}
}

func TestGateEnvironmentFindsUserLevelToolchains(t *testing.T) {
	t.Setenv("HOME", "/Users/someone")
	joined := strings.Join(gateEnvironment(), "\n")
	for _, want := range []string{"/Users/someone/.cargo/bin", "/Users/someone/.local/bin", "/opt/homebrew/bin"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("PATH is missing %s:\n%s", want, joined)
		}
	}
}
