package agent

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
)

func (s *HeadlessScheduler) advance(ctx context.Context, record *schedulerRecord) error {
	command, err := s.runnerCommand(record)
	if err != nil {
		return err
	}
	switch record.Phase {
	case schedulerPhaseClaimed, schedulerPhasePreparing:
		return s.prepare(ctx, record, command)
	case schedulerPhaseReconcilePrepare:
		return s.reconcilePrepare(ctx, record, command)
	case schedulerPhasePrepared, schedulerPhaseStarting:
		return s.start(ctx, record, command)
	case schedulerPhaseReconcileStart:
		return s.reconcileStart(ctx, record)
	case schedulerPhaseRunning:
		return s.running(ctx, record, command)
	case schedulerPhaseStopping:
		return s.stop(ctx, record, command)
	case schedulerPhaseAwaitingRemoval:
		return s.awaitRemoval(ctx, record)
	case schedulerPhaseReleasing:
		return s.release(ctx, record, command)
	case schedulerPhaseReconcileRelease:
		return s.reconcileRelease(ctx, record)
	default:
		return fmt.Errorf("unsupported scheduler phase %q", record.Phase)
	}
}

func (s *HeadlessScheduler) prepare(ctx context.Context, record *schedulerRecord, command socketCommand) error {
	if record.PrepareRequestID == "" {
		record.PrepareRequestID = "prepare." + record.Reservation.Correlation.PreparationID
	}
	record.Phase = schedulerPhasePreparing
	if err := s.persist(record); err != nil {
		return err
	}
	command.Command = "reservation.prepare"
	command.OperationID = record.PrepareRequestID
	response, err := s.config.Runtime.schedulerDispatch(record.PrepareRequestID, command)
	if err != nil || response.Outcome != "succeeded" {
		record.Phase = schedulerPhaseReconcilePrepare
		_ = s.persist(record)
		if err != nil {
			log.Printf("scheduler prepare dispatch pending: %v", err)
			return err
		}
		if response.Error != nil && response.Error.Code != "" {
			log.Printf("scheduler prepare dispatch pending: %s", response.Error.Code)
			return newSchedulerSocketResponseError(response)
		}
		log.Printf("scheduler prepare dispatch pending: outcome %q", response.Outcome)
		return newSchedulerSocketResponseError(response)
	}
	if err := s.config.Server.Register(ctx, "register."+record.Reservation.Correlation.RunnerInstanceID, record.Reservation); err != nil {
		record.Phase = schedulerPhaseReconcilePrepare
		_ = s.persist(record)
		log.Printf("scheduler registration pending: %v", err)
		return err
	}
	record.Phase = schedulerPhasePrepared
	return s.persist(record)
}

func (s *HeadlessScheduler) reconcilePrepare(ctx context.Context, record *schedulerRecord, command socketCommand) error {
	result, err := s.config.Server.Reconcile(ctx, "reconcile.prepare."+record.Reservation.Correlation.PreparationID, record.Reservation, "prepare")
	if err != nil {
		return s.handlePrepareReconcileError(ctx, record, err)
	}
	switch strings.ToLower(strings.TrimSpace(result.State)) {
	case "preparing":
		return s.handlePreparingState(ctx, record, command, result)
	case "reserved", "claimed", "unprepared", "not_prepared":
		record.Phase = schedulerPhasePreparing
		return s.persist(record)
	case "prepared", "config_ready":
		return s.handlePreparedState(ctx, record, command, result)
	default:
		return s.recoverPrepare(ctx, record)
	}
}

func (s *HeadlessScheduler) handlePreparingState(ctx context.Context, record *schedulerRecord, command socketCommand, result SchedulerReconcileResponse) error {
	if strings.TrimSpace(result.JITConfig) != "" {
		response, prepareErr := s.config.Runtime.schedulerPrepareFromJIT(record.PrepareRequestID, command, result.JITConfig, result.JITStatus)
		if prepareErr == nil && response.Outcome == "succeeded" {
			return s.registerPreparedRunner(ctx, record)
		}
	}
	if s.config.Runtime.OwnsRunnerInstance(record.Reservation.Correlation.RunnerInstanceID) {
		return s.registerPreparedRunner(ctx, record)
	}
	return s.recoverPrepare(ctx, record)
}

func (s *HeadlessScheduler) registerPreparedRunner(ctx context.Context, record *schedulerRecord) error {
	if registerErr := s.config.Server.Register(ctx, "register."+record.Reservation.Correlation.RunnerInstanceID, record.Reservation); registerErr == nil {
		record.Phase = schedulerPhasePrepared
		return s.persist(record)
	} else {
		record.Phase = schedulerPhaseReconcilePrepare
		_ = s.persist(record)
		log.Printf("scheduler registration retry pending: %v", registerErr)
		return registerErr
	}
}

func (s *HeadlessScheduler) handlePreparedState(ctx context.Context, record *schedulerRecord, command socketCommand, result SchedulerReconcileResponse) error {
	if strings.TrimSpace(result.JITConfig) == "" {
		if s.config.Runtime.OwnsRunnerInstance(record.Reservation.Correlation.RunnerInstanceID) {
			record.Phase = schedulerPhasePrepared
			return s.persist(record)
		}
		return s.recoverPrepare(ctx, record)
	}
	response, prepareErr := s.config.Runtime.schedulerPrepareFromJIT(record.PrepareRequestID, command, result.JITConfig, result.JITStatus)
	if prepareErr != nil || response.Outcome != "succeeded" {
		record.Phase = schedulerPhaseReconcilePrepare
		_ = s.persist(record)
		return prepareErr
	}
	record.Phase = schedulerPhasePrepared
	return s.persist(record)
}

func (s *HeadlessScheduler) recoverPrepare(ctx context.Context, record *schedulerRecord) error {
	status, err := s.config.Server.Recover(ctx, "recover.prepare."+record.Reservation.ReservationID, record.Reservation)
	if err != nil {
		if schedulerRecoveryCannotFind(err) {
			return s.clear()
		}
		log.Printf("scheduler preparation recovery pending: %v", err)
		return err
	}
	if status.Terminal || strings.EqualFold(status.State, "released") || strings.EqualFold(status.State, "closed") || strings.EqualFold(status.State, "cancelled") || strings.EqualFold(status.State, "expired_unassigned") {
		return s.clear()
	}
	return errors.New("server preparation recovery remains pending")
}

func (s *HeadlessScheduler) handlePrepareReconcileError(ctx context.Context, record *schedulerRecord, err error) error {
	log.Printf("scheduler preparation reconcile error: %v", err)
	if !strings.Contains(err.Error(), "operation_not_found") {
		return err
	}
	_, recoverErr := s.config.Server.Recover(ctx, "recover.v2."+record.Reservation.ReservationID, record.Reservation)
	if recoverErr != nil {
		log.Printf("scheduler recovery pending: %v", recoverErr)
		return recoverErr
	}
	return s.clear()
}
