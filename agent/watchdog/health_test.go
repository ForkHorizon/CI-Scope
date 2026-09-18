package watchdog

import (
	"testing"
	"time"
)

func TestMonitorRejectsStaleSequenceAndHonorsSleepGrace(t *testing.T) {
	base := time.Unix(100, 0)
	m := NewMonitor(30 * time.Second)
	if got := m.Observe(Health{Sequence: 1, State: Healthy, At: base}); got != ObserveHealthy {
		t.Fatal(got)
	}
	m.BeginSleep(base)
	if got := m.Observe(Health{Sequence: 2, State: Stalled, At: base.Add(10 * time.Second)}); got != ObserveGrace {
		t.Fatal(got)
	}
	if got := m.Observe(Health{Sequence: 2, State: Stalled, At: base.Add(40 * time.Second)}); got != ObserveStale {
		t.Fatal(got)
	}
	if got := m.Observe(Health{Sequence: 3, State: Stalled, At: base.Add(40 * time.Second)}); got != ObserveStalled {
		t.Fatal(got)
	}
}

func TestMonitorSurfacesRecoveryBlocked(t *testing.T) {
	m := NewMonitor(time.Second)
	if got := m.Observe(Health{Sequence: 1, State: RecoveryBlocked, At: time.Unix(1, 0)}); got != ObserveBlocked {
		t.Fatal(got)
	}
}
