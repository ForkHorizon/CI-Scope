package watchdog

import "time"

type Observation string

const (
	ObserveHealthy Observation = "healthy"
	ObserveGrace   Observation = "grace"
	ObserveStalled Observation = "stalled"
	ObserveBlocked Observation = "blocked"
	ObserveStale   Observation = "stale"
)

type Monitor struct {
	lastSequence uint64
	graceUntil   time.Time
	grace        time.Duration
}

func NewMonitor(grace time.Duration) *Monitor { return &Monitor{grace: grace} }

func (m *Monitor) BeginSleep(at time.Time) { m.graceUntil = at.Add(m.grace) }

func (m *Monitor) Observe(h Health) Observation {
	if h.Sequence <= m.lastSequence {
		return ObserveStale
	}
	m.lastSequence = h.Sequence
	if h.State == RecoveryBlocked {
		return ObserveBlocked
	}
	if h.State == Healthy {
		return ObserveHealthy
	}
	if !m.graceUntil.IsZero() && h.At.Before(m.graceUntil) {
		return ObserveGrace
	}
	return ObserveStalled
}
