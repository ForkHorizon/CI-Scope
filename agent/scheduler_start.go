package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

func (s *HeadlessScheduler) start(ctx context.Context, record *schedulerRecord, command socketCommand) error {
	if record.StartRequestID == "" {
		record.StartRequestID = "start." + record.Reservation.Correlation.RunnerInstanceID
	}
	record.Phase = schedulerPhaseStarting
	if err := s.persist(record); err != nil {
		return err
	}
	command.Command = "runner.start"
	command.OperationID = record.StartRequestID
	response, err := s.config.Runtime.schedulerDispatch(record.StartRequestID, command)
	if err != nil || response.Outcome != "succeeded" {
		record.Phase = schedulerPhaseReconcileStart
		_ = s.persist(record)
		return err
	}
	record.Phase = schedulerPhaseRunning
	return s.persist(record)
}

func (s *HeadlessScheduler) reconcileStart(ctx context.Context, record *schedulerRecord) error {
	status, err := s.config.Server.Status(ctx, s.nextStatusRequest(record), record.Reservation)
	if err != nil {
		if schedulerOperationNotFound(err) {
			_, recoverErr := s.config.Server.Recover(ctx, "recover.v2."+record.Reservation.ReservationID, record.Reservation)
			if recoverErr == nil || schedulerRecoveryCannotFind(recoverErr) {
				return s.clear()
			}
			log.Printf("scheduler start recovery pending: %v", recoverErr)
		}
		return err
	}
	// The scheduler record is durable, but the process-controller ownership is
	// deliberately in memory. After an Agent restart, never issue start or
	// observe for the old runner: ask the server to prove the GitHub runner is
	// gone and recover the reservation instead.
	if !s.config.Runtime.OwnsRunnerInstance(record.Reservation.Correlation.RunnerInstanceID) {
		// An ephemeral runner can disappear locally immediately after GitHub
		// records the job as terminal. In that case the server-side release path
		// is the safe next step; attempting recovery would require emergency
		// evidence for an assigned reservation and can strand the slot.
		if status.Terminal || strings.EqualFold(status.JobState, "completed") || strings.EqualFold(status.JobState, "failed") || strings.EqualFold(status.JobState, "cancelled") {
			record.LocalReleased = true
			record.Phase = schedulerPhaseReleasing
			return s.persist(record)
		}
		_, recoverErr := s.config.Server.Recover(ctx, "recover.v2."+record.Reservation.ReservationID, record.Reservation)
		if recoverErr == nil || schedulerRecoveryCannotFind(recoverErr) {
			return s.clear()
		}
		return recoverErr
	}
	if strings.EqualFold(status.State, "running") || strings.EqualFold(status.JobState, "in_progress") {
		record.Phase = schedulerPhaseRunning
		return s.persist(record)
	}
	if isTerminalReservationState(status) {
		return s.clear()
	}
	if strings.EqualFold(status.State, "prepared") || strings.EqualFold(status.State, "claimed") {
		record.Phase = schedulerPhaseStarting
		return s.persist(record)
	}
	return fmt.Errorf("start reconciliation is %q", status.State)
}

func schedulerOperationNotFound(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "operation_not_found")
}

func schedulerRecoveryCannotFind(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "operation_not_found") || strings.Contains(message, "invalid_request")
}

func schedulerExternalControlAmbiguous(err error, response SocketResponseEnvelope) bool {
	if err != nil && strings.Contains(strings.ToLower(err.Error()), "external_control_ambiguous") {
		return true
	}
	return response.Error != nil && response.Error.Code == "external_control_ambiguous"
}

func (s *HeadlessScheduler) running(ctx context.Context, record *schedulerRecord, command socketCommand) error {
	// The server is authoritative for GitHub job lifecycle. Check it before
	// asking the local process controller to emit runner.observed: once a job
	// is terminal, the ephemeral runner may already be gone and an observe
	// lifecycle mutation can become ambiguous and strand the reservation.
	record.StatusRequestID = s.nextStatusRequest(record)
	status, err := s.config.Server.Status(ctx, record.StatusRequestID, record.Reservation)
	if err != nil {
		return err
	}
	if schedulerStatusTerminal(status) {
		record.Phase = schedulerPhaseStopping
		return s.persist(record)
	}

	if record.ObserveRequestID == "" {
		record.ObserveRequestID = "observe." + record.Reservation.Correlation.RunnerInstanceID
	}
	command.Command = "runner.observe"
	command.OperationID = record.ObserveRequestID
	response, err := s.config.Runtime.schedulerDispatch(record.ObserveRequestID, command)
	if err != nil || response.Outcome != "succeeded" {
		// The process may disappear immediately after GitHub marks an
		// ephemeral runner terminal. Treat an ambiguous external observe as
		// reconciliation work instead of retrying the same lifecycle mutation
		// forever and holding the reservation.
		if schedulerExternalControlAmbiguous(err, response) {
			record.Phase = schedulerPhaseReconcileStart
			return s.persist(record)
		}
		return err
	}
	var observation RunnerProcessObservation
	if err := json.Unmarshal(response.Payload, &observation); err == nil && (!observation.Known || !observation.Alive || !observation.Owned) {
		// The runner process can disappear after GitHub removes an ephemeral
		// runner. Keep the reservation durable, but re-enter server recovery
		// instead of treating the stale runtime ID as a live owner forever.
		record.Phase = schedulerPhaseReconcileStart
		return s.persist(record)
	}
	return s.persist(record)
}

func schedulerStatusTerminal(status SchedulerStatusResponse) bool {
	return status.Terminal || strings.EqualFold(status.JobState, "completed") || strings.EqualFold(status.JobState, "failed") || strings.EqualFold(status.JobState, "cancelled")
}
