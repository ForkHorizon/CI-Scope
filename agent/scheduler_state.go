package agent

import "time"

const (
	schedulerPhaseClaimed          = "claimed"
	schedulerPhasePreparing        = "preparing"
	schedulerPhaseReconcilePrepare = "reconcile_prepare"
	schedulerPhasePrepared         = "prepared"
	schedulerPhaseStarting         = "starting"
	schedulerPhaseReconcileStart   = "reconcile_start"
	schedulerPhaseRunning          = "running"
	schedulerPhaseStopping         = "stopping"
	schedulerPhaseAwaitingRemoval  = "awaiting_removal"
	schedulerPhaseReleasing        = "releasing"
	schedulerPhaseReconcileRelease = "reconcile_release"
)

type schedulerRecord struct {
	Reservation      SchedulerReservation `json:"reservation"`
	Phase            string               `json:"phase"`
	ClaimRequestID   string               `json:"claimRequestId"`
	PrepareRequestID string               `json:"prepareRequestId"`
	StartRequestID   string               `json:"startRequestId"`
	ObserveRequestID string               `json:"observeRequestId"`
	StatusRequestID  string               `json:"statusRequestId"`
	StopRequestID    string               `json:"stopRequestId"`
	ReleaseRequestID string               `json:"releaseRequestId"`
	LocalReleased    bool                 `json:"localReleased"`
}

type HeadlessSchedulerConfig struct {
	Runtime          *UnixSocketRuntime
	Store            *SQLiteStore
	Server           *SchedulerServerClient
	PoolIdentity     string
	RunnerExecutable string
	RunnerWorkspace  string
	PollInterval     time.Duration
}

const schedulerMetadataKey = "scheduler.active"
