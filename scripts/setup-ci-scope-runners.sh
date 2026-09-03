#!/usr/bin/env bash
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-$HOME/actions-runners}"
PERSONAL_RUNNER_ROOT="${PERSONAL_RUNNER_ROOT:-$HOME/actions-runner/moodling}"
RUNNER_VERSION="${RUNNER_VERSION:-}"
RUNNER_ROLE="${RUNNER_ROLE:-general}"
RUNNER_INDEX="${RUNNER_INDEX:-1}"
DEFAULT_LABELS="${DEFAULT_LABELS:-ci-scope,macbook-ci,code-linter}"
ORG_EXTRA_LABELS="${ORG_EXTRA_LABELS:-nexus-doc-ai,nexus-unity-ci}"
PERSONAL_EXTRA_LABELS="${PERSONAL_EXTRA_LABELS:-moodling,deepseek}"
AI_LABELS="${AI_LABELS:-self-hosted,macOS,ARM64,ci-scope-ai}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/setup-ci-scope-runners.sh org ForkHorizon
  scripts/setup-ci-scope-runners.sh personal Daliys/MyPrivateRepo

What this creates:
  org      -> an organization-level runner for repos allowed by the org
  personal -> a repository-level runner for one personal repo

Runner profiles:
  RUNNER_ROLE=general (default) -> regular CI gates; multiple indexes allowed
  RUNNER_ROLE=ai                 -> Slop Review; RUNNER_INDEX must be 1

Important:
  GitHub does not support one runner shared across every personal-account repo.
  For personal repos, this script configures one repo-level runner. Re-run the
  personal command with another owner/repo if you want to move that runner.

Required gh auth scopes:
  org runner      -> admin:org
  personal runner -> repo

Environment overrides:
  RUNNER_HOME       default: $HOME/actions-runners
  PERSONAL_RUNNER_ROOT
                    default: $HOME/actions-runner/moodling
  RUNNER_VERSION    default: latest actions/runner release
  RUNNER_ROLE       default: general; general or ai
  RUNNER_INDEX      default: 1; use 2, 3, ... for additional general runners
  DEFAULT_LABELS    default: ci-scope,macbook-ci,code-linter
  ORG_EXTRA_LABELS  default: nexus-doc-ai,nexus-unity-ci
  PERSONAL_EXTRA_LABELS
                    default: moodling,deepseek
  AI_LABELS         default: self-hosted,macOS,ARM64,ci-scope-ai

Examples:
  RUNNER_INDEX=2 scripts/setup-ci-scope-runners.sh org ForkHorizon
  RUNNER_ROLE=ai scripts/setup-ci-scope-runners.sh org ForkHorizon
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

latest_runner_version() {
  if [ -n "$RUNNER_VERSION" ]; then
    printf '%s\n' "$RUNNER_VERSION"
    return
  fi

  python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("https://api.github.com/repos/actions/runner/releases/latest", timeout=20) as response:
    payload = json.load(response)
print(payload["tag_name"].lstrip("v"))
PY
}

ensure_runner_package() {
  local runner_dir=$1
  local version=$2

  mkdir -p "$runner_dir"
  if [ -x "$runner_dir/config.sh" ]; then
    return
  fi

  local archive="actions-runner-osx-arm64-${version}.tar.gz"
  local url="https://github.com/actions/runner/releases/download/v${version}/${archive}"
  local tmp
  tmp=$(mktemp -d)

  echo "Downloading GitHub Actions runner $version"
  curl -fsSL "$url" -o "$tmp/$archive"
  tar -xzf "$tmp/$archive" -C "$runner_dir"
  rm -rf "$tmp"
}

service_status() {
  local runner_dir=$1
  if [ -x "$runner_dir/svc.sh" ]; then
    (cd "$runner_dir" && ./svc.sh status) || true
  fi
}

stop_existing_service() {
  local runner_dir=$1
  if [ -f "$runner_dir/.service" ] && [ -x "$runner_dir/svc.sh" ]; then
    echo "Stopping existing service in $runner_dir"
    (cd "$runner_dir" && ./svc.sh stop) || true
    (cd "$runner_dir" && ./svc.sh uninstall) || true
  fi
}

remove_existing_config() {
  local runner_dir=$1
  if [ -f "$runner_dir/.runner" ] && [ -x "$runner_dir/config.sh" ]; then
    echo "Removing existing runner registration in $runner_dir"
    (cd "$runner_dir" && ./config.sh remove --unattended) || true
  fi
}

configure_service() {
  local runner_dir=$1

  echo "Installing launchd service"
  (cd "$runner_dir" && ./svc.sh install)
  (cd "$runner_dir" && ./svc.sh start)
  service_status "$runner_dir"
}

registration_token() {
  local scope=$1
  local target=$2

  case "$scope" in
    org)
      gh api -X POST "orgs/${target}/actions/runners/registration-token" --jq .token
      ;;
    repo)
      gh api -X POST "repos/${target}/actions/runners/registration-token" --jq .token
      ;;
    *)
      fail "Unknown token scope: $scope"
      ;;
  esac
}

configure_org_runner() {
  local org=$1
  local version
  version=$(latest_runner_version)

  local runner_dir runner_name labels
  if [ "$RUNNER_ROLE" = "general" ] && [ "$RUNNER_INDEX" = "1" ]; then
    # Preserve the original default registration for existing installations.
    runner_dir="${RUNNER_HOME}/$(lowercase "$org")-org-ci"
    runner_name="${org}-MacBook-CI-Scope-Org"
    labels="${DEFAULT_LABELS},ci-scope-org"
    if [ -n "$ORG_EXTRA_LABELS" ]; then
      labels="${labels},${ORG_EXTRA_LABELS}"
    fi
  elif [ "$RUNNER_ROLE" = "general" ]; then
    runner_dir="${RUNNER_HOME}/$(lowercase "$org")-org-general-${RUNNER_INDEX}"
    runner_name="${org}-MacBook-CI-Scope-General-${RUNNER_INDEX}"
    labels="${DEFAULT_LABELS},ci-scope-org"
    if [ -n "$ORG_EXTRA_LABELS" ]; then
      labels="${labels},${ORG_EXTRA_LABELS}"
    fi
  else
    runner_dir="${RUNNER_HOME}/$(lowercase "$org")-org-ai-${RUNNER_INDEX}"
    runner_name="${org}-MacBook-CI-Scope-AI-${RUNNER_INDEX}"
    labels="$AI_LABELS"
  fi
  local token

  ensure_runner_package "$runner_dir" "$version"
  token=$(registration_token org "$org")
  stop_existing_service "$runner_dir"
  remove_existing_config "$runner_dir"

  echo "Configuring organization runner: $org"
  (
    cd "$runner_dir"
    ./config.sh \
      --url "https://github.com/${org}" \
      --token "$token" \
      --name "$runner_name" \
      --labels "$labels" \
      --work "_work" \
      --unattended \
      --replace
  )

  configure_service "$runner_dir"
}

configure_personal_runner() {
  local repo=$1
  [[ "$repo" == */* ]] || fail "Personal runner target must be owner/repo"

  local owner=${repo%%/*}
  local name=${repo##*/}
  local version
  version=$(latest_runner_version)

  local runner_dir runner_name labels
  if [ "$RUNNER_ROLE" = "general" ] && [ "$RUNNER_INDEX" = "1" ]; then
    # Preserve the original default registration for existing installations.
    runner_dir="$PERSONAL_RUNNER_ROOT"
    runner_name="${owner}-MacBook-CI-Scope-Personal"
    labels="${DEFAULT_LABELS},ci-scope-personal"
    if [ -n "$PERSONAL_EXTRA_LABELS" ]; then
      labels="${labels},${PERSONAL_EXTRA_LABELS}"
    fi
  elif [ "$RUNNER_ROLE" = "general" ]; then
    runner_dir="${PERSONAL_RUNNER_ROOT}-general-${RUNNER_INDEX}"
    runner_name="${owner}-MacBook-CI-Scope-General-${RUNNER_INDEX}"
    labels="${DEFAULT_LABELS},ci-scope-personal"
    if [ -n "$PERSONAL_EXTRA_LABELS" ]; then
      labels="${labels},${PERSONAL_EXTRA_LABELS}"
    fi
  else
    runner_dir="${PERSONAL_RUNNER_ROOT}-ai-${RUNNER_INDEX}"
    runner_name="${owner}-MacBook-CI-Scope-AI-${RUNNER_INDEX}"
    labels="$AI_LABELS"
  fi
  local token

  ensure_runner_package "$runner_dir" "$version"
  token=$(registration_token repo "$repo")
  stop_existing_service "$runner_dir"
  remove_existing_config "$runner_dir"

  echo "Configuring personal repo runner: $repo"
  (
    cd "$runner_dir"
    ./config.sh \
      --url "https://github.com/${repo}" \
      --token "$token" \
      --name "$runner_name" \
      --labels "$labels" \
      --work "_work" \
      --unattended \
      --replace
  )

  configure_service "$runner_dir"

  echo
  echo "Personal runner now points to ${owner}/${name}."
  echo "GitHub personal accounts cannot share one runner across all personal repos."
}

main() {
  require_command gh
  require_command git
  require_command curl
  require_command tar
  require_command python3

  if [ $# -lt 2 ]; then
    usage
    exit 2
  fi

  case "$RUNNER_ROLE" in
    general|ai) ;;
    *) fail "RUNNER_ROLE must be general or ai" ;;
  esac
  [[ "$RUNNER_INDEX" =~ ^[1-9][0-9]*$ ]] || fail "RUNNER_INDEX must be a positive integer"
  if [ "$RUNNER_ROLE" = "ai" ] && [ "$RUNNER_INDEX" != "1" ]; then
    fail "Only one AI runner is supported; keep RUNNER_INDEX=1"
  fi
  if [ "$RUNNER_ROLE" = "ai" ] && [[ ",$AI_LABELS," == *,ci-scope,* ]]; then
    fail "AI_LABELS must not include the general ci-scope label"
  fi

  case "$1" in
    org)
      configure_org_runner "$2"
      ;;
    personal)
      configure_personal_runner "$2"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
