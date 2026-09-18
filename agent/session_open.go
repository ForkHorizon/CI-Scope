package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

func (s *SessionLifecycle) Open(ctx context.Context) (SessionInfo, error) {
	request, alreadyOpen, err := s.openRequest()
	if err != nil {
		return SessionInfo{}, err
	}
	if alreadyOpen {
		return s.currentInfo(), nil
	}
	response, err := s.plane.DoWithHeaders(ctx, SessionOpenPath, request, HTTPControlPlaneRequestHeaders{Authorization: "Bearer " + s.config.ShadowToken})
	if err != nil {
		return SessionInfo{}, err
	}
	if err := s.acceptOpenResponse(response); err != nil {
		return SessionInfo{}, err
	}
	if _, err := s.transition(ctx, "activate"); err != nil {
		s.mu.Lock()
		s.open = false
		s.mu.Unlock()
		return SessionInfo{}, err
	}
	return s.currentInfo(), nil
}

func (s *SessionLifecycle) openRequest() (ServerRequestEnvelope, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.open {
		return ServerRequestEnvelope{}, true, nil
	}
	identity := ServerMachineIdentity{
		MachineID: s.config.MachineID, BootID: s.config.BootID,
		AgentInstanceID: s.config.AgentInstanceID, CredentialID: s.config.CredentialID,
		SessionRequestID: s.config.SessionRequestID,
	}
	payload := map[string]any{
		"type": "session.open", "machineId": s.config.MachineID, "bootId": s.config.BootID,
		"agentInstanceId": s.config.AgentInstanceID, "credentialId": s.config.CredentialID,
		"sessionRequestId": s.config.SessionRequestID, "sessionId": s.config.SessionID,
	}
	request, err := NewServerRequestEnvelope(
		s.config.SessionRequestID, identity,
		ServerFencingFields{SessionEpoch: 1, FenceToken: "bootstrap-" + s.config.SessionRequestID}, payload,
	)
	return request, false, err
}

func (s *SessionLifecycle) acceptOpenResponse(response ServerResponseEnvelope) error {
	if response.Outcome != "accepted" && response.Outcome != "completed" {
		return fmt.Errorf("session.open returned %s", response.Outcome)
	}
	var metadata struct {
		SessionID    string `json:"sessionId"`
		SessionEpoch uint64 `json:"sessionEpoch"`
		FenceToken   string `json:"fenceToken"`
	}
	if err := json.Unmarshal(response.Payload, &metadata); err != nil {
		return fmt.Errorf("decode session.open response: %w", err)
	}
	if metadata.SessionID != s.config.SessionID || metadata.SessionEpoch == 0 || metadata.FenceToken == "" {
		return errors.New("session.open response omitted assigned fencing context")
	}
	s.mu.Lock()
	s.identity = ServerMachineIdentity{
		MachineID: s.config.MachineID, BootID: s.config.BootID,
		AgentInstanceID: s.config.AgentInstanceID, CredentialID: s.config.CredentialID,
		SessionRequestID: s.config.SessionRequestID, SessionID: metadata.SessionID,
	}
	s.fencing = ServerFencingFields{SessionEpoch: metadata.SessionEpoch, FenceToken: metadata.FenceToken}
	s.revision = response.ServerRevision
	s.open = true
	s.mu.Unlock()
	return nil
}

func (s *SessionLifecycle) currentInfo() SessionInfo {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.infoLocked()
}
