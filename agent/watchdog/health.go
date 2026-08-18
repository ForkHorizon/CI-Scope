package watchdog

import "time"

type HealthState string

const (
	Healthy         HealthState = "HEALTHY"
	Stalled         HealthState = "STALLED"
	RecoveryBlocked HealthState = "RECOVERY_BLOCKED"
)

type Health struct {
	Sequence uint64
	State    HealthState
	At       time.Time
}
