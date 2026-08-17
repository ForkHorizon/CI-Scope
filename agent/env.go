package agent

import (
	"os"
	"strings"
)

var forbiddenEnvironmentKeys = map[string]bool{
	"SSH_AUTH_SOCK":          true,
	"GITHUB_TOKEN":           true,
	"GH_TOKEN":               true,
	"DEEPSEEK_API_KEY":       true,
	"CI_SCOPE_BACKEND_TOKEN": true,
}

// AllowlistedEnvironment drops inherited credentials. Callers must provide
// every value the runner needs explicitly; the Agent never forwards the
// process environment wholesale.
func AllowlistedEnvironment(input map[string]string, allowed map[string]bool) map[string]string {
	result := make(map[string]string)
	for key, value := range input {
		if allowed[key] && !forbiddenEnvironmentKeys[key] && strings.TrimSpace(value) != "" {
			result[key] = value
		}
	}
	return result
}

// DefaultRunnerEnvironment is the smallest useful macOS process environment.
// It never copies the parent environment wholesale and contains no credential
// variables.
func DefaultRunnerEnvironment() map[string]string {
	result := map[string]string{
		"PATH":   "/usr/bin:/bin:/usr/sbin:/sbin",
		"TMPDIR": os.TempDir(),
	}
	for _, key := range []string{"HOME", "LANG", "LC_ALL", "LC_CTYPE"} {
		if value := strings.TrimSpace(os.Getenv(key)); value != "" {
			result[key] = value
		}
	}
	return result
}
