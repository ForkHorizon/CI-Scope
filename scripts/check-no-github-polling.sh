#!/bin/bash
# The app reads CI state from the CI Scope server, never from GitHub: a personal gh token has 5000 requests/hour
# shared with every tool, and an old build burnt it with `gh run list` every ~28 s per repository.
# Only the one-off login lookup may call gh; anything else needs a deliberate edit of this script.
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(grep -rnE 'gh (run|pr|api|workflow|search) ' "CI Scope" --include='*.swift' | grep -v '//' | grep -v 'gh api user --jq .login' || true)
if [[ -n "$hits" ]]; then
  echo "App sources must not call GitHub through gh (read the CI Scope server instead):" >&2
  echo "$hits" >&2
  exit 1
fi
