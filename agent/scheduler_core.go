package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

type HeadlessScheduler struct {
	config HeadlessSchedulerConfig
	mu     sync.Mutex
	active *schedulerRecord
	runMu  sync.Mutex
	retry  int
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

func NewHeadlessScheduler(config HeadlessSchedulerConfig) (*HeadlessScheduler, error) {
	if config.Runtime == nil || config.Store == nil || config.Server == nil {
		return nil, errors.New("scheduler runtime, store and server are required")
	}
	if config.PollInterval == 0 {
		config.PollInterval = 2 * time.Second
	}
	if config.PollInterval < 100*time.Millisecond {
		return nil, errors.New("scheduler poll interval is too short")
	}
	if strings.TrimSpace(config.PoolIdentity) == "" {
		config.PoolIdentity = DefaultSchedulerPoolIdentity
	}
	scheduler := &HeadlessScheduler{config: config}
	record, err := loadSchedulerRecord(config.Store)
	if errors.Is(err, sql.ErrNoRows) {
		return scheduler, nil
	}
	if err != nil {
		return nil, err
	}
	if record == nil {
		return scheduler, nil
	}
	scheduler.active = record
	return scheduler, nil
}

func loadSchedulerRecord(store *SQLiteStore) (*schedulerRecord, error) {
	value, err := store.GetMetadata(context.Background(), schedulerMetadataKey)
	if err != nil {
		return nil, fmt.Errorf("load scheduler state: %w", err)
	}
	var record schedulerRecord
	if err := json.Unmarshal([]byte(value), &record); err != nil {
		return nil, fmt.Errorf("decode scheduler state: %w", err)
	}
	if record.Reservation.ReservationID == "" {
		return nil, nil
	}
	if err := validateSchedulerReservation(record.Reservation); err != nil {
		return nil, err
	}
	// A crash during a side effect is reconciled first. The server is the only
	// authority allowed to say whether a runner side effect already happened.
	if record.Phase == schedulerPhasePreparing {
		record.Phase = schedulerPhaseReconcilePrepare
	}
	if record.Phase == schedulerPhaseStarting {
		record.Phase = schedulerPhaseReconcileStart
	}
	if record.Phase == schedulerPhasePrepared {
		// Prepared local state is not durable across boots. Do not ask a new
		// process controller to start a runner it cannot prove it owns.
		record.Phase = schedulerPhaseReconcileStart
	}
	if record.Phase == schedulerPhaseRunning {
		// A running record is durable, but local process-controller ownership is
		// not. Re-enter the server reconciliation path after an Agent restart.
		record.Phase = schedulerPhaseReconcileStart
	}
	if record.Phase == schedulerPhaseStopping || record.Phase == schedulerPhaseAwaitingRemoval {
		// Stop/removal may have completed while the Agent was down. The new
		// process cannot safely call the old process controller, so let the
		// server prove the outcome before recovering or releasing the reservation.
		record.Phase = schedulerPhaseReconcileStart
	}
	if record.Phase == schedulerPhaseReleasing {
		record.Phase = schedulerPhaseReconcileRelease
	}
	return &record, nil
}
