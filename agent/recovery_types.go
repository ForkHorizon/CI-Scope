package agent

type RecoveryAction string

const (
	RecoveryKeepRunning        RecoveryAction = "keep_running"
	RecoveryObserve            RecoveryAction = "observe"
	RecoveryStopOrphan         RecoveryAction = "stop_orphan"
	RecoveryRemoveRegistration RecoveryAction = "remove_registration"
	RecoveryReleaseUnassigned  RecoveryAction = "release_unassigned"
	RecoveryBlock              RecoveryAction = "block_recovery"
)

type RecoveryDecision struct {
	IntentID         string
	Action           RecoveryAction
	Reason           string
	RunnerInstanceID string
}
