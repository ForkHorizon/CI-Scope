package agent

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func decodeControlPlaneResponse(response *http.Response, body []byte, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	var envelope ServerResponseEnvelope
	if err := json.Unmarshal(body, &envelope); err != nil {
		return decodeControlPlaneIngressError(response, body, request, err)
	}
	if err := envelope.ValidateFor(request); err != nil {
		return ServerResponseEnvelope{}, err
	}
	if response.StatusCode >= http.StatusOK && response.StatusCode < http.StatusMultipleChoices {
		return envelope, nil
	}
	return envelope, formatControlPlaneHTTPError(response.StatusCode, envelope)
}

func decodeControlPlaneIngressError(response *http.Response, body []byte, request ServerRequestEnvelope, decodeErr error) (ServerResponseEnvelope, error) {
	if response.StatusCode >= http.StatusOK && response.StatusCode < http.StatusMultipleChoices {
		return ServerResponseEnvelope{}, fmt.Errorf("decode control-plane response: %w", decodeErr)
	}
	var simple struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(body, &simple); err == nil && simple.Error != "" {
		return ServerResponseEnvelope{
			ProtocolVersion: ServerProtocolVersion,
			RequestID:       request.RequestID,
			OperationID:     "none",
			Outcome:         "rejected",
			Error:           &ServerProtocolError{Code: simple.Error, Message: simple.Error, RequestID: request.RequestID},
		}, fmt.Errorf("control-plane returned HTTP %d (%s)", response.StatusCode, simple.Error)
	}
	if response.StatusCode >= http.StatusOK {
		return nonJSONControlPlaneError(response.StatusCode, request)
	}
	return ServerResponseEnvelope{}, fmt.Errorf("decode control-plane response: %w", decodeErr)
}

func nonJSONControlPlaneError(status int, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	outcome := "rejected"
	if status == http.StatusTooManyRequests || status >= http.StatusInternalServerError {
		outcome = "retry"
	}
	code := fmt.Sprintf("http_%d", status)
	return ServerResponseEnvelope{
		ProtocolVersion: ServerProtocolVersion,
		RequestID:       request.RequestID,
		OperationID:     "none",
		Outcome:         outcome,
		Error:           &ServerProtocolError{Code: code, Message: "control-plane returned a non-JSON error response", RequestID: request.RequestID},
	}, fmt.Errorf("control-plane returned HTTP %d (%s)", status, code)
}

func formatControlPlaneHTTPError(status int, envelope ServerResponseEnvelope) error {
	if envelope.Error != nil && envelope.Error.Code != "" {
		if envelope.Error.RequestID != "" {
			return fmt.Errorf("control-plane returned HTTP %d (%s, request %s)", status, envelope.Error.Code, envelope.Error.RequestID)
		}
		return fmt.Errorf("control-plane returned HTTP %d (%s)", status, envelope.Error.Code)
	}
	return fmt.Errorf("control-plane returned HTTP %d", status)
}
