package agent

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os/exec"
	"strings"
	"syscall"
	"unicode"
)

const maxRunnerNameLength = 63

func RunnerName(machineID, sessionID, runnerInstanceID string) string {
	parts := []string{safeNamePart(machineID), safeNamePart(sessionID), safeNamePart(runnerInstanceID)}
	prefix := strings.Trim(strings.Join(parts, "-"), "-")
	digest := sha256.Sum256([]byte(machineID + "\x00" + sessionID + "\x00" + runnerInstanceID))
	suffix := hex.EncodeToString(digest[:])[:10]
	name := strings.Trim(prefix, "-") + "-" + suffix
	if len(name) > maxRunnerNameLength {
		name = strings.Trim(name[:maxRunnerNameLength], "-")
	}
	return name
}

func safeNamePart(value string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(value) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('-')
		}
	}
	return strings.Trim(b.String(), "-")
}

func NewRunnerCommand(executable, jitConfig, workspace string, environment map[string]string) (*exec.Cmd, error) {
	return NewRunnerCommandWithScript(executable, "run.sh", jitConfig, workspace, environment)
}

func NewRunnerCommandWithScript(executable, runnerScript, jitConfig, workspace string, environment map[string]string) (*exec.Cmd, error) {
	if executable == "" || jitConfig == "" || workspace == "" {
		return nil, fmt.Errorf("runner executable, JIT config and workspace are required")
	}
	if runnerScript == "" {
		return nil, fmt.Errorf("runner script is required")
	}
	cmd := exec.Command(executable, runnerScript, "--jitconfig", jitConfig)
	cmd.Dir = workspace
	cmd.Env = make([]string, 0, len(environment)+1)
	for key, value := range environment {
		cmd.Env = append(cmd.Env, key+"="+value)
	}
	// The stock wrapper's manual-trap mode forwards termination to its
	// helper process group, allowing the controller to signal the owned shell
	// directly while keeping process-group fencing fail-closed.
	cmd.Env = append(cmd.Env, "RUNNER_MANUALLY_TRAP_SIG=1")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	return cmd, nil
}

func RedactedRunnerCommand(executable string) string {
	return executable + " run.sh --jitconfig <redacted>"
}
