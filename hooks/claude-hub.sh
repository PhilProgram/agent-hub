#!/usr/bin/env bash
# Claude Code hooks for the agent hub (wired in ~/.claude/settings.json).
#   claude-hub.sh session-start   SessionStart: print the hub digest (this project's kb facts, unread inbox, other agent's last time here)
#   claude-hub.sh prompt          UserPromptSubmit: print only messages that arrived since this hook last ran for this session
#   claude-hub.sh stop            Stop: log a turn-ended event so the other agent can see where Claude was last active
# stdout of SessionStart/UserPromptSubmit is added to the model's context, so it stays empty when there is nothing new.
# Fails open: any error means no output and exit 0.
set -u
HUB="${HUB_HOME:-$HOME/agent-hub}"
BIN="$HUB/bin/hub"
[ -x "$BIN" ] || exit 0
MODE="${1:-}"
INPUT=$(cat 2>/dev/null | tr -d '\n')
field() { printf '%s' "$INPUT" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'; }
SID=$(field session_id); case "$SID" in *[!A-Za-z0-9_-]*) SID="" ;; esac
CWD=$(field cwd); [ -n "$CWD" ] && export HUB_PROJECT="$CWD"
export HUB_AGENT=claude
MARK="${TMPDIR:-/tmp}/claude-hub-lastseen-${SID:-nosid}"

case "$MODE" in
  session-start)
    "$BIN" digest claude 2>/dev/null || true
    "$BIN" log claude session-start "${CWD:-}" 2>/dev/null || true
    sqlite3 -batch "$HUB/bus.db" "SELECT coalesce(max(id),0) FROM messages" > "$MARK" 2>/dev/null || true
    ;;
  prompt)
    LAST=$(cat "$MARK" 2>/dev/null || echo 0); case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
    NEW=$(sqlite3 -batch "$HUB/bus.db" "SELECT '#'||id||'  from '||from_agent||coalesce('  ['||project||']','')||'  '||subject||char(10)||coalesce('    '||replace(body,char(10),char(10)||'    '),'') FROM messages WHERE to_agent='claude' AND read_at IS NULL AND id>$LAST ORDER BY id" 2>/dev/null || true)
    if [ -n "$NEW" ]; then
      printf '[agent-hub] new message(s) for claude (ack with: hub ack <id>):\n%s\n' "$NEW"
      sqlite3 -batch "$HUB/bus.db" "SELECT coalesce(max(id),0) FROM messages" > "$MARK" 2>/dev/null || true
    fi
    ;;
  stop)
    # Keep $MARK: it records which messages this session has already been shown.
    # (Deleting it here made every unread message reappear on every later turn.)
    "$BIN" log claude turn-ended "${CWD:-}" 2>/dev/null || true
    ;;
esac
exit 0
