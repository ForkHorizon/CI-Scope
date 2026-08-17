package agent

import "testing"

func TestLoadBootstrapConfigRequiresHTTPSAndCredentials(t *testing.T) {
	env := map[string]string{}
	get := func(key string) string { return env[key] }
	if _, err := LoadBootstrapConfig(get); err == nil {
		t.Fatal("missing configuration unexpectedly accepted")
	}
	env = map[string]string{
		"CI_SCOPE_CONTROL_PLANE_URL": "http://example.test",
		"CI_SCOPE_CREDENTIAL_PROOF":  "proof",
		"CI_SCOPE_V2_SHADOW_TOKEN":   "shadow",
		"CI_SCOPE_MACHINE_ID":        "machine", "CI_SCOPE_BOOT_ID": "boot", "CI_SCOPE_AGENT_INSTANCE_ID": "agent",
		"CI_SCOPE_CREDENTIAL_ID": "credential", "CI_SCOPE_SESSION_REQUEST_ID": "request",
		"CI_SCOPE_SOCKET_PATH": "/tmp/ci-scope/agent.sock", "CI_SCOPE_STATE_ROOT": "/tmp/ci-scope/state",
	}
	if _, err := LoadBootstrapConfig(get); err == nil {
		t.Fatal("HTTP control plane unexpectedly accepted")
	}
}

func TestLoadBootstrapConfigAcceptsStrictStagingValues(t *testing.T) {
	env := map[string]string{
		"CI_SCOPE_CONTROL_PLANE_URL": "https://example.test",
		"CI_SCOPE_CREDENTIAL_PROOF":  "proof",
		"CI_SCOPE_V2_SHADOW_TOKEN":   "shadow",
		"CI_SCOPE_MACHINE_ID":        "machine", "CI_SCOPE_BOOT_ID": "boot", "CI_SCOPE_AGENT_INSTANCE_ID": "agent",
		"CI_SCOPE_CREDENTIAL_ID": "credential", "CI_SCOPE_SESSION_REQUEST_ID": "request",
		"CI_SCOPE_SOCKET_PATH": "/tmp/ci-scope/agent.sock", "CI_SCOPE_STATE_ROOT": "/tmp/ci-scope/state",
		"CI_SCOPE_HEARTBEAT_INTERVAL_MS": "5000", "CI_SCOPE_HTTP_TIMEOUT_MS": "2000",
	}
	config, err := LoadBootstrapConfig(func(key string) string { return env[key] })
	if err != nil {
		t.Fatal(err)
	}
	if config.HeartbeatInterval.Milliseconds() != 5000 || config.HTTPTimeout.Milliseconds() != 2000 {
		t.Fatalf("unexpected timing config: %+v", config)
	}
}

func TestLoadBootstrapConfigAcceptsPoolIdentityWithoutEnrollment(t *testing.T) {
	env := map[string]string{
		"CI_SCOPE_CONTROL_PLANE_URL": "https://example.test",
		"CI_SCOPE_CREDENTIAL_PROOF":  "proof",
		"CI_SCOPE_V2_SHADOW_TOKEN":   "shadow",
		"CI_SCOPE_MACHINE_ID":        "machine", "CI_SCOPE_BOOT_ID": "boot", "CI_SCOPE_AGENT_INSTANCE_ID": "agent",
		"CI_SCOPE_CREDENTIAL_ID": "credential", "CI_SCOPE_SESSION_REQUEST_ID": "request",
		"CI_SCOPE_SOCKET_PATH": "/tmp/ci-scope/agent.sock", "CI_SCOPE_STATE_ROOT": "/tmp/ci-scope/state",
		"CI_SCOPE_POOL_IDENTITY": "forkhorizon-production-vps",
	}
	config, err := LoadBootstrapConfig(func(key string) string { return env[key] })
	if err != nil {
		t.Fatal(err)
	}
	if config.PoolIdentity != "forkhorizon-production-vps" {
		t.Fatalf("pool identity = %q", config.PoolIdentity)
	}
}

func TestLoadBootstrapConfigRejectsPartialEnrollment(t *testing.T) {
	env := map[string]string{
		"CI_SCOPE_CONTROL_PLANE_URL": "https://example.test",
		"CI_SCOPE_CREDENTIAL_PROOF":  "proof",
		"CI_SCOPE_V2_SHADOW_TOKEN":   "shadow",
		"CI_SCOPE_MACHINE_ID":        "machine", "CI_SCOPE_BOOT_ID": "boot", "CI_SCOPE_AGENT_INSTANCE_ID": "agent",
		"CI_SCOPE_CREDENTIAL_ID": "credential", "CI_SCOPE_SESSION_REQUEST_ID": "request",
		"CI_SCOPE_SOCKET_PATH": "/tmp/ci-scope/agent.sock", "CI_SCOPE_STATE_ROOT": "/tmp/ci-scope/state",
		"CI_SCOPE_POOL_IDENTITY":    "forkhorizon-production-vps",
		"CI_SCOPE_ENROLLMENT_TOKEN": "token",
	}
	if _, err := LoadBootstrapConfig(func(key string) string { return env[key] }); err == nil {
		t.Fatal("partial enrollment unexpectedly accepted")
	}
}

func TestLoadBootstrapConfigDoesNotUseKeychainWhenExplicitSecretsArePresent(t *testing.T) {
	env := map[string]string{
		"CI_SCOPE_CONTROL_PLANE_URL": "https://example.test",
		"CI_SCOPE_CREDENTIAL_PROOF":  "proof",
		"CI_SCOPE_V2_SHADOW_TOKEN":   "shadow",
		"CI_SCOPE_MACHINE_ID":        "machine", "CI_SCOPE_BOOT_ID": "boot", "CI_SCOPE_AGENT_INSTANCE_ID": "agent",
		"CI_SCOPE_CREDENTIAL_ID": "credential", "CI_SCOPE_SESSION_REQUEST_ID": "request",
		"CI_SCOPE_SOCKET_PATH": "/tmp/ci-scope/agent.sock", "CI_SCOPE_STATE_ROOT": "/tmp/ci-scope/state",
	}
	if _, err := LoadBootstrapConfig(func(key string) string { return env[key] }); err != nil {
		t.Fatal(err)
	}
}

func TestLoadBootstrapConfigAcceptsExplicitRunnerOptIn(t *testing.T) {
	env := map[string]string{
		"CI_SCOPE_CONTROL_PLANE_URL": "https://example.test",
		"CI_SCOPE_CREDENTIAL_PROOF":  "proof",
		"CI_SCOPE_V2_SHADOW_TOKEN":   "shadow",
		"CI_SCOPE_MACHINE_ID":        "machine", "CI_SCOPE_BOOT_ID": "boot", "CI_SCOPE_AGENT_INSTANCE_ID": "agent",
		"CI_SCOPE_CREDENTIAL_ID": "credential", "CI_SCOPE_SESSION_REQUEST_ID": "request",
		"CI_SCOPE_SOCKET_PATH": "/tmp/ci-scope/agent.sock", "CI_SCOPE_STATE_ROOT": "/tmp/ci-scope/state",
		"CI_SCOPE_RUNNER_EXECUTABLE": "/opt/ci/runner", "CI_SCOPE_RUNNER_WORKSPACE_ROOT": "/Users/ci/workspaces",
		"CI_SCOPE_RUNNER_SCRIPT": "/Users/ci/workspaces/run.sh",
	}
	config, err := LoadBootstrapConfig(func(key string) string { return env[key] })
	if err != nil {
		t.Fatal(err)
	}
	if config.RunnerExecutable != "/opt/ci/runner" || config.RunnerWorkspaceRoot != "/Users/ci/workspaces" || config.RunnerScript != "/Users/ci/workspaces/run.sh" {
		t.Fatalf("runner config = %+v", config)
	}
	env["CI_SCOPE_RUNNER_SCRIPT"] = ""
	if _, err := LoadBootstrapConfig(func(key string) string { return env[key] }); err == nil {
		t.Fatal("configured runner without an explicit script unexpectedly accepted")
	}
	env["CI_SCOPE_RUNNER_WORKSPACE_ROOT"] = ""
	if _, err := LoadBootstrapConfig(func(key string) string { return env[key] }); err == nil {
		t.Fatal("partial runner config unexpectedly accepted")
	}
}
