// What a running check is doing right now, relayed to the server so the app can show it.
package agent

import (
	"bytes"
	"context"
	"strings"
	"sync"
)

const (
	activityMarker = "@@activity "
	// The server's request protocol rejects any string longer than 256 characters.
	localGateMaxActivity = 200
)

type activityKey struct{}

// withActivity makes report receive every "what I am doing now" text produced while ctx runs.
func withActivity(ctx context.Context, report func(string)) context.Context {
	return context.WithValue(ctx, activityKey{}, report)
}

func reportActivity(ctx context.Context, text string) {
	if report, ok := ctx.Value(activityKey{}).(func(string)); ok {
		report(clip(text, localGateMaxActivity))
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
