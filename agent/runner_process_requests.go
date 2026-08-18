package agent

type RunnerPrepareRequest struct {
	Executable   string
	RunnerScript string
	JITConfig    string
	Workspace    string
	Environment  map[string]string
}

type RunnerProcessObservation struct {
	Identity ProcessIdentity
	Known    bool
	Alive    bool
	Owned    bool
}
