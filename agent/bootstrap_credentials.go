package agent

import (
	"errors"
	"strings"
)

func loadBootstrapCredentials(getenv func(string) string, config *BootstrapConfig) error {
	config.CredentialProof = strings.TrimSpace(getenv("CI_SCOPE_CREDENTIAL_PROOF"))
	config.ShadowToken = strings.TrimSpace(getenv("CI_SCOPE_V2_SHADOW_TOKEN"))
	keychainService := strings.TrimSpace(getenv("CI_SCOPE_KEYCHAIN_SERVICE"))
	if keychainService == "" {
		keychainService = defaultKeychainService
	}
	if config.CredentialProof == "" {
		secret, err := readKeychainSecret(keychainService, config.CredentialID)
		if err != nil {
			return errors.New("CI_SCOPE_CREDENTIAL_PROOF is required unless the device credential is in Keychain")
		}
		config.CredentialProof = secret
	}
	if config.ShadowToken == "" {
		account := strings.TrimSpace(getenv("CI_SCOPE_V2_SHADOW_TOKEN_KEYCHAIN_ACCOUNT"))
		if account == "" {
			account = "shadow-token"
		}
		secret, err := readKeychainSecret(keychainService, account)
		if err != nil {
			return errors.New("CI_SCOPE_V2_SHADOW_TOKEN is required unless the shadow token is in Keychain")
		}
		config.ShadowToken = secret
	}
	return nil
}
