package agent

type IntentKind string

const (
	IntentClaimReservation   IntentKind = "claim_reservation"
	IntentPrepareJIT         IntentKind = "prepare_jit"
	IntentCreateDirectory    IntentKind = "create_directory"
	IntentSpawnProcess       IntentKind = "spawn_process"
	IntentStopProcess        IntentKind = "stop_process"
	IntentRemoveRegistration IntentKind = "remove_registration"
	IntentCleanupWorkspace   IntentKind = "cleanup_workspace"
	IntentReleaseReservation IntentKind = "release_reservation"
)

type IntentStatus string

const (
	IntentPending       IntentStatus = "PENDING"
	IntentEffectApplied IntentStatus = "EFFECT_APPLIED"
	IntentAcknowledged  IntentStatus = "ACKNOWLEDGED"
	IntentCancelPending IntentStatus = "CANCEL_PENDING"
)
