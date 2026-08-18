package agent

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
)

const ServerProtocolVersion uint64 = 2

func CanonicalJSON(value any) ([]byte, error) {
	// json.Marshal preserves Go struct declaration order, while the Web
	// protocol canonicalizes every object by lexicographically sorting keys.
	// Normalize through interface{} first so nested structs and maps use the
	// same ordering before hashing or signing a request.
	raw, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	var normalized any
	if err := json.Unmarshal(raw, &normalized); err != nil {
		return nil, err
	}
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(normalized); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buffer.Bytes(), []byte{'\n'}), nil
}

func HashPayload(value any) (string, error) {
	data, err := CanonicalJSON(value)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:]), nil
}

func NewServerRequestEnvelope(requestID string, identity ServerMachineIdentity, fencing ServerFencingFields, payload any) (ServerRequestEnvelope, error) {
	if requestID == "" || identity.MachineID == "" || identity.BootID == "" || identity.AgentInstanceID == "" || fencing.SessionEpoch == 0 || fencing.FenceToken == "" {
		return ServerRequestEnvelope{}, errors.New("invalid server request identity or fencing")
	}
	data, err := CanonicalJSON(payload)
	if err != nil {
		return ServerRequestEnvelope{}, err
	}
	hash, err := HashPayload(payload)
	if err != nil {
		return ServerRequestEnvelope{}, err
	}
	return ServerRequestEnvelope{
		ProtocolVersion: ServerProtocolVersion,
		RequestID:       requestID,
		PayloadHash:     hash,
		Identity:        identity,
		Fencing:         fencing,
		Payload:         data,
	}, nil
}

func (response ServerResponseEnvelope) ValidateFor(request ServerRequestEnvelope) error {
	if response.ProtocolVersion != ServerProtocolVersion || response.RequestID != request.RequestID {
		return fmt.Errorf("invalid server response protocol or request id")
	}
	if response.OperationID == "" || response.Outcome == "" {
		return errors.New("invalid server response metadata")
	}
	switch response.Outcome {
	case "accepted", "completed", "rejected", "retry", "ambiguous":
	default:
		return fmt.Errorf("unsupported server response outcome %q", response.Outcome)
	}
	return nil
}
