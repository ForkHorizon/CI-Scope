package agent

import "context"

type schedulerEnvelopeTransport interface {
	DoServerRequest(context.Context, string, ServerRequestEnvelope) (ServerResponseEnvelope, error)
}

type schedulerRevisionSource interface {
	CurrentServerRevision() uint64
}
