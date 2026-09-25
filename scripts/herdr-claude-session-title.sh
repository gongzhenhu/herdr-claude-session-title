#!/bin/sh
# installed by the gongzhenhu.claude-session-title herdr plugin
# reinstalling the plugin overwrites this file; do not edit in place.
set -eu

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$script_dir/herdr-claude-session-title.py"
