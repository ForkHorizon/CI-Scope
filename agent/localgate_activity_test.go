package agent

import (
	"strings"
	"testing"
)

func TestActivityWriterSplitsMarkedLinesFromOutput(t *testing.T) {
	var seen []string
	w := &activityWriter{report: func(text string) { seen = append(seen, text) }}
	// A marked line split across two writes, a normal line and an unfinished last line.
	for _, chunk := range []string{"@@activity lint: pyt", "hon3 code-linter.py\nCI Scope: ", "FAILED — x\nlast"} {
		if _, err := w.Write([]byte(chunk)); err != nil {
			t.Fatal(err)
		}
	}
	if len(seen) != 1 || seen[0] != "lint: python3 code-linter.py" {
		t.Fatalf("activity = %q", seen)
	}
	if got := string(w.Bytes()); got != "CI Scope: FAILED — x\nlast" || strings.Contains(got, "@@") {
		t.Fatalf("output = %q", got)
	}
}

func TestJobProgressFollowsPlanAndGateEvents(t *testing.T) {
	p := newJobProgress()
	p.Phase("Starting the checks")
	p.Event(`{"plan":["protected-files","code-linter","swift-compile"]}`)
	p.Event(`{"check":"protected-files","state":"passed"}`)
	p.Event(`{"check":"code-linter","state":"running"}`)
	p.Event(`{"check":"code-linter","state":"running","step":"lint","current":3,"total":40,"detail":"src/a.swift"}`)
	p.Event(`not json`)
	activity, checks := p.Snapshot()
	if activity != "code-linter · lint: src/a.swift (3/40)" {
		t.Fatalf("activity = %q", activity)
	}
	want := []CheckProgress{
		{ID: "protected-files", State: "passed"},
		{ID: "code-linter", State: "running", Step: "lint", Current: 3, Total: 40, Detail: "src/a.swift"},
		{ID: "swift-compile", State: "pending"},
	}
	if len(checks) != 3 || checks[0] != want[0] || checks[1] != want[1] || checks[2] != want[2] {
		t.Fatalf("checks = %+v", checks)
	}
	p.Event(`{"check":"code-linter","state":"failed"}`)
	if _, checks = p.Snapshot(); checks[1] != (CheckProgress{ID: "code-linter", State: "failed"}) {
		t.Fatalf("a finished gate keeps no live detail: %+v", checks[1])
	}
}
