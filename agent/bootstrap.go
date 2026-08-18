package agent

import (
	"os"
	"time"
)

type BootstrapConfig struct {
	ControlPlaneURL     string
	CredentialProof     string
	ShadowToken         string
	MachineID           string
	BootID              string
	AgentInstanceID     string
	CredentialID        string
	SessionRequestID    string
	EnrollmentToken     string
	DeviceSecret        string
	EnrollmentIssuer    string
	PoolIdentity        string
	SocketPath          string
	StateRoot           string
	HeartbeatInterval   time.Duration
	HTTPTimeout         time.Duration
	RunnerExecutable    string
	RunnerWorkspaceRoot string
	RunnerScript        string
	RunnerTempRoot      string
}

func LoadBootstrapConfig(getenv func(string) string) (BootstrapConfig, error) {
	if getenv == nil {
		getenv = os.Getenv
	}
	config, err := parseBootstrapIdentity(getenv)
	if err != nil {
		return BootstrapConfig{}, err
	}
	if err := loadBootstrapCredentials(getenv, &config); err != nil {
		return BootstrapConfig{}, err
	}
	if err := loadBootstrapRunnerConfig(getenv, &config); err != nil {
		return BootstrapConfig{}, err
	}
	if err := loadBootstrapOptionalConfig(getenv, &config); err != nil {
		return BootstrapConfig{}, err
	}
	return config, nil
}
