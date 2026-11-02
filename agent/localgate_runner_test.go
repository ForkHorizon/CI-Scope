package agent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const (
	gateHead = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	gateBase = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	gatePin  = "cccccccccccccccccccccccccccccccccccccccc"
)

type recordedCommand struct {
	dir  string
	line string
}

type scriptedCommands struct {
	calls   []recordedCommand
	gitHead string
	dirty   string
	cliOut  string
	cliErr  error
	failOn  string
}

func (s *scriptedCommands) run(_ context.Context, dir, name string, args ...string) ([]byte, error) {
	line := name + " " + strings.Join(args, " ")
	s.calls = append(s.calls, recordedCommand{dir, line})
	switch {
	case line == "git rev-parse HEAD":
		return []byte(s.gitHead + "\n"), nil
	case strings.HasPrefix(line, "git status"):
		return []byte(s.dirty), nil
	case s.failOn != "" && strings.HasPrefix(line, s.failOn):
		return []byte("boom"), errors.New("exit status 1")
	case name == "python3":
		return []byte(s.cliOut), s.cliErr
	}
	return nil, nil
}

func newScriptedRunner(t *testing.T, commands *scriptedCommands) *GateScriptRunner {
	t.Helper()
	runner := NewGateScriptRunner(t.TempDir(), "/gates", gatePin)
	runner.run = commands.run
	runner.now = func() time.Time { return time.UnixMilli(42) }
	return runner
}

func gateJob() LocalGateJob {
	return LocalGateJob{ID: "job-1", Repository: "ForkHorizon/Example", PullRequest: 3, HeadSHA: gateHead, BaseSHA: gateBase}
}

const passingOutput = "CI Scope: PASSED — 2 of 2 checks passed\n" +
	`{"results":[{"id":"protected-files","status":"passed","detail":""},{"id":"code-linter","status":"passed","detail":""}]}` + "\n"

func TestRunnerChecksOutTheHeadAndRunsTheCLIWithPinnedRevisions(t *testing.T) {
	commands := &scriptedCommands{gitHead: gatePin, cliOut: passingOutput}
	runner := newScriptedRunner(t, commands)
	report, err := runner.Run(context.Background(), gateJob())
	if err != nil {
		t.Fatal(err)
	}
	if report.Status != "passed" || len(report.Checks) != 2 || !report.Checks[0].Required || report.CompletedAt != 42 {
		t.Fatalf("report = %#v", report)
	}
	var lines []string
	for _, call := range commands.calls {
		lines = append(lines, call.line)
	}
	joined := strings.Join(lines, "\n")
	for _, want := range []string{
		"git clone --no-checkout https://github.com/ForkHorizon/Example.git .",
		"git fetch --quiet origin " + gateBase + " " + gateHead,
		"git checkout --quiet --detach --force " + gateHead,
		"git clean -ffdxq",
		"python3 /gates/scripts/ci_scope_cli.py --event pull_request --tier push --base " + gateBase + " --head " + gateHead,
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("missing command %q in:\n%s", want, joined)
		}
	}
}

func TestRunnerFetchesInsteadOfCloningWhenTheWorkspaceExists(t *testing.T) {
	commands := &scriptedCommands{gitHead: gatePin, cliOut: passingOutput}
	runner := newScriptedRunner(t, commands)
	if err := os.MkdirAll(filepath.Join(runner.WorkspaceRoot, "ForkHorizon__Example", ".git"), 0o700); err != nil {
		t.Fatal(err)
	}
	if _, err := runner.Run(context.Background(), gateJob()); err != nil {
		t.Fatal(err)
	}
	for _, call := range commands.calls {
		if strings.HasPrefix(call.line, "git clone") {
			t.Fatalf("cloned although the workspace exists: %s", call.line)
		}
	}
}

func TestRunnerRefusesUnpinnedOrModifiedGates(t *testing.T) {
	wrong := &scriptedCommands{gitHead: "dddddddddddddddddddddddddddddddddddddddd"}
	if _, err := newScriptedRunner(t, wrong).Run(context.Background(), gateJob()); err == nil || !strings.Contains(err.Error(), "pinned commit") {
		t.Fatalf("err = %v, want a pin error", err)
	}
	dirty := &scriptedCommands{gitHead: gatePin, dirty: " M scripts/code-linter.py\n"}
	if _, err := newScriptedRunner(t, dirty).Run(context.Background(), gateJob()); err == nil || !strings.Contains(err.Error(), "local changes") {
		t.Fatalf("err = %v, want a dirty checkout error", err)
	}
	for _, call := range dirty.calls {
		if call.dir != "/gates" {
			t.Fatalf("ran %q outside the gates checkout before verifying it", call.line)
		}
	}
}

func TestRunnerRejectsJobsThatCouldInjectArguments(t *testing.T) {
	for name, mutate := range map[string]func(*LocalGateJob){
		"repository path":  func(j *LocalGateJob) { j.Repository = "../../etc/passwd" },
		"repository flag":  func(j *LocalGateJob) { j.Repository = "--upload-pack=x/y" },
		"short commit":     func(j *LocalGateJob) { j.HeadSHA = "abc" },
		"commit with flag": func(j *LocalGateJob) { j.BaseSHA = "--output=/tmp/x" + strings.Repeat("a", 24) },
	} {
		commands := &scriptedCommands{gitHead: gatePin}
		job := gateJob()
		mutate(&job)
		if _, err := newScriptedRunner(t, commands).Run(context.Background(), job); err == nil {
			t.Fatalf("%s: expected the job to be rejected", name)
		}
		for _, call := range commands.calls {
			if strings.HasPrefix(call.line, "git fetch") || strings.HasPrefix(call.line, "git clone") {
				t.Fatalf("%s: ran %q for a rejected job", name, call.line)
			}
		}
	}
}

func TestRunnerReportsAFailingCheck(t *testing.T) {
	out := "CI Scope: FAILED — protected-files: modified Cargo.toml\n" +
		`{"results":[{"id":"protected-files","status":"failed","detail":"modified Cargo.toml"},{"id":"code-linter","status":"passed","detail":""}]}` + "\n"
	commands := &scriptedCommands{gitHead: gatePin, cliOut: out, cliErr: errors.New("exit status 1")}
	report, err := newScriptedRunner(t, commands).Run(context.Background(), gateJob())
	if err != nil {
		t.Fatal(err)
	}
	if report.Status != "failed" || report.Checks[0].Status != "failed" || !strings.Contains(report.Summary, "modified Cargo.toml") {
		t.Fatalf("report = %#v", report)
	}
}

func TestRunnerTurnsToolErrorsIntoAFailedReport(t *testing.T) {
	commands := &scriptedCommands{gitHead: gatePin, cliOut: "CI Scope: FAILED — the config digest does not match; refusing to use it\n", cliErr: errors.New("exit status 2")}
	report, err := newScriptedRunner(t, commands).Run(context.Background(), gateJob())
	if err != nil || report.Status != "failed" || len(report.Checks) != 0 || !strings.Contains(report.Summary, "digest") {
		t.Fatalf("report = %#v, err = %v", report, err)
	}
	empty := &scriptedCommands{gitHead: gatePin, cliOut: "", cliErr: errors.New("python3: not found")}
	report, _ = newScriptedRunner(t, empty).Run(context.Background(), gateJob())
	if report.Status != "failed" || !strings.Contains(report.Summary, "not found") {
		t.Fatalf("report = %#v", report)
	}
}

func TestRunnerNeverPassesWhenTheCLIFailedEvenIfResultsLookGreen(t *testing.T) {
	commands := &scriptedCommands{gitHead: gatePin, cliOut: passingOutput, cliErr: errors.New("exit status 1")}
	report, _ := newScriptedRunner(t, commands).Run(context.Background(), gateJob())
	if report.Status != "failed" {
		t.Fatalf("status = %q, want failed when the process exited non-zero", report.Status)
	}
}

func TestRunnerSurfacesGitFailures(t *testing.T) {
	commands := &scriptedCommands{gitHead: gatePin, failOn: "git fetch"}
	if _, err := newScriptedRunner(t, commands).Run(context.Background(), gateJob()); err == nil || !strings.Contains(err.Error(), "git fetch failed") {
		t.Fatalf("err = %v", err)
	}
}
