package agent

import "context"

func (r *UnixSocketRuntime) emergencyStop(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	r.mu.Lock()
	if err := r.validateEmergencyLeaseLocked(command); err != nil {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	if r.owner.Snapshot().State != StateDraining {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "emergency_stop_requires_draining")
	}
	controller := r.config.RunnerController
	processController := r.config.ProcessController
	r.mu.Unlock()
	if processController != nil {
		response := r.runnerStop(request, command, true)
		if response.Outcome != "succeeded" {
			return response
		}
		r.mu.Lock()
		r.lease = controlLease{}
		r.mu.Unlock()
		result := r.submitTransition(r.runtimeContext(), request.RequestID, StateDormant)
		if result.Err != nil || result.Stale {
			return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
		}
		return r.successResponse(request, r.statusPayload())
	}
	if controller == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	outcome, err := controller.EmergencyStop(context.Background(), request.RequestID)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	if outcome != RunnerStopCompleted {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	result := r.submitTransition(r.runtimeContext(), request.RequestID, StateDormant)
	if result.Err != nil || result.Stale {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	r.mu.Lock()
	r.lease = controlLease{}
	r.mu.Unlock()
	return r.successResponse(request, r.statusPayload())
}
