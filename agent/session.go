package agent

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
)

const (
	SessionOpenPath = "/api/ci/v2/sessions/open"
)

type SessionLifecycle struct {
	plane  *HTTPControlPlane
	config SessionLifecycleConfig

	mu       sync.Mutex
	identity ServerMachineIdentity
	fencing  ServerFencingFields
	revision uint64
	sequence uint64
	open     bool
}

func NewSessionLifecycle(plane *HTTPControlPlane, config SessionLifecycleConfig) (*SessionLifecycle, error) {
	if plane == nil {
		return nil, errors.New("control-plane client is required")
	}
	if config.MachineID == "" || config.BootID == "" || config.AgentInstanceID == "" ||
		config.CredentialID == "" || config.SessionRequestID == "" {
		return nil, errors.New("machine, boot, agent, credential and session request identities are required")
	}
	if config.ShadowToken == "" {
		return nil, errors.New("shadow token is required for session.open")
	}
	if config.SessionID == "" {
		generated, err := newSessionID()
		if err != nil {
			return nil, err
		}
		config.SessionID = generated
	}
	return &SessionLifecycle{plane: plane, config: config}, nil
}

func newSessionID() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate session id: %w", err)
	}
	return "session-" + hex.EncodeToString(bytes), nil
}

// NewSessionRequestID returns a fresh idempotency identity for a new Agent boot.
// Session.open is a mutation, so reusing a launchd-configured request ID after a
// restart would correctly be rejected as a conflicting replay.
func NewSessionRequestID() (string, error) {
	return newSessionID()
}
