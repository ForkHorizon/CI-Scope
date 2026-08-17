package agent

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestLaunchdAgentPlistTemplateAndRendererKeepThrottleInterval(t *testing.T) {
	template, rendered := renderLaunchdAgentFixture(t)
	const throttle = "<key>ThrottleInterval</key><integer>300</integer>"
	if !strings.Contains(string(template), throttle) {
		t.Fatalf("agent plist template lost %s", throttle)
	}
	if !strings.Contains(rendered, throttle) {
		t.Fatalf("rendered agent plist lost %s", throttle)
	}
	if !strings.Contains(rendered, "<key>CI_SCOPE_POOL_IDENTITY</key><string>forkhorizon-production</string>") {
		t.Fatalf("rendered agent plist lost production pool identity")
	}
	if strings.Contains(rendered, "{{") {
		t.Fatalf("rendered agent plist still contains template placeholders: %s", rendered)
	}
}

func TestLaunchdWatchdogValidationRequiresRealRenderedExecutable(t *testing.T) {
	root := t.TempDir()
	watchdogPath := filepath.Join(root, "watchdog")
	if err := os.WriteFile(watchdogPath, []byte("#!/bin/sh\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	plistPath := filepath.Join(root, "watchdog.plist")
	plist := `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>ProgramArguments</key><array><string>` + watchdogPath + `</string><string>run</string></array></dict></plist>`
	if err := os.WriteFile(plistPath, []byte(plist), 0o600); err != nil {
		t.Fatal(err)
	}
	validator := filepath.Join("watchdog", "launchd", "validate-watchdog-plist.sh")
	if output, err := exec.Command("sh", validator, watchdogPath, plistPath).CombinedOutput(); err != nil {
		t.Fatalf("valid watchdog plist rejected: %v: %s", err, output)
	}
	if output, err := exec.Command("sh", validator, filepath.Join(root, "missing-watchdog"), plistPath).CombinedOutput(); err == nil {
		t.Fatalf("missing watchdog executable accepted: %s", output)
	}

	placeholder := filepath.Join(root, "placeholder.plist")
	if err := os.WriteFile(placeholder, []byte(strings.Replace(plist, watchdogPath, "{{WATCHDOG_PATH}}", 1)), 0o600); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command("sh", validator, watchdogPath, placeholder).CombinedOutput(); err == nil {
		t.Fatalf("unresolved watchdog template accepted: %s", output)
	}
}
