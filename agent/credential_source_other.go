//go:build !darwin

package agent

import "errors"

const defaultKeychainService = "com.forkhorizon.ci-scope.agent"

func readKeychainSecret(_, _ string) (string, error) {
	return "", errors.New("macOS Keychain is unavailable on this platform")
}
