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
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	localGateTier = "push"
	// The server's request protocol rejects any string longer than 256 characters, so every text in a
	// report stays well below that; a longer one would make the whole report fail with invalid_request.
	localGateMaxDetail  = 240
	localGateMaxSummary = 240
)

// commandRunner runs one command and returns its combined output; swapped out in tests.
type commandRunner func(ctx context.Context, dir, name string, args ...string) ([]byte, error)

// gateEnvironment is everything a checked command gets: it runs code from a pull request, so it never inherits
// the agent's own environment (control plane settings, credential IDs and the like).
func gateEnvironment() []string {
	home := os.Getenv("HOME")
	return []string{
		// Where the toolchains the gates need live: Homebrew, user-level node and rustup/cargo, then the system.
		"PATH=" + strings.Join([]string{home + "/.cargo/bin", home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"}, ":"),
		"HOME=" + home,
		"LANG=en_US.UTF-8",
		"GIT_TERMINAL_PROMPT=0",
		// A checked-out pull request must not get to run its own git hooks inside the agent.
		"GIT_CONFIG_COUNT=1", "GIT_CONFIG_KEY_0=core.hooksPath", "GIT_CONFIG_VALUE_0=/dev/null",
	}
}

// GateSearchPath is the PATH checked commands run with. Capability detection must look there too: a LaunchAgent's own
// PATH is only /usr/bin:/bin:..., so cargo under /opt/homebrew/bin would never be found and its jobs never claimed.
func GateSearchPath() string {
	for _, entry := range gateEnvironment() {
		if path, ok := strings.CutPrefix(entry, "PATH="); ok {
			return path
		}
	}
	return ""
}

// LookGatePath finds a tool the way the gate commands will: on GateSearchPath. exec.Command resolves a bare name
// with this process's PATH instead of command.Env, so a LaunchAgent would run /usr/bin/python3 (3.9) and not Homebrew's.
func LookGatePath(name string) (string, error) {
	for _, dir := range filepath.SplitList(GateSearchPath()) {
		if path, err := exec.LookPath(filepath.Join(dir, name)); err == nil {
			return path, nil
		}
	}
	return "", exec.ErrNotFound
}

// gateKillGrace is how long a cancelled command gets before its output pipes are abandoned.
const gateKillGrace = 5 * time.Second

func execCommand(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	if resolved, err := LookGatePath(name); err == nil {
		name = resolved
	}
	command := exec.CommandContext(ctx, name, args...)
	command.Dir = dir
	command.Env = gateEnvironment()
	// Its own process group, so cancelling stops the children too (a test runner, a build, a stray sleep).
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	command.Cancel = func() error { return syscall.Kill(-command.Process.Pid, syscall.SIGKILL) }
	command.WaitDelay = gateKillGrace
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
	arguments := []string{script, "--event", "pull_request", "--tier", localGateTier,
		"--base", job.BaseSHA, "--head", job.HeadSHA, "--repository", job.Repository, "--root", dir, "--json"}
	if job.ConfigVersion > 0 {
		// Judge the pull request by the config version fixed when it was queued, not by whatever it is now.
		arguments = append(arguments, "--config-version", strconv.Itoa(job.ConfigVersion))
	}
	output, runErr := r.run(ctx, dir, "python3", arguments...)
	return r.report(output, runErr), nil
}

func (r *GateScriptRunner) verifyGates(ctx context.Context) error {
	// The report goes to a PR check where nobody sees the agent's log: say what was found, where, and the fix.
	head, err := r.run(ctx, r.GatesRoot, "git", "rev-parse", "HEAD")
	if err != nil {
		return &environmentError{fmt.Sprintf("cannot read ci-gates HEAD in %s: %s", r.GatesRoot, clip(string(head)+" "+err.Error(), 120))}
	}
	if got := strings.TrimSpace(string(head)); got != r.GatesSHA {
		// Self-heal: the pin moved ahead of this checkout. Checkout without --force, so local edits are never lost.
		if out, err := r.syncGates(ctx); err != nil {
			return &environmentError{fmt.Sprintf("ci-gates in %s is at %s, expected pinned %s, and auto-sync failed: %s",
				r.GatesRoot, shortSHA(got), shortSHA(r.GatesSHA), clip(out, 120))}
		}
	}
	status, err := r.run(ctx, r.GatesRoot, "git", "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return &environmentError{fmt.Sprintf("cannot read ci-gates status in %s: %s", r.GatesRoot, clip(string(status)+" "+err.Error(), 120))}
	}
	if changed := strings.TrimSpace(string(status)); changed != "" {
		return &environmentError{fmt.Sprintf("ci-gates checkout %s has local changes, refusing unpinned code: %s", r.GatesRoot, clip(changed, 120))}
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
			return "", &environmentError{"clone failed: " + clip(string(out), 300)}
		}
	}
	steps := [][]string{
		{"fetch", "--quiet", "origin", job.BaseSHA, job.HeadSHA},
		{"checkout", "--quiet", "--detach", "--force", job.HeadSHA},
		{"clean", "-ffdxq"},
	}
	for _, step := range steps {
		if out, err := r.run(ctx, dir, "git", step...); err != nil {
			return "", &environmentError{fmt.Sprintf("git %s failed: %s", step[0], clip(string(out), 300))}
		}
	}
	return dir, nil
}

// report turns the CLI output (one verdict line, then a JSON line) into a server report.
func (r *GateScriptRunner) report(output []byte, runErr error) LocalGateReport {
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	summary := clip(lines[0], localGateMaxSummary)
	if last := lines[len(lines)-1]; last != "" && (len(lines) < 2 || !strings.HasPrefix(lines[0], "CI Scope:")) {
		// No verdict line: the script crashed, and the cause is at the end of its output (a traceback's last line).
		summary = clip("CI Scope: FAILED — "+last, localGateMaxSummary)
	}
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

// environmentError is a problem with the agent's machine, not with the pull request being checked.
type environmentError struct{ msg string }

func (e *environmentError) Error() string { return e.msg }

// syncGates moves the pinned ci-gates checkout to GatesSHA and confirms it landed there.
func (r *GateScriptRunner) syncGates(ctx context.Context) (string, error) {
	for _, step := range [][]string{{"fetch", "--quiet", "origin", r.GatesSHA}, {"checkout", "--quiet", "--detach", r.GatesSHA}} {
		if out, err := r.run(ctx, r.GatesRoot, "git", step...); err != nil {
			return "git " + step[0] + ": " + string(out), err
		}
	}
	head, err := r.run(ctx, r.GatesRoot, "git", "rev-parse", "HEAD")
	if err != nil || strings.TrimSpace(string(head)) != r.GatesSHA {
		return "checkout did not land on the pinned commit", fmt.Errorf("not synced")
	}
	return "", nil
}

func shortSHA(sha string) string {
	if len(sha) > 12 {
		return sha[:12]
	}
	return sha
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
