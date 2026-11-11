#!/usr/bin/env bash
# Codex `notify` wrapper (wired in ~/.codex/config.toml).
# Codex calls: codex-notify.sh <json>   with {"type":"agent-turn-complete", "cwd":..., "last-assistant-message":..., ...}
# 1. if you already had a notify program, set CODEX_NOTIFY_ORIG to it and it is still called first
# 2. log a turn-ended event in the agent hub so Claude can see where Codex was last active
set -u
ORIG="${CODEX_NOTIFY_ORIG:-}"
[ -n "$ORIG" ] && [ -x "$ORIG" ] && "$ORIG" turn-ended "$@" || true
HUB="${HUB_HOME:-$HOME/agent-hub}"
[ -x "$HUB/bin/hub" ] || exit 0
JSON="${1:-}"
field() { printf '%s' "$JSON" | tr -d '\n' | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" | head -1 | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//'; }
TYPE=$(field type); CWD=$(field cwd); MSG=$(field last-assistant-message | cut -c1-200)
[ -n "$CWD" ] && export HUB_PROJECT="$CWD"
HUB_AGENT=codex "$HUB/bin/hub" log codex "${TYPE:-turn-ended}" "$MSG" >/dev/null 2>&1 || true
exit 0
