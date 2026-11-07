// Tests that no text in a gate report can exceed the server protocol's string limit.
package agent

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

const serverMaxString = 256

func longestString(value any) int {
	switch typed := value.(type) {
	case string:
		return len([]rune(typed))
	case []any:
		longest := 0
		for _, item := range typed {
			longest = max(longest, longestString(item))
		}
		return longest
	case map[string]any:
		longest := 0
		for _, item := range typed {
			longest = max(longest, longestString(item))
		}
		return longest
	}
	return 0
}

func TestReportTextsStayWithinTheServerStringLimit(t *testing.T) {
	long := strings.Repeat("x", 3000)
	out := "CI Scope: FAILED — " + long + "\n" +
		`{"results":[{"id":"code-linter","status":"failed","detail":"` + long + `"},{"id":"protected-files","status":"failed","detail":"` + long + `"}],"configVersion":3}` + "\n"
	commands := &scriptedCommands{gitHead: gatePin, cliOut: out, cliErr: errors.New("exit status 1")}
	report, err := newScriptedRunner(t, commands).Run(context.Background(), gateJob())
	if err != nil {
		t.Fatal(err)
	}
	var generic any
	encoded, _ := json.Marshal(report)
	if err := json.Unmarshal(encoded, &generic); err != nil {
		t.Fatal(err)
	}
	if longest := longestString(generic); longest > serverMaxString {
		t.Fatalf("a report text has %d characters, the server accepts at most %d", longest, serverMaxString)
	}
	if !strings.Contains(report.Checks[0].Detail, "...") {
		t.Fatalf("a clipped detail should say so, got %q", report.Checks[0].Detail)
	}
}

func TestAFailedRunSummaryAlsoStaysWithinTheLimit(t *testing.T) {
	worker := testGateWorker(&fakeGateServer{}, fakeGateRunner{})
	report := worker.finalReport(LocalGateReport{}, errors.New(strings.Repeat("e", 3000)), false)
	if len([]rune(report.Summary)) > serverMaxString {
		t.Fatalf("summary has %d characters", len([]rune(report.Summary)))
	}
}
