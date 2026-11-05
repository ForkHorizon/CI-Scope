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
