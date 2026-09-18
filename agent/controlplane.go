package agent

import (
	"errors"
)

var ErrResponseLost = errors.New("control-plane response lost after request handling")

type ControlRequest struct {
	RequestID    string
	SessionEpoch uint64
	PayloadHash  string
}

type ControlResponse struct {
	OperationID    string
	ServerRevision uint64
	Outcome        string
	SessionEpoch   uint64
}
