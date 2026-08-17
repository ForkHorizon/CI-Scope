package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

const EnrollmentPath = "/api/ci/v2/enrollment"

type EnrollmentConfig struct {
	Token            string
	DeviceSecret     string
	CredentialID     string
	MachineID        string
	BootID           string
	AgentInstanceID  string
	SessionRequestID string
	SessionID        string
	PoolIdentity     string
	IssuerSecret     string
}

func EnrollDevice(ctx context.Context, plane *HTTPControlPlane, config EnrollmentConfig) (string, error) {
	if plane == nil {
		return "", errors.New("control-plane client is required")
	}
	for name, value := range map[string]string{
		"token": config.Token, "device secret": config.DeviceSecret, "credential ID": config.CredentialID,
		"machine ID": config.MachineID, "boot ID": config.BootID, "agent instance ID": config.AgentInstanceID,
		"session request ID": config.SessionRequestID, "session ID": config.SessionID,
		"pool identity": config.PoolIdentity, "issuer secret": config.IssuerSecret,
	} {
		if value == "" {
			return "", fmt.Errorf("%s is required for enrollment", name)
		}
	}
	identity := ServerMachineIdentity{
		MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
		CredentialID: config.CredentialID, SessionRequestID: config.SessionRequestID, SessionID: config.SessionID,
	}
	payload := map[string]any{
		"type": "enrollment.consume", "token": config.Token, "deviceSecret": config.DeviceSecret,
		"credentialId": config.CredentialID, "machineId": config.MachineID, "poolIdentity": config.PoolIdentity,
	}
	request, err := NewServerRequestEnvelope(config.SessionRequestID, identity, ServerFencingFields{SessionEpoch: 1, FenceToken: "enrollment-" + config.SessionRequestID}, payload)
	if err != nil {
		return "", err
	}
	response, err := plane.DoWithHeaders(ctx, EnrollmentPath, request, HTTPControlPlaneRequestHeaders{EnrollmentIssuer: config.IssuerSecret})
	if err != nil {
		return "", err
	}
	if response.Outcome != "accepted" && response.Outcome != "completed" {
		return "", fmt.Errorf("enrollment returned %s", response.Outcome)
	}
	var metadata struct {
		CredentialID string `json:"credentialId"`
	}
	if err := json.Unmarshal(response.Payload, &metadata); err != nil {
		return "", fmt.Errorf("decode enrollment response: %w", err)
	}
	if metadata.CredentialID != config.CredentialID {
		return "", errors.New("enrollment response returned an unexpected credential")
	}
	return metadata.CredentialID, nil
}
