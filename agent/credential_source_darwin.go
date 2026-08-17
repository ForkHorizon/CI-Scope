//go:build darwin

package agent

import (
	"errors"
	"os/exec"
	"strings"
)

const defaultKeychainService = "com.forkhorizon.ci-scope.agent"

func readKeychainSecret(service, account string) (string, error) {
	if strings.TrimSpace(service) == "" || strings.TrimSpace(account) == "" {
		return "", errors.New("keychain service and account are required")
	}
	output, err := exec.Command("/usr/bin/security", "find-generic-password", "-s", service, "-a", account, "-w").Output()
	if err != nil {
		return "", errors.New("keychain secret is unavailable")
	}
	secret := strings.TrimSpace(string(output))
	if secret == "" {
		return "", errors.New("keychain secret is empty")
	}
	return secret, nil
}
