#!/bin/sh
set -eu

usage() {
	echo "usage: $0 <watchdog-executable> <rendered-plist>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage
watchdog_path=$1
plist_path=$2

[ -x "$watchdog_path" ] || {
	echo "watchdog executable is missing or not executable: $watchdog_path" >&2
	exit 1
}
[ -f "$plist_path" ] || {
	echo "rendered watchdog plist is missing: $plist_path" >&2
	exit 1
}

command -v plutil >/dev/null 2>&1 || {
	echo "plutil is required to validate a launchd plist" >&2
	exit 1
}
plutil -lint "$plist_path" >/dev/null

if grep -F '{{' "$plist_path" >/dev/null 2>&1 || grep -F '}}' "$plist_path" >/dev/null 2>&1; then
	echo "watchdog plist still contains template placeholders" >&2
	exit 1
fi
if ! grep -F "<string>$watchdog_path</string>" "$plist_path" >/dev/null 2>&1; then
	echo "watchdog plist does not launch the validated executable" >&2
	exit 1
fi
