package agent

import (
	"context"
	"errors"
)

func (r *UnixSocketRuntime) statusPayload() AgentStatus {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.expireLeaseLocked()
	r.expireSchedulerLeaseLocked()
	snapshot := r.owner.Snapshot()
	leaseActive := r.lease.token != "" && !r.lease.draining && r.lease.expiresAt.After(r.config.Now())
	schedulerLeaseActive := r.schedulerLease.token != "" && r.schedulerLease.expiresAt.After(r.config.Now())
	draining := snapshot.State == StateDraining || r.lease.draining
	status := AgentStatus{
		ProcessAlive: r.processAlive, SchedulerHealthy: r.schedulerHealthy, ControlLeaseActive: leaseActive,
		SchedulerLeaseActive: schedulerLeaseActive,
		ServerConnected:      r.serverConnected, Draining: draining, RecoveryBlocked: snapshot.State == StateRecoveryBlocked,
		ProjectionLagging: r.projectionLagging, State: snapshot.State, LocalEpoch: snapshot.LocalEpoch,
		ServerSessionEpoch: snapshot.ServerSessionEpoch,
	}
	if leaseActive {
		status.ControlLeaseExpiresAt = r.lease.expiresAt.UnixMilli()
	}
	status.ReadyToClaim = status.CanClaim()
	return status
}

func (r *UnixSocketRuntime) expireLeaseLocked() {
	now := r.config.Now()
	if r.lease.token == "" {
		return
	}
	if r.lease.draining && !r.lease.drainDeadline.IsZero() && !r.lease.drainDeadline.After(now) {
		r.lease = controlLease{}
		return
	}
	if !r.lease.draining && !r.lease.expiresAt.After(now) {
		r.lease = controlLease{}
	}
}

func (r *UnixSocketRuntime) expireSchedulerLeaseLocked() {
	if r.schedulerLease.token != "" && !r.schedulerLease.expiresAt.After(r.config.Now()) {
		r.schedulerLease = controlLease{}
	}
}

// AcquireSchedulerLease grants the headless Agent an internal lease. It is
// deliberately separate from the UI/operator lease so the scheduler can run
// while the macOS app is closed, without giving a background process authority
// to resume, drain, or emergency-stop the runner.

func (r *UnixSocketRuntime) AcquireSchedulerLease() error {
	if r == nil {
		return ErrRuntimeNotStarted
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.expireSchedulerLeaseLocked()
	if r.schedulerLease.token != "" {
		return nil
	}
	token, err := r.config.RandomToken()
	if err != nil || token == "" {
		return ErrExternalControlUnavailable
	}
	r.schedulerLease = controlLease{
		appInstanceID: "agent-scheduler:" + r.config.Identity.AgentInstanceID,
		token:         token,
		expiresAt:     r.config.Now().Add(r.config.LeaseDuration),
	}
	return nil
}

// RenewSchedulerLease refreshes the internal scheduler lease. A false result
// means the lease was absent or had expired and must be acquired again.

func (r *UnixSocketRuntime) RenewSchedulerLease() bool {
	if r == nil {
		return false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.expireSchedulerLeaseLocked()
	if r.schedulerLease.token == "" {
		return false
	}
	r.schedulerLease.expiresAt = r.config.Now().Add(r.config.LeaseDuration)
	return true
}

func (r *UnixSocketRuntime) validateLeaseLocked(command socketCommand) error {
	r.expireLeaseLocked()
	r.expireSchedulerLeaseLocked()
	if r.lease.token != "" && r.lease.appInstanceID == command.AppInstanceID && r.lease.token == command.ControlToken && !r.lease.draining {
		return nil
	}
	if r.schedulerLease.token != "" && r.schedulerLease.appInstanceID == command.AppInstanceID && r.schedulerLease.token == command.ControlToken {
		return nil
	}
	if r.lease.token == "" && r.schedulerLease.token == "" {
		return ErrControlLeaseRequired
	}
	return errors.New("invalid control lease")
}

func (r *UnixSocketRuntime) validateOperatorLeaseLocked(command socketCommand) error {
	r.expireLeaseLocked()
	if r.lease.token == "" {
		return ErrControlLeaseRequired
	}
	if r.lease.appInstanceID != command.AppInstanceID || r.lease.token != command.ControlToken || r.lease.draining {
		return errors.New("invalid control lease")
	}
	return nil
}

func (r *UnixSocketRuntime) validateEmergencyLeaseLocked(command socketCommand) error {
	r.expireLeaseLocked()
	if r.lease.token == "" {
		return ErrControlLeaseRequired
	}
	if r.lease.appInstanceID != command.AppInstanceID || r.lease.token != command.ControlToken {
		return errors.New("invalid control lease")
	}
	return nil
}

func (r *UnixSocketRuntime) acquireLease(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	if command.AppInstanceID == "" {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_conflict")
	}
	r.mu.Lock()
	r.expireLeaseLocked()
	if r.lease.token != "" {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_conflict")
	}
	token, err := r.config.RandomToken()
	if err != nil || token == "" {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "ambiguous", "external_control_unavailable")
	}
	r.lease = controlLease{appInstanceID: command.AppInstanceID, token: token, expiresAt: r.config.Now().Add(r.config.LeaseDuration)}
	expiresAt := r.lease.expiresAt.UnixMilli()
	r.mu.Unlock()
	return r.response(request, request.RequestID, "succeeded", map[string]any{"controlToken": token, "expiresAt": expiresAt}, nil)
}

func (r *UnixSocketRuntime) renewLease(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	r.mu.Lock()
	if err := r.validateOperatorLeaseLocked(command); err != nil {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	r.lease.expiresAt = r.config.Now().Add(r.config.LeaseDuration)
	token, expiresAt := r.lease.token, r.lease.expiresAt.UnixMilli()
	r.mu.Unlock()
	return r.response(request, request.RequestID, "succeeded", map[string]any{"controlToken": token, "expiresAt": expiresAt}, nil)
}

func (r *UnixSocketRuntime) resume(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	r.mu.Lock()
	if err := r.validateOperatorLeaseLocked(command); err != nil {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	r.mu.Unlock()
	result := r.submitTransition(r.runtimeContext(), request.RequestID, StateReady)
	if result.Err != nil || result.Stale {
		code := "invalid_lifecycle_transition"
		if errors.Is(result.Err, context.Canceled) || errors.Is(result.Err, context.DeadlineExceeded) {
			code = "runtime_closed"
		}
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", code)
	}
	return r.successResponse(request, r.statusPayload())
}

func (r *UnixSocketRuntime) drain(request SocketRequestEnvelope, command socketCommand) SocketResponseEnvelope {
	deadline, err := r.parseDrainDeadline(command.DrainDeadline)
	if err != nil {
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "invalid_drain_deadline")
	}
	r.mu.Lock()
	if err := r.validateOperatorLeaseLocked(command); err != nil {
		r.mu.Unlock()
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", "control_lease_invalid")
	}
	r.mu.Unlock()
	result := r.submitTransition(r.runtimeContext(), request.RequestID, StateDraining)
	if result.Err != nil || result.Stale {
		code := "invalid_lifecycle_transition"
		if errors.Is(result.Err, context.Canceled) || errors.Is(result.Err, context.DeadlineExceeded) {
			code = "runtime_closed"
		}
		return r.errorResponse(request.RequestID, request.PayloadHash, "rejected", code)
	}
	r.mu.Lock()
	r.lease.draining = true
	r.lease.drainDeadline = deadline
	r.mu.Unlock()
	return r.successResponse(request, r.statusPayload())
}

func (r *UnixSocketRuntime) requireControlLease(command socketCommand) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.validateLeaseLocked(command)
}
