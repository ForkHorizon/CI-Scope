#!/bin/sh
set -eu
umask 077

production_service="${CI_SCOPE_PRODUCTION_KEYCHAIN_SERVICE:-com.forkhorizon.ci-scope.production}"
agent_service="${CI_SCOPE_AGENT_KEYCHAIN_SERVICE:-com.forkhorizon.ci-scope.agent}"
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

put_if_missing "$production_service" local-token
put_if_missing "$agent_service" shadow-token
put_if_missing "$production_service" enrollment-issuer
put_if_missing "$production_service" webhook-secret
put_if_missing "$production_service" admin-password

echo "production Keychain entries ready"
