package agent

import (
	"errors"
	"fmt"
	"net/url"
	"path/filepath"
	"strings"
	"time"
)

func parseBootstrapIdentity(getenv func(string) string) (BootstrapConfig, error) {
	get := requiredBootstrapValue(getenv)
	controlPlaneURL, err := get("CI_SCOPE_CONTROL_PLANE_URL")
	if err != nil {
		return BootstrapConfig{}, err
	}
	parsed, err := url.Parse(controlPlaneURL)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return BootstrapConfig{}, errors.New("CI_SCOPE_CONTROL_PLANE_URL must be an absolute HTTPS URL")
	}
	values := make([]string, 7)
	for index, key := range []string{
		"CI_SCOPE_MACHINE_ID", "CI_SCOPE_BOOT_ID", "CI_SCOPE_AGENT_INSTANCE_ID",
		"CI_SCOPE_CREDENTIAL_ID", "CI_SCOPE_SESSION_REQUEST_ID", "CI_SCOPE_SOCKET_PATH", "CI_SCOPE_STATE_ROOT",
	} {
		values[index], err = get(key)
		if err != nil {
			return BootstrapConfig{}, err
		}
	}
	if err := validateBootstrapPaths(values[5], values[6]); err != nil {
		return BootstrapConfig{}, err
	}
	return BootstrapConfig{
		ControlPlaneURL:   controlPlaneURL,
		MachineID:         values[0],
		BootID:            values[1],
		AgentInstanceID:   values[2],
		CredentialID:      values[3],
		SessionRequestID:  values[4],
		SocketPath:        values[5],
		StateRoot:         values[6],
		HeartbeatInterval: 15 * time.Second,
		HTTPTimeout:       10 * time.Second,
	}, nil
}

func requiredBootstrapValue(getenv func(string) string) func(string) (string, error) {
	return func(key string) (string, error) {
		value := strings.TrimSpace(getenv(key))
		if value == "" {
			return "", fmt.Errorf("%s is required", key)
		}
		return value, nil
	}
}

func validateBootstrapPaths(paths ...string) error {
	for _, path := range paths {
		if !filepath.IsAbs(path) || filepath.Clean(path) != path || path == "/" {
			return fmt.Errorf("path must be absolute, clean and non-root: %s", path)
		}
	}
	return nil
}
