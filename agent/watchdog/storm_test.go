package watchdog

import (
	"testing"
	"time"
)

func TestStormGuardBlocksAfterBoundedRestarts(t *testing.T) {
	g := NewStormGuard(2, time.Minute)
	base := time.Unix(100, 0)
	if !g.RecordRestart(base) || !g.RecordRestart(base.Add(time.Second)) {
		t.Fatal("first restarts should pass")
	}
	if g.RecordRestart(base.Add(2*time.Second)) || !g.Blocked() || g.Count() != 3 {
		t.Fatalf("unexpected storm state: blocked=%v count=%d", g.Blocked(), g.Count())
	}
	if g.RecordRestart(base.Add(3 * time.Second)) {
		t.Fatal("blocked guard must remain blocked")
	}
}
