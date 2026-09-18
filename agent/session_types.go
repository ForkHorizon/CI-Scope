package agent

type SessionLifecycleConfig struct {
	MachineID        string
	BootID           string
	AgentInstanceID  string
	CredentialID     string
	SessionRequestID string
	SessionID        string
	ShadowToken      string
}

type SessionInfo struct {
	Identity ServerMachineIdentity
	Fencing  ServerFencingFields
	Revision uint64
}
