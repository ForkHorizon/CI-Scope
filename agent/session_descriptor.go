package agent

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// SessionDescriptor contains only the non-secret values Swift needs to build a
// request envelope for the local Agent socket. The file is local discovery
// metadata; every request is still authenticated and fenced by the socket.
type SessionDescriptor struct {
	MachineID       string `json:"machineID"`
	BootID          string `json:"bootID"`
	AgentInstanceID string `json:"agentInstanceID"`
	SessionID       string `json:"sessionID"`
	SessionEpoch    uint64 `json:"sessionEpoch"`
	LocalOwnerEpoch uint64 `json:"localOwnerEpoch"`
	FencingToken    string `json:"fencingToken"`
	SocketPath      string `json:"socketPath"`
}

const sessionDescriptorName = "agent-session.json"

func sessionDescriptorPath(stateRoot string) (string, error) {
	if stateRoot == "" || !filepath.IsAbs(stateRoot) || filepath.Clean(stateRoot) != stateRoot || stateRoot == "/" {
		return "", fmt.Errorf("state root must be an absolute clean non-root path")
	}
	return filepath.Join(stateRoot, sessionDescriptorName), nil
}

// WriteSessionDescriptor publishes the current live session atomically.
func WriteSessionDescriptor(stateRoot string, descriptor SessionDescriptor) error {
	path, err := sessionDescriptorPath(stateRoot)
	if err != nil {
		return err
	}
	if descriptor.MachineID == "" || descriptor.BootID == "" || descriptor.AgentInstanceID == "" ||
		descriptor.SessionID == "" || descriptor.SessionEpoch == 0 || descriptor.LocalOwnerEpoch == 0 ||
		descriptor.FencingToken == "" || descriptor.SocketPath == "" {
		return fmt.Errorf("session descriptor is incomplete")
	}
	data, err := json.Marshal(descriptor)
	if err != nil {
		return fmt.Errorf("encode session descriptor: %w", err)
	}
	temporary, err := os.CreateTemp(stateRoot, ".agent-session-*.tmp")
	if err != nil {
		return fmt.Errorf("create session descriptor: %w", err)
	}
	temporaryPath := temporary.Name()
	cleanup := func() { _ = temporary.Close(); _ = os.Remove(temporaryPath) }
	if err := temporary.Chmod(0o600); err != nil {
		cleanup()
		return fmt.Errorf("secure session descriptor: %w", err)
	}
	if _, err := temporary.Write(data); err != nil {
		cleanup()
		return fmt.Errorf("write session descriptor: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		cleanup()
		return fmt.Errorf("sync session descriptor: %w", err)
	}
	if err := temporary.Close(); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("close session descriptor: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("publish session descriptor: %w", err)
	}
	return nil
}

// RemoveSessionDescriptor removes only this Agent's discovery metadata.
func RemoveSessionDescriptor(stateRoot string) error {
	path, err := sessionDescriptorPath(stateRoot)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove session descriptor: %w", err)
	}
	return nil
}
