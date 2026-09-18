package agent

import (
	"strings"
	"testing"
)

func TestRunnerNameIsBoundedAndCollisionResistant(t *testing.T) {
	name := RunnerName(strings.Repeat("machine/", 20), "session", "runner")
	if len(name) > maxRunnerNameLength || strings.ContainsAny(name, "/ ") {
		t.Fatalf("unsafe runner name: %q", name)
	}
	if RunnerName("machine", "session", "a") == RunnerName("machine", "session", "b") {
		t.Fatal("runner identity suffix collided")
	}
}

func TestRunnerCommandUsesSeparateProcessGroupAndRedactsJIT(t *testing.T) {
	cmd, err := NewRunnerCommand("/runner", "secret-jit", "/workspace", map[string]string{"HOME": "/home/ci"})
	if err != nil {
		t.Fatal(err)
	}
	if cmd.SysProcAttr == nil || !cmd.SysProcAttr.Setpgid {
		t.Fatal("runner is not isolated in a process group")
	}
	if !strings.Contains(strings.Join(cmd.Env, "\x00"), "RUNNER_MANUALLY_TRAP_SIG=1") {
		t.Fatal("runner wrapper signal trap is not enabled")
	}
	if strings.Contains(RedactedRunnerCommand("/runner"), "secret-jit") {
		t.Fatal("JIT capability leaked to diagnostics")
	}
}
