package agent

import (
	"context"
	"log"
	"strings"
)

func (r *UnixSocketRuntime) runnerStart(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	if err := r.requireControlLease(command); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	if r.config.ProcessController == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	runnerID, correlation, err := r.commandRunnerIdentity(command, false)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", runnerCommandError(err))
	}
	ownership := r.runnerOwnershipFor(runnerID)
	if err := r.config.ProcessController.Start(context.Background(), ownership); err != nil {
		log.Printf("runner start failed: %v", err)
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", runnerCommandError(err))
	}
	if _, err := r.runnerLifecycle(context.Background(), firstNonEmpty(command.OperationID, request.RequestID)+".started", runnerID, "started", correlation); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	return r.successResponse(request, map[string]any{"runnerInstanceId": runnerID, "started": true})
}

func (r *UnixSocketRuntime) runnerObserve(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	if err := r.requireControlLease(command); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	if r.config.ProcessController == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	runnerID, correlation, err := r.commandRunnerIdentity(command, false)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", runnerCommandError(err))
	}
	observation, err := r.config.ProcessController.Observe(context.Background(), r.runnerOwnershipFor(runnerID))
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", runnerCommandError(err))
	}
	if observation.Known {
		if _, err := r.runnerLifecycle(context.Background(), firstNonEmpty(command.OperationID, request.RequestID)+".observed", runnerID, "observed", correlation); err != nil {
			return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
		}
	}
	return r.successResponse(request, observation)
}

func (r *UnixSocketRuntime) runnerStop(request SocketRequestEnvelope, command socketCommand, requireDraining bool) SocketResponseEnvelope {
	if err := r.requireControlLease(command); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	r.mu.Lock()
	draining := r.owner.Snapshot().State == StateDraining
	r.mu.Unlock()
	if requireDraining && !draining {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "emergency_stop_requires_draining")
	}
	if r.config.ProcessController == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	runnerID, correlation, err := r.commandRunnerIdentity(command, false)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", runnerCommandError(err))
	}
	ownership := r.runnerOwnershipFor(runnerID)
	if _, err := r.runnerLifecycle(context.Background(), firstNonEmpty(command.OperationID, request.RequestID)+".stop-requested", runnerID, "stop-requested", correlation); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	outcome, err := r.config.ProcessController.Stop(context.Background(), ownership)
	if err != nil || outcome != RunnerStopCompleted {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	if _, err := r.runnerLifecycle(context.Background(), firstNonEmpty(command.OperationID, request.RequestID)+".stopped", runnerID, "stopped", correlation); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_ambiguous")
	}
	return r.successResponse(request, map[string]any{"runnerInstanceId": runnerID, "stopped": true})
}

func (r *UnixSocketRuntime) runnerRelease(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	if err := r.requireControlLease(command); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	if r.config.ProcessController == nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	runnerID, _, err := r.commandRunnerIdentity(command, false)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", runnerCommandError(err))
	}
	if err := r.config.ProcessController.Release(context.Background(), r.runnerOwnershipFor(runnerID)); err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", runnerCommandError(err))
	}
	r.mu.Lock()
	if r.runnerInstanceID == runnerID {
		r.runnerInstanceID = ""
	}
	r.mu.Unlock()
	return r.successResponse(request, map[string]any{"runnerInstanceId": runnerID, "released": true})
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
