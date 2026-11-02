// Checks a pull request in a clean checkout with the pinned ci-gates CLI.
package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	localGateTier       = "push"
	localGateMaxDetail  = 3900
	localGateMaxSummary = 3900
)

// commandRunner runs one command and returns its combined output; swapped out in tests.
type commandRunner func(ctx context.Context, dir, name string, args ...string) ([]byte, error)

func execCommand(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	command := exec.CommandContext(ctx, name, args...)
	command.Dir = dir
	var output bytes.Buffer
	command.Stdout, command.Stderr = &output, &output
	err := command.Run()
	return output.Bytes(), err
}

// GateScriptRunner checks a pull request in a clean checkout with the pinned ci-gates `ci-scope check`.
type GateScriptRunner struct {
	WorkspaceRoot string // where per-repository checkouts live
	GatesRoot     string // pinned ci-gates checkout
	GatesSHA      string // commit GatesRoot must be at
	run           commandRunner
	now           func() time.Time
}

func NewGateScriptRunner(workspaceRoot, gatesRoot, gatesSHA string) *GateScriptRunner {
	return &GateScriptRunner{WorkspaceRoot: workspaceRoot, GatesRoot: gatesRoot, GatesSHA: gatesSHA, run: execCommand, now: time.Now}
}

func (r *GateScriptRunner) Run(ctx context.Context, job LocalGateJob) (LocalGateReport, error) {
	if err := r.verifyGates(ctx); err != nil {
		return LocalGateReport{}, err
	}
	dir, err := r.checkout(ctx, job)
	if err != nil {
		return LocalGateReport{}, err
	}
	script := filepath.Join(r.GatesRoot, "scripts", "ci_scope_cli.py")
	output, runErr := r.run(ctx, dir, "python3", script, "--event", "pull_request", "--tier", localGateTier,
		"--base", job.BaseSHA, "--head", job.HeadSHA, "--repository", job.Repository, "--root", dir, "--json")
	return r.report(output, runErr), nil
}

func (r *GateScriptRunner) verifyGates(ctx context.Context) error {
	head, err := r.run(ctx, r.GatesRoot, "git", "rev-parse", "HEAD")
	if err != nil || strings.TrimSpace(string(head)) != r.GatesSHA {
		return fmt.Errorf("ci-gates is not at the pinned commit %s", r.GatesSHA)
	}
	status, err := r.run(ctx, r.GatesRoot, "git", "status", "--porcelain", "--untracked-files=all")
	if err != nil || strings.TrimSpace(string(status)) != "" {
		return fmt.Errorf("ci-gates checkout has local changes; refusing to run unpinned code")
	}
	return nil
}

func (r *GateScriptRunner) checkout(ctx context.Context, job LocalGateJob) (string, error) {
	if !validRepository(job.Repository) || !validCommit(job.HeadSHA) || !validCommit(job.BaseSHA) {
		return "", fmt.Errorf("job %s has an invalid repository or commit", job.ID)
	}
	dir := filepath.Join(r.WorkspaceRoot, strings.ReplaceAll(job.Repository, "/", "__"))
	if _, err := os.Stat(filepath.Join(dir, ".git")); err != nil {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return "", err
		}
		if out, err := r.run(ctx, dir, "git", "clone", "--no-checkout", "https://github.com/"+job.Repository+".git", "."); err != nil {
			return "", fmt.Errorf("clone failed: %s", clip(string(out), 300))
		}
	}
	steps := [][]string{
		{"fetch", "--quiet", "origin", job.BaseSHA, job.HeadSHA},
		{"checkout", "--quiet", "--detach", "--force", job.HeadSHA},
		{"clean", "-ffdxq"},
	}
	for _, step := range steps {
		if out, err := r.run(ctx, dir, "git", step...); err != nil {
			return "", fmt.Errorf("git %s failed: %s", step[0], clip(string(out), 300))
		}
	}
	return dir, nil
}

// report turns the CLI output (one verdict line, then a JSON line) into a server report.
func (r *GateScriptRunner) report(output []byte, runErr error) LocalGateReport {
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	summary := clip(lines[0], localGateMaxSummary)
	report := LocalGateReport{Status: "failed", Summary: summary, Checks: []LocalGateCheck{}, CompletedAt: r.now().UnixMilli()}
	var parsed struct {
		ConfigVersion int `json:"configVersion"`
		Results       []struct {
			ID     string `json:"id"`
			Status string `json:"status"`
			Detail string `json:"detail"`
		} `json:"results"`
	}
	if len(lines) < 2 || json.Unmarshal([]byte(lines[len(lines)-1]), &parsed) != nil || len(parsed.Results) == 0 {
		if runErr != nil && summary == "" {
			report.Summary = "CI Scope: FAILED — " + clip(runErr.Error(), 300)
		}
		return report
	}
	report.ConfigVersion = parsed.ConfigVersion
	allPassed := true
	for _, item := range parsed.Results {
		report.Checks = append(report.Checks, LocalGateCheck{ID: item.ID, Status: item.Status, Required: true, Detail: clip(item.Detail, localGateMaxDetail)})
		allPassed = allPassed && item.Status == "passed"
	}
	if allPassed && runErr == nil {
		report.Status = "passed"
	}
	return report
}

func clip(text string, limit int) string {
	text = strings.Join(strings.Fields(text), " ")
	if len(text) <= limit {
		return text
	}
	return text[:limit-3] + "..."
}

func validRepository(value string) bool {
	owner, name, ok := strings.Cut(value, "/")
	return ok && safeSlug(owner) && safeSlug(name)
}

func safeSlug(value string) bool {
	if value == "" || strings.HasPrefix(value, ".") {
		return false
	}
	for _, r := range value {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.') {
			return false
		}
	}
	return true
}

func validCommit(value string) bool {
	if len(value) != 40 {
		return false
	}
	for _, r := range value {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') {
			return false
		}
	}
	return true
}
