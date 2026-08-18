package agent

import "encoding/json"

type socketCommand struct {
	Command           string            `json:"command"`
	AppInstanceID     string            `json:"appInstanceId"`
	ControlToken      string            `json:"controlToken,omitempty"`
	OperationID       string            `json:"operationId,omitempty"`
	DrainDeadline     json.RawMessage   `json:"drainDeadline,omitempty"`
	ReservationID     string            `json:"reservationId,omitempty"`
	RunnerInstanceID  string            `json:"runnerInstanceId,omitempty"`
	Executable        string            `json:"executable,omitempty"`
	Workspace         string            `json:"workspace,omitempty"`
	Environment       map[string]string `json:"environment,omitempty"`
	RunnerCorrelation map[string]any    `json:"runnerCorrelation,omitempty"`
}
