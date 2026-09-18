package agent

import "context"

type ServerControlPlane interface {
	Do(context.Context, string, ServerRequestEnvelope) (ServerResponseEnvelope, error)
}

type RunnerStopOutcome string

const (
	RunnerStopCompleted RunnerStopOutcome = "completed"
	RunnerStopAmbiguous RunnerStopOutcome = "ambiguous"
)
