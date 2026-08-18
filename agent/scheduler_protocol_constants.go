package agent

// These paths are the small Agent/Web seam. Calls use the existing
// authenticated ServerControlPlane envelope; webhooks never start a process.
const (
	// SchedulerDispatchNextPath is the canonical V2 polling endpoint. The
	// scheduler.claim-next alias remains accepted by Web during rollout, but
	// the Agent must speak the dispatch.next contract so its request shape is
	// validated by the current ingress.
	SchedulerDispatchNextPath    = "/api/ci/v2/dispatch/next"
	SchedulerClaimNextPath       = SchedulerDispatchNextPath
	SchedulerReconcilePath       = "/api/ci/v2/scheduler/reconcile"
	SchedulerReservationPathRoot = "/api/ci/v2/scheduler/reservations/"
	DefaultSchedulerPoolIdentity = "shadow-default"
)
