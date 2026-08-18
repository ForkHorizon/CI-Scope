package agent

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func renderLaunchdAgentFixture(t *testing.T) ([]byte, string) {
	t.Helper()
	launchdDir := filepath.Join("watchdog", "launchd")
	template, err := os.ReadFile(filepath.Join(launchdDir, "com.forkhorizon.ci-scope.agent.plist.tmpl"))
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	fakeBin := filepath.Join(root, "bin")
	if err := os.Mkdir(fakeBin, 0o700); err != nil {
		t.Fatal(err)
	}
	for name, output := range map[string]string{"sysctl": "boot-time\n", "uuidgen": "00000000-0000-0000-0000-000000000001\n"} {
		path := filepath.Join(fakeBin, name)
		if err := os.WriteFile(path, []byte("#!/bin/sh\nprintf '%s' '"+output+"'\n"), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	agentPath := filepath.Join(root, "agent")
	if err := os.WriteFile(agentPath, []byte("#!/bin/sh\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	outputPath := filepath.Join(root, "rendered.plist")
	stateRoot := filepath.Join(root, "state")
	cmd := exec.Command("sh", filepath.Join(launchdDir, "render-agent-plist.sh"), agentPath, "https://control-plane.example", "machine-1", "credential-1", outputPath)
	cmd.Env = append(os.Environ(), "PATH="+fakeBin+string(os.PathListSeparator)+os.Getenv("PATH"), "HOME="+root, "CI_SCOPE_STATE_ROOT="+stateRoot, "CI_SCOPE_LOG_DIR="+filepath.Join(root, "logs"), "CI_SCOPE_SOCKET_PATH="+filepath.Join(stateRoot, "agent.sock"), "CI_SCOPE_RUNNER_EXECUTABLE=", "CI_SCOPE_RUNNER_WORKSPACE_ROOT=", "CI_SCOPE_RUNNER_SCRIPT=", "CI_SCOPE_RUNNER_TEMP_ROOT=")
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("render-agent-plist.sh: %v: %s", err, output)
	}
	rendered, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatal(err)
	}
	return template, string(rendered)
}
