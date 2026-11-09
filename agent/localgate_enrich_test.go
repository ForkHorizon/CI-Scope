// Tests for the optional model step: tiers fall through, answers are grounded, the raw excerpt never leaves the agent.
package agent

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

const enrichExcerpt = "Traceback\n  File \"app/main.py\", line 7, in run\nValueError: bad config value"

const goodAnswer = `{"cause":"config value is invalid","fix":"fix the value","findings":[{"file":"app/main.py","line":7,"rule":"ValueError","quote":"ValueError: bad config value"}]}`

func answer(text string, err error) askModel {
	return func(context.Context, string) (string, error) { return text, err }
}

func TestExplainUsesCodexAndGroundsTheFinding(t *testing.T) {
	got := (&Enricher{Codex: answer(goodAnswer, nil)}).Explain(context.Background(), "tests", enrichExcerpt)
	if got != "app/main.py:7 ValueError | config value is invalid | fix: fix the value" {
		t.Fatalf("got %q", got)
	}
}

func TestExplainFallsBackToLocalWhenCodexFailsOrIsUnusable(t *testing.T) {
	for _, codex := range []askModel{answer("", errors.New("offline")), answer("not json", nil)} {
		got := (&Enricher{Codex: codex, Local: answer(goodAnswer, nil)}).Explain(context.Background(), "tests", enrichExcerpt)
		if !strings.HasPrefix(got, "app/main.py:7") {
			t.Fatalf("local tier not used: %q", got)
		}
	}
}

func TestExplainDropsAQuoteTheLogDoesNotContain(t *testing.T) {
	invented := `{"cause":"c","fix":"f","findings":[{"file":"evil.py","line":1,"rule":"X","quote":"this line is not in the log"}]}`
	got := (&Enricher{Codex: answer(invented, nil)}).Explain(context.Background(), "tests", enrichExcerpt)
	if got != "c | fix: f" {
		t.Fatalf("ungrounded finding kept: %q", got)
	}
}

func TestExplainIsEmptyWhenOffOrBothTiersFail(t *testing.T) {
	var off *Enricher
	if off.Explain(context.Background(), "t", enrichExcerpt) != "" || (&Enricher{}).Explain(context.Background(), "t", enrichExcerpt) != "" {
		t.Fatal("a disabled enricher must return nothing")
	}
	down := &Enricher{Codex: answer("", errors.New("x")), Local: answer("", errors.New("y"))}
	if down.Explain(context.Background(), "t", enrichExcerpt) != "" {
		t.Fatal("both tiers down must leave the rules text")
	}
}

func TestRunEnrichesOnlyUnstructuredChecksAndNeverSendsTheExcerpt(t *testing.T) {
	out := "CI Scope: FAILED — x\n" + `{"configVersion":1,"results":[` +
		`{"id":"code-linter","status":"failed","detail":"a.py:1 E1: bad"},` +
		`{"id":"web-tests","status":"failed","detail":"raw tail","unstructured":true,"excerpt":"` +
		strings.ReplaceAll(strings.ReplaceAll(enrichExcerpt, "\n", `\n`), `"`, `\"`) + `"}]}` + "\n"
	runner := newScriptedRunner(t, &scriptedCommands{gitHead: gatePin, cliOut: out, cliErr: errors.New("exit status 1")})
	runner.Enrich = &Enricher{Codex: answer(goodAnswer, nil)}
	report, err := runner.Run(context.Background(), gateJob())
	if err != nil {
		t.Fatal(err)
	}
	if report.Checks[0].Detail != "a.py:1 E1: bad" || !strings.HasPrefix(report.Checks[1].Detail, "app/main.py:7 ValueError") {
		t.Fatalf("details: %q / %q", report.Checks[0].Detail, report.Checks[1].Detail)
	}
	encoded, _ := json.Marshal(report)
	if strings.Contains(string(encoded), "Traceback") {
		t.Fatal("the raw excerpt leaked into the report")
	}
}
