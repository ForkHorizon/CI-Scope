#!/bin/sh
set -eu

usage() {
  echo "usage: $0 <agent-path> <control-plane-url> <machine-id> <credential-id> [output-path]" >&2
  exit 2
}

[ "$#" -ge 4 ] || usage

agent_path=$1
control_plane_url=$2
machine_id=$3
credential_id=$4
output_path=${5:-"$HOME/Library/LaunchAgents/com.forkhorizon.ci-scope.agent.plist"}
keychain_service=${CI_SCOPE_KEYCHAIN_SERVICE:-com.forkhorizon.ci-scope.agent}
shadow_account=${CI_SCOPE_V2_SHADOW_TOKEN_KEYCHAIN_ACCOUNT:-shadow-token}
pool_identity=${CI_SCOPE_POOL_IDENTITY:-forkhorizon-production}
runner_executable=${CI_SCOPE_RUNNER_EXECUTABLE:-}
runner_workspace_root=${CI_SCOPE_RUNNER_WORKSPACE_ROOT:-}
runner_script=${CI_SCOPE_RUNNER_SCRIPT:-}
runner_temp_root=${CI_SCOPE_RUNNER_TEMP_ROOT:-}
state_root=${CI_SCOPE_STATE_ROOT:-"$HOME/Library/Application Support/CI-Scope"}
socket_path=${CI_SCOPE_SOCKET_PATH:-"$state_root/agent.sock"}
log_dir=${CI_SCOPE_LOG_DIR:-"$HOME/Library/Logs/CI-Scope"}

if [ -n "$runner_executable" ] || [ -n "$runner_workspace_root" ]; then
	[ -n "$runner_executable" ] && [ -n "$runner_workspace_root" ] && [ -n "$runner_script" ] || {
		echo "runner executable, workspace root, and runner script must be configured together" >&2
		exit 1
	}
	[ -x "$runner_executable" ] || { echo "runner executable is missing or not executable: $runner_executable" >&2; exit 1; }
	[ -x "$runner_script" ] || { echo "runner script is missing or not executable: $runner_script" >&2; exit 1; }
fi

for value in "$agent_path" "$control_plane_url" "$machine_id" "$credential_id" "$keychain_service" "$shadow_account" "$pool_identity" "$runner_executable" "$runner_workspace_root" "$runner_script" "$runner_temp_root" "$state_root" "$socket_path" "$log_dir"; do
  case "$value" in
    *'&'*|*'<'*|*'>'*|*'"'*)
      echo "launchd value contains XML metacharacters" >&2
      exit 1
      ;;
  esac
done

[ -x "$agent_path" ] || { echo "Agent executable is missing or not executable: $agent_path" >&2; exit 1; }

boot_id=$(sysctl -n kern.boottime | shasum -a 256 | awk '{print substr($1, 1, 32)}')
agent_instance_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
session_request_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

escape_sed() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

rendered=$(mktemp "${TMPDIR:-/tmp}/ci-scope-agent-plist.XXXXXX")
trap 'rm -f "$rendered"' EXIT INT TERM

sed \
  -e "s|{{AGENT_PATH}}|$(escape_sed "$agent_path")|g" \
  -e "s|{{CONTROL_PLANE_URL}}|$(escape_sed "$control_plane_url")|g" \
  -e "s|{{MACHINE_ID}}|$(escape_sed "$machine_id")|g" \
  -e "s|{{BOOT_ID}}|$(escape_sed "$boot_id")|g" \
  -e "s|{{AGENT_INSTANCE_ID}}|$(escape_sed "$agent_instance_id")|g" \
  -e "s|{{CREDENTIAL_ID}}|$(escape_sed "$credential_id")|g" \
  -e "s|{{POOL_IDENTITY}}|$(escape_sed "$pool_identity")|g" \
  -e "s|{{SESSION_REQUEST_ID}}|$(escape_sed "$session_request_id")|g" \
  -e "s|{{SOCKET_PATH}}|$(escape_sed "$socket_path")|g" \
  -e "s|{{STATE_ROOT}}|$(escape_sed "$state_root")|g" \
  -e "s|{{KEYCHAIN_SERVICE}}|$(escape_sed "$keychain_service")|g" \
  -e "s|{{SHADOW_ACCOUNT}}|$(escape_sed "$shadow_account")|g" \
  -e "s|{{RUNNER_EXECUTABLE}}|$(escape_sed "$runner_executable")|g" \
  -e "s|{{RUNNER_WORKSPACE_ROOT}}|$(escape_sed "$runner_workspace_root")|g" \
  -e "s|{{RUNNER_SCRIPT}}|$(escape_sed "$runner_script")|g" \
  -e "s|{{RUNNER_TEMP_ROOT}}|$(escape_sed "$runner_temp_root")|g" \
  -e "s|{{LOG_DIR}}|$(escape_sed "$log_dir")|g" \
  "$(dirname "$0")/com.forkhorizon.ci-scope.agent.plist.tmpl" > "$rendered"

mkdir -p "$(dirname "$output_path")" "$state_root" "$log_dir"
chmod 700 "$state_root" "$log_dir"
mv "$rendered" "$output_path"
chmod 600 "$output_path"
echo "$output_path"
