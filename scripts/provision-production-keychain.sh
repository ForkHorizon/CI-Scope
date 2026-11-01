#!/bin/sh
set -eu
umask 077

production_service="${CI_SCOPE_PRODUCTION_KEYCHAIN_SERVICE:-com.forkhorizon.ci-scope.production}"
agent_service="${CI_SCOPE_AGENT_KEYCHAIN_SERVICE:-com.forkhorizon.ci-scope.agent}"
web_ssh_host="${CI_SCOPE_WEB_SSH_HOST:-daliys@143.14.22.61}"
web_env_file="${CI_SCOPE_WEB_ENV_FILE:-/etc/ci-scope-web/env}"
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/ci-scope-keychain.XXXXXX")
helper="$temporary_dir/ci-scope-keychain-put"
trap 'unlink "$helper"; rmdir "$temporary_dir"' EXIT INT TERM

swiftc -O -framework Security "$script_dir/ci-scope-keychain-put.swift" -o "$helper"

put_if_missing() {
  service=$1
  account=$2
  if current=$(/usr/bin/security find-generic-password -s "$service" -a "$account" -w 2>/dev/null); then
    if [ -n "$current" ]; then
      unset current
      return
    fi
  fi
  unset current
  value=$(openssl rand -hex 32)
  printf '%s' "$value" | "$helper" "$service" "$account"
  unset value
}

# Unlike the tokens above (locally generated, then the server is configured to
# accept them), policy-read-token must equal a value that already exists
# server-side (CI_SCOPE_POLICY_READ_TOKEN in $web_env_file) — nothing local can
# invent it. put_if_missing also can't detect drift: a present-but-stale value
# isn't "missing", so it would never get refreshed if the server's copy
# rotated. Always overwrite from the server instead. (2026-09: found stale by
# 16 days with no way to self-heal — see .projectmem for the incident.)
sync_policy_read_token() {
  value=$(ssh "$web_ssh_host" "sudo grep '^CI_SCOPE_POLICY_READ_TOKEN=' $web_env_file | cut -d= -f2-" | tr -d '\n')
  if [ -z "$value" ]; then
    echo "policy-read-token: got an empty value from $web_ssh_host:$web_env_file — aborting" >&2
    exit 1
  fi
  printf '%s' "$value" | "$helper" "$production_service" policy-read-token
  unset value
}

put_if_missing "$production_service" local-token
put_if_missing "$agent_service" shadow-token
put_if_missing "$production_service" enrollment-issuer
put_if_missing "$production_service" webhook-secret
put_if_missing "$production_service" admin-password
sync_policy_read_token

echo "production Keychain entries ready"
