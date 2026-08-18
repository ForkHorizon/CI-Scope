package agent

import "testing"

func TestAllowlistedEnvironmentDropsInheritedCredentials(t *testing.T) {
	got := AllowlistedEnvironment(map[string]string{
		"HOME":          "/tmp/ci",
		"PATH":          "/usr/bin",
		"SSH_AUTH_SOCK": "/tmp/ssh.sock",
		"GITHUB_TOKEN":  "secret",
	}, map[string]bool{"HOME": true, "PATH": true, "SSH_AUTH_SOCK": true, "GITHUB_TOKEN": true})
	if len(got) != 2 || got["HOME"] == "" || got["PATH"] == "" {
		t.Fatalf("unexpected allowlist: %#v", got)
	}
}

func TestDefaultRunnerEnvironmentIsMinimalAndCredentialFree(t *testing.T) {
	got := DefaultRunnerEnvironment()
	if got["PATH"] == "" || got["TMPDIR"] == "" {
		t.Fatalf("runner environment lacks required system paths: %#v", got)
	}
	for key := range forbiddenEnvironmentKeys {
		if _, ok := got[key]; ok {
			t.Fatalf("runner environment contains forbidden key %q", key)
		}
	}
}
