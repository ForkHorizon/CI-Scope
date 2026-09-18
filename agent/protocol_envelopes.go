package agent

import "encoding/json"

type ServerRequestEnvelope struct {
	ProtocolVersion uint64                `json:"protocolVersion"`
	RequestID       string                `json:"requestId"`
	PayloadHash     string                `json:"payloadHash"`
	Identity        ServerMachineIdentity `json:"identity"`
	Fencing         ServerFencingFields   `json:"fencing"`
	Payload         json.RawMessage       `json:"payload"`
}

type ServerResponseEnvelope struct {
	ProtocolVersion uint64               `json:"protocolVersion"`
	RequestID       string               `json:"requestId"`
	OperationID     string               `json:"operationId"`
	ServerRevision  uint64               `json:"serverRevision"`
	Outcome         string               `json:"outcome"`
	RetryAfterMs    *uint64              `json:"retryAfterMs"`
	Payload         json.RawMessage      `json:"payload,omitempty"`
	Error           *ServerProtocolError `json:"error,omitempty"`
}
