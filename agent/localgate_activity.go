// What a running job is doing right now, gate by gate, relayed to the server so the app can show it.
package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
)

const (
	activityMarker = "@@activity "
	// The server's request protocol rejects any string longer than 256 characters.
	localGateMaxActivity = 200
	localGateMaxProgress = 32
)

// CheckProgress is one gate of a running job: waiting, running (with what it is doing now), or finished.
type CheckProgress struct {
	ID      string `json:"id"`
	State   string `json:"state"` // pending, running, passed, failed
	Step    string `json:"step,omitempty"`
	Current int    `json:"current,omitempty"`
	Total   int    `json:"total,omitempty"`
	Detail  string `json:"detail,omitempty"`
}

// gateEvent is one JSON line the ci-gates CLI prints after the activity marker.
type gateEvent struct {
	Plan    []string `json:"plan"`
	Check   string   `json:"check"`
	State   string   `json:"state"`
	Step    string   `json:"step"`
	Current int      `json:"current"`
	Total   int      `json:"total"`
	Detail  string   `json:"detail"`
}

// jobProgress collects the phase the agent is in and the state of every gate; changed wakes the heartbeat.
type jobProgress struct {
	mu      sync.Mutex
	phase   string
	checks  []CheckProgress
	changed chan struct{}
}

func newJobProgress() *jobProgress { return &jobProgress{changed: make(chan struct{}, 1)} }

func (p *jobProgress) wake() {
	select {
	case p.changed <- struct{}{}:
	default:
	}
}

// Phase records what the agent itself is doing before the gates start (verifying, checking out).
func (p *jobProgress) Phase(text string) {
	p.mu.Lock()
	changed := p.phase != text
	p.phase = text
	p.mu.Unlock()
	if changed {
		p.wake()
	}
}

// Event applies one gate event; text that is not a valid event is ignored.
func (p *jobProgress) Event(raw string) {
	var event gateEvent
	if json.Unmarshal([]byte(raw), &event) != nil {
		return
	}
	p.mu.Lock()
	p.apply(event)
	p.mu.Unlock()
	p.wake()
}

func (p *jobProgress) apply(event gateEvent) {
	if event.Plan != nil {
		p.checks = p.checks[:0]
		for _, id := range event.Plan[:min(len(event.Plan), localGateMaxProgress)] {
			p.checks = append(p.checks, CheckProgress{ID: clip(id, 64), State: "pending"})
		}
		return
	}
	if event.Check == "" {
		return
	}
	id := clip(event.Check, 64)
	index := -1
	for i := range p.checks {
		if p.checks[i].ID == id {
			index = i
		}
	}
	if index < 0 {
		if len(p.checks) >= localGateMaxProgress {
			return
		}
		p.checks = append(p.checks, CheckProgress{ID: id})
		index = len(p.checks) - 1
	}
	state := event.State
	if state == "" {
		state = "running"
	}
	// A finished gate keeps no live detail; a running one shows the newest step it reported.
	p.checks[index] = CheckProgress{ID: id, State: clip(state, 16)}
	if state == "running" {
		p.checks[index].Step, p.checks[index].Detail = clip(event.Step, 64), clip(event.Detail, 160)
		p.checks[index].Current, p.checks[index].Total = max(event.Current, 0), max(event.Total, 0)
	}
}

// Snapshot is the one-line summary (for the GitHub check and old clients) and the per-gate list.
func (p *jobProgress) Snapshot() (string, []CheckProgress) {
	p.mu.Lock()
	defer p.mu.Unlock()
	checks := append([]CheckProgress(nil), p.checks...)
	for _, check := range checks {
		if check.State == "running" {
			return clip(describeCheck(check), localGateMaxActivity), checks
		}
	}
	return clip(p.phase, localGateMaxActivity), checks
}

func describeCheck(check CheckProgress) string {
	text := check.ID
	if check.Step != "" {
		text += " · " + check.Step
	}
	if check.Detail != "" {
		text += ": " + check.Detail
	}
	if check.Total > 0 {
		text += fmt.Sprintf(" (%d/%d)", check.Current, check.Total)
	}
	return text
}

type progressKey struct{}

// withProgress makes p receive everything reported while ctx runs.
func withProgress(ctx context.Context, p *jobProgress) context.Context {
	return context.WithValue(ctx, progressKey{}, p)
}

func progressFrom(ctx context.Context) *jobProgress {
	p, _ := ctx.Value(progressKey{}).(*jobProgress)
	return p
}

// reportActivity records the agent's own phase, for example "Checking out abc123".
func reportActivity(ctx context.Context, text string) {
	if p := progressFrom(ctx); p != nil {
		p.Phase(text)
	}
}

// activityWriter keeps a command's output, minus the marked activity lines, which go to report instead.
type activityWriter struct {
	mu      sync.Mutex
	out     bytes.Buffer
	pending []byte
	report  func(string)
}

func (w *activityWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.pending = append(w.pending, p...)
	for {
		end := bytes.IndexByte(w.pending, '\n')
		if end < 0 {
			return len(p), nil
		}
		w.line(string(w.pending[:end+1]))
		w.pending = w.pending[end+1:]
	}
}

func (w *activityWriter) line(line string) {
	if text, ok := strings.CutPrefix(line, activityMarker); ok {
		w.report(strings.TrimSpace(text))
		return
	}
	w.out.WriteString(line)
}

// Bytes is the output so far, with a last line that has no newline yet.
func (w *activityWriter) Bytes() []byte {
	w.mu.Lock()
	defer w.mu.Unlock()
	return append(append([]byte(nil), w.out.Bytes()...), w.pending...)
}
