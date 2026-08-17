package agent

import "encoding/json"

type SocketRequestEnvelope struct {
	ProtocolVersion uint64                 `json:"protocolVersion"`
	RequestID       string                 `json:"requestId"`
	PayloadHash     string                 `json:"payloadHash"`
	Identity        *ServerMachineIdentity `json:"identity,omitempty"`
	Session         *SocketSessionContext  `json:"session,omitempty"`
	Fencing         SocketFencingContext   `json:"fencing"`
	Payload         json.RawMessage        `json:"payload"`
}

type SocketResponseEnvelope struct {
	ProtocolVersion uint64               `json:"protocolVersion"`
	RequestID       string               `json:"requestId"`
	PayloadHash     string               `json:"payloadHash"`
	Session         SocketSessionContext `json:"session"`
	Fencing         SocketFencingContext `json:"fencing"`
	OperationID     string               `json:"operationId"`
	ServerRevision  uint64               `json:"serverRevision"`
	Outcome         string               `json:"outcome"`
	RetryAfterMs    *uint64              `json:"retryAfterMs"`
	Payload         json.RawMessage      `json:"payload"`
	Error           *ServerProtocolError `json:"error,omitempty"`
}
