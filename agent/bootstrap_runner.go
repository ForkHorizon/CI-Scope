package agent

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
)

func loadBootstrapRunnerConfig(getenv func(string) string, config *BootstrapConfig) error {
	config.RunnerExecutable = strings.TrimSpace(getenv("CI_SCOPE_RUNNER_EXECUTABLE"))
	config.RunnerWorkspaceRoot = strings.TrimSpace(getenv("CI_SCOPE_RUNNER_WORKSPACE_ROOT"))
	config.RunnerScript = strings.TrimSpace(getenv("CI_SCOPE_RUNNER_SCRIPT"))
	config.RunnerTempRoot = strings.TrimSpace(getenv("CI_SCOPE_RUNNER_TEMP_ROOT"))
	if (config.RunnerExecutable == "") != (config.RunnerWorkspaceRoot == "") {
		return errors.New("runner configuration must provide executable and workspace root together")
	}
	if config.RunnerExecutable != "" && config.RunnerScript == "" {
		return errors.New("runner configuration must provide an explicit runner script")
	}
	for key, value := range map[string]string{
		"CI_SCOPE_RUNNER_EXECUTABLE":     config.RunnerExecutable,
		"CI_SCOPE_RUNNER_WORKSPACE_ROOT": config.RunnerWorkspaceRoot,
		"CI_SCOPE_RUNNER_SCRIPT":         config.RunnerScript,
		"CI_SCOPE_RUNNER_TEMP_ROOT":      config.RunnerTempRoot,
	} {
		if value != "" && (!filepath.IsAbs(value) || filepath.Clean(value) != value || value == "/") {
			return fmt.Errorf("%s must be an absolute clean non-root path", key)
		}
	}
	return nil
}
