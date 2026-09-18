package agent

import (
	"context"
	"fmt"
	"log"
	"strings"
)

func (s *HeadlessScheduler) markRestartReconciliation() {
	record := s.current()
	if record == nil {
		return
	}
	switch record.Phase {
	case schedulerPhaseRunning, schedulerPhaseStopping, schedulerPhaseAwaitingRemoval:
		record.Phase = schedulerPhaseReconcileStart
	case schedulerPhaseReleasing:
		record.Phase = schedulerPhaseReconcileRelease
	default:
		return
	}
	if err := s.persist(record); err != nil {
		log.Printf("persist scheduler restart reconciliation phase: %v", err)
	}
}

func (s *HeadlessScheduler) shutdownOnce(ctx context.Context, record *schedulerRecord) error {
	command, err := s.runnerCommand(record)
	if err != nil {
		return err
	}
	hasRunner := s.config.Runtime.HasRunnerInstance(record.Reservation.Correlation.RunnerInstanceID)
	switch record.Phase {
	case schedulerPhaseClaimed:
		return s.shutdownRecover(ctx, record)
	case schedulerPhasePreparing, schedulerPhaseReconcilePrepare, schedulerPhasePrepared:
		if hasRunner {
			return s.release(ctx, record, command)
		}
		return s.shutdownRecover(ctx, record)
	case schedulerPhaseStarting:
		if !hasRunner {
			return s.shutdownRecover(ctx, record)
		}
		record.Phase = schedulerPhaseStopping
		if err := s.persist(record); err != nil {
			return err
		}
		return s.stop(ctx, record, command)
	case schedulerPhaseReconcileStart:
		return s.reconcileStart(ctx, record)
	case schedulerPhaseRunning, schedulerPhaseStopping:
		if !hasRunner {
			record.Phase = schedulerPhaseReconcileStart
			if err := s.persist(record); err != nil {
				return err
			}
			return s.reconcileStart(ctx, record)
		}
		return s.stop(ctx, record, command)
	case schedulerPhaseAwaitingRemoval:
		return s.awaitRemoval(ctx, record)
	case schedulerPhaseReleasing:
		if !record.LocalReleased && hasRunner {
			return s.release(ctx, record, command)
		}
		return s.reconcileRelease(ctx, record)
	case schedulerPhaseReconcileRelease:
		return s.reconcileRelease(ctx, record)
	default:
		return fmt.Errorf("unsupported scheduler shutdown phase %q", record.Phase)
	}
}

func (s *HeadlessScheduler) shutdownRecover(ctx context.Context, record *schedulerRecord) error {
	status, err := s.config.Server.Status(ctx, s.nextStatusRequest(record), record.Reservation)
	if err != nil {
		if schedulerOperationNotFound(err) {
			return s.clear()
		}
		return err
	}
	if isTerminalReservationState(status) {
		return s.clear()
	}
	if status.Terminal || strings.EqualFold(status.JobState, "completed") || strings.EqualFold(status.JobState, "failed") || strings.EqualFold(status.JobState, "cancelled") {
		record.LocalReleased = true
		record.Phase = schedulerPhaseReleasing
		return s.persist(record)
	}
	if _, err := s.config.Server.Recover(ctx, "recover.v2."+record.Reservation.ReservationID, record.Reservation); err != nil {
		return err
	}
	return s.clear()
}
