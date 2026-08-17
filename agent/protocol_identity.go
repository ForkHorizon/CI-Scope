package agent

type ServerMachineIdentity struct {
	MachineID        string `json:"machineId"`
	BootID           string `json:"bootId"`
	AgentInstanceID  string `json:"agentInstanceId"`
	CredentialID     string `json:"credentialId,omitempty"`
	SessionRequestID string `json:"sessionRequestId,omitempty"`
	SessionID        string `json:"sessionId,omitempty"`
}

type ServerFencingFields struct {
	SessionEpoch           uint64  `json:"sessionEpoch"`
	FenceToken             string  `json:"fenceToken"`
	ExpectedServerRevision *uint64 `json:"expectedServerRevision,omitempty"`
}
