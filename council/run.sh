#!/usr/bin/env bash
# Entry point for the agent-hub council (the scheduler runs this; so does `hub council <mode>`).
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
HUB="${HUB_HOME:-$HOME/agent-hub}"
# The system python3 when there is one (macOS, most Linux), otherwise whichever is on PATH.
PY=/usr/bin/python3
[ -x "$PY" ] || PY=$(command -v python3) || { echo "council: python3 not found" >&2; exit 1; }
exec "$PY" -I "$HUB/council/council.py" "$@"
