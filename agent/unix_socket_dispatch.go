package agent

import "encoding/json"

func (r *UnixSocketRuntime) dispatch(request SocketRequestEnvelope) SocketResponseEnvelope {
	var command socketCommand
	if err := json.Unmarshal(request.Payload, &command); err != nil || command.Command == "" {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "invalid_command")
	}
	switch command.Command {
	case "status":
		return r.successResponse(request, r.statusPayload())
	case "acquireControlLease":
		return r.acquireLease(request, command)
	case "renewControlLease":
		return r.renewLease(request, command)
	case "resume":
		return r.resume(request, command)
	case "drain":
		return r.drain(request, command)
	case "emergencyStop":
		return r.emergencyStop(request, command)
	case "reservation.prepare":
		return r.reservationPrepare(request, command)
	case "runner.start":
		return r.runnerStart(request, command)
	case "runner.observe":
		return r.runnerObserve(request, command)
	case "runner.stop":
		return r.runnerStop(request, command, false)
	case "runner.release", "reservation.release":
		return r.runnerRelease(request, command)
	default:
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "unsupported_command")
	}
}

func (r *UnixSocketRuntime) sessionContext() SocketSessionContext {
	return SocketSessionContext{
		MachineID: r.config.Identity.MachineID, BootID: r.config.Identity.BootID,
		AgentInstanceID: r.config.Identity.AgentInstanceID, SessionID: r.config.Identity.SessionID,
		SessionEpoch: r.config.ServerSessionEpoch,
	}
}

func (r *UnixSocketRuntime) fencingContext() SocketFencingContext {
	return SocketFencingContext{LocalOwnerEpoch: r.config.LocalEpoch, SessionEpoch: r.config.ServerSessionEpoch, FencingToken: r.config.FencingToken, RunnerInstanceID: r.config.RunnerInstanceID}
}

func (r *UnixSocketRuntime) response(request SocketRequestEnvelope, operationID, outcome string, payload any, protocolError *ServerProtocolError) SocketResponseEnvelope {
	data, err := json.Marshal(payload)
	if err != nil {
		data = []byte("{}")
	}
	hash, err := HashPayload(payload)
	if err != nil {
		hash = ""
	}
	r.mu.Lock()
	revision := r.serverRevision
	r.mu.Unlock()
	return SocketResponseEnvelope{
		ProtocolVersion: ServerProtocolVersion, RequestID: request.RequestID, PayloadHash: hash,
		Session: r.sessionContext(), Fencing: r.fencingContext(), OperationID: operationID,
		ServerRevision: revision, Outcome: outcome, RetryAfterMs: nil, Payload: data, Error: protocolError,
	}
}

func (r *UnixSocketRuntime) successResponse(request SocketRequestEnvelope, payload any) SocketResponseEnvelope {
	return r.response(request, request.RequestID, "succeeded", payload, nil)
}

func (r *UnixSocketRuntime) errorResponse(requestID, payloadHash, outcome, code string) SocketResponseEnvelope {
	request := SocketRequestEnvelope{RequestID: requestID, PayloadHash: payloadHash}
	return r.response(request, requestID, outcome, map[string]any{}, &ServerProtocolError{Code: code, Message: safeSocketErrorMessage(code), RequestID: requestID})
}

func safeSocketErrorMessage(code string) string {
	return map[string]string{
		"invalid_command":                  "The control command is invalid.",
		"unsupported_command":              "The control command is unsupported.",
		"control_lease_required":           "An active control lease is required.",
		"control_lease_conflict":           "The control lease is owned by another app instance.",
		"control_lease_invalid":            "The control lease token is invalid or expired.",
		"invalid_drain_deadline":           "The drain deadline is invalid.",
		"invalid_lifecycle_transition":     "The requested lifecycle transition is invalid.",
		"runtime_closed":                   "The Agent runtime is shutting down.",
		"external_control_unavailable":     "External runner control is unavailable.",
		"external_control_ambiguous":       "External runner control has an ambiguous result.",
		"runner_jit_config_missing":        "The reservation response did not contain an ephemeral runner configuration.",
		"runner_lifecycle_failed":          "The runner lifecycle operation could not be confirmed.",
		"runner_identity_invalid":          "The runner ownership identity is invalid.",
		"runner_not_prepared":              "The runner has not been prepared.",
		"emergency_stop_requires_draining": "Emergency stop requires a draining Agent.",
		"malformed_frame":                  "The socket frame is malformed.",
	}[code]
}
