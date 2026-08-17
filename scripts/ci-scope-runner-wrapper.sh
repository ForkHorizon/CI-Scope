#!/bin/bash
set -euo pipefail

# CI Scope passes the stock Actions run.sh as the first argument and the JIT
# options after it. Supervise that process so Agent shutdown cannot leave an
# orphan Runner.Listener behind.
#
# The Agent launches this wrapper as its own process group leader (Setpgid).
# The stock run.sh under RUNNER_MANUALLY_TRAP_SIG=1 gives its backgrounded
# helper (Runner.Listener) a separate process group via job control, so a group
# signal to the wrapper's own group can never reach the listener. The wrapper
# therefore continuously records descendant process groups while the runner
# script is alive and hard-kills every recorded group on termination: once the
# runner script exits, an orphaned listener is reparented to launchd and can
# no longer be discovered through the child chain.

if [[ $# -lt 1 ]]; then
  exit 64
fi
runner_script=$1
shift
if [[ "$runner_script" != /* || ! -x "$runner_script" ]]; then
  exit 66
fi

# Enable job control so the runner script and the watcher run in their own
# process groups. The Agent signals this wrapper's whole group on shutdown;
# without this, the runner script dies on the same group signal before the
# wrapper can enumerate its descendants, and a listener in a job-control
# group of its own survives as an orphan.
set -m

"$runner_script" "$@" &
child_pid=$!
own_pgid="$(ps -o pgid= -p "$$" 2>/dev/null | tr -d '[:space:]' || true)"
child_pgid="$(ps -o pgid= -p "$child_pid" 2>/dev/null | tr -d '[:space:]' || true)"

# Directory of group snapshots: latest wins, shared with the terminator.
snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/ci-scope-runner-groups.XXXXXX")"
snapshot_file="$snapshot_dir/groups"

descendant_pids() {
  local parent=$1 child
  for child in $(pgrep -P "$parent" 2>/dev/null || true); do
    echo "$child"
    descendant_pids "$child"
  done
}

snapshot_descendant_groups() {
  local pid pgid groups=""
  for pid in $(descendant_pids "$child_pid"); do
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$pgid" =~ ^[0-9]+$ && "$pgid" != "$own_pgid" ]]; then
      groups+="$pgid"$'\n'
    fi
  done
  printf '%s' "$groups" | sort -u > "$snapshot_file.new" 2>/dev/null || true
  mv -f "$snapshot_file.new" "$snapshot_file" 2>/dev/null || true
}

# Watcher: keep recording descendant groups while the runner script lives.
watcher_loop() {
  while kill -0 "$child_pid" 2>/dev/null; do
    snapshot_descendant_groups
    sleep 0.25
  done
  snapshot_descendant_groups
}
watcher_loop &
watcher_pid=$!

terminate() {
  trap - TERM INT
  # Stop the watcher first so its final snapshot cannot race this terminator.
  kill -KILL "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true

  local groups pgid
  # The runner script runs in its own job-control group, so it is still alive
  # here and its descendants are still discoverable: refresh the snapshot at
  # signal time before anything is terminated.
  snapshot_descendant_groups
  groups="$(cat "$snapshot_file" 2>/dev/null || true)"

  local live_child_pgid
  live_child_pgid="$(ps -o pgid= -p "$child_pid" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "$live_child_pgid" =~ ^[0-9]+$ && "$live_child_pgid" != "$own_pgid" ]]; then
    kill -TERM "-$live_child_pgid" 2>/dev/null || true
  fi
  kill -TERM "$child_pid" 2>/dev/null || true
  wait "$child_pid" 2>/dev/null || true

  # The runner script's trap may have forwarded termination, or may be gone
  # entirely (its process already exited when the group signal arrived).
  # Hard-kill every recorded descendant group so no Runner.Listener can
  # outlive the runner script. Empty or reused groups fail silently.
  while read -r pgid; do
    [[ -n "$pgid" ]] || continue
    kill -KILL "-$pgid" 2>/dev/null || true
  done <<< "$groups"
  if [[ "$live_child_pgid" =~ ^[0-9]+$ && "$live_child_pgid" != "$own_pgid" ]]; then
    kill -KILL "-$live_child_pgid" 2>/dev/null || true
  fi
  rm -rf "$snapshot_dir" 2>/dev/null || true
  exit 143
}

trap terminate TERM INT
if wait "$child_pid"; then
  kill -KILL "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true
  rm -rf "$snapshot_dir" 2>/dev/null || true
  exit 0
fi
status=$?
kill -KILL "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true
rm -rf "$snapshot_dir" 2>/dev/null || true
exit "$status"
