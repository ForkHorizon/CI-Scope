package agent

import (
	"context"
	"fmt"
	"strings"
)

func (s *HeadlessScheduler) stop(ctx context.Context, record *schedulerRecord, command socketCommand) error {
	if record.StopRequestID == "" {
		record.StopRequestID = "stop." + record.Reservation.Correlation.RunnerInstanceID
	}
	record.Phase = schedulerPhaseStopping
	if err := s.persist(record); err != nil {
		return err
	}
	command.Command = "runner.stop"
	command.OperationID = record.StopRequestID
	response, err := s.config.Runtime.schedulerDispatch(record.StopRequestID, command)
	if err != nil || response.Outcome != "succeeded" {
		// GitHub can remove an ephemeral runner before the local process
		// controller observes the terminal job. The stop side effect is then
		// inherently ambiguous, but retrying it forever only holds the slot;
		// let the server-side removal observer settle the reservation.
		if schedulerExternalControlAmbiguous(err, response) {
			record.LocalReleased = true
			record.Phase = schedulerPhaseAwaitingRemoval
			return s.persist(record)
		}
		return err
	}
	record.Phase = schedulerPhaseAwaitingRemoval
	return s.persist(record)
}

func (s *HeadlessScheduler) awaitRemoval(ctx context.Context, record *schedulerRecord) error {
	status, err := s.config.Server.Status(ctx, s.nextStatusRequest(record), record.Reservation)
	if err != nil {
		return err
	}
	if status.Terminal {
		record.Phase = schedulerPhaseReleasing
		return s.persist(record)
	}
	return s.persist(record)
}

func (s *HeadlessScheduler) release(ctx context.Context, record *schedulerRecord, command socketCommand) error {
	if !record.LocalReleased {
		command.Command = "runner.release"
		command.OperationID = "release-local." + record.Reservation.Correlation.RunnerInstanceID
		response, err := s.config.Runtime.schedulerDispatch(command.OperationID, command)
		if err != nil || response.Outcome != "succeeded" {
			return err
		}
		record.LocalReleased = true
	}
	if record.ReleaseRequestID == "" {
		record.ReleaseRequestID = "release." + record.Reservation.ReservationID
	}
	record.Phase = schedulerPhaseReleasing
	if err := s.persist(record); err != nil {
		return err
	}
	status, err := s.config.Server.Release(ctx, record.ReleaseRequestID, record.Reservation)
	if err != nil {
		record.Phase = schedulerPhaseReconcileRelease
		_ = s.persist(record)
		return err
	}
	if !isTerminalReservationState(status) {
		record.Phase = schedulerPhaseReconcileRelease
		return s.persist(record)
	}
	return s.clear()
}

func (s *HeadlessScheduler) reconcileRelease(ctx context.Context, record *schedulerRecord) error {
	status, err := s.config.Server.Status(ctx, s.nextStatusRequest(record), record.Reservation)
	if err != nil {
		// A new session may fence the old session after the server has already
		// completed release. The old reservation is then intentionally hidden
		// from the new session's status endpoint. LocalReleased proves that no
		// local runner side effect remains, so dropping this terminal marker is
		// safe and lets the fresh scheduler claim the next job.
		if record.LocalReleased && schedulerOperationNotFound(err) {
			return s.clear()
		}
		return err
	}
	if isTerminalReservationState(status) {
		return s.clear()
	}
	if !status.Terminal {
		if record.ReleaseRequestID == "" {
			record.ReleaseRequestID = "release." + record.Reservation.ReservationID
		}
		releaseStatus, releaseErr := s.config.Server.Release(ctx, record.ReleaseRequestID, record.Reservation)
		if releaseErr != nil {
			return releaseErr
		}
		if isTerminalReservationState(releaseStatus) {
			return s.clear()
		}
		return s.persist(record)
	}
	record.Phase = schedulerPhaseReleasing
	return s.persist(record)
}

func isTerminalReservationState(status SchedulerStatusResponse) bool {
	return status.Terminal ||
		strings.EqualFold(status.State, "released") ||
		strings.EqualFold(status.State, "closed") ||
		strings.EqualFold(status.State, "satisfied") ||
		strings.EqualFold(status.State, "cancelled") ||
		strings.EqualFold(status.State, "expired_unassigned")
}

func (s *HeadlessScheduler) nextStatusRequest(record *schedulerRecord) string {
	if record.StatusRequestID == "" {
		record.StatusRequestID = "status." + record.Reservation.ReservationID + ".1"
		return record.StatusRequestID
	}
	parts := strings.Split(record.StatusRequestID, ".")
	sequence := 1
	if len(parts) > 2 {
		_, _ = fmt.Sscanf(parts[len(parts)-1], "%d", &sequence)
		sequence++
	}
	record.StatusRequestID = "status." + record.Reservation.ReservationID + "." + fmt.Sprint(sequence)
	return record.StatusRequestID
}
