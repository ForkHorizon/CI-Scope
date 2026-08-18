package watchdog

import "time"

type StormGuard struct {
	maxRestarts int
	window      time.Duration
	starts      []time.Time
	blocked     bool
}

func NewStormGuard(maxRestarts int, window time.Duration) *StormGuard {
	return &StormGuard{maxRestarts: maxRestarts, window: window}
}

func (g *StormGuard) RecordRestart(at time.Time) bool {
	if g.blocked {
		return false
	}
	cutoff := at.Add(-g.window)
	kept := g.starts[:0]
	for _, start := range g.starts {
		if !start.Before(cutoff) {
			kept = append(kept, start)
		}
	}
	g.starts = append(kept, at)
	if len(g.starts) > g.maxRestarts {
		g.blocked = true
		return false
	}
	return true
}

func (g *StormGuard) Blocked() bool { return g.blocked }

func (g *StormGuard) Count() int { return len(g.starts) }
