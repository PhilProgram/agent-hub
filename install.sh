#!/usr/bin/env bash
# Install agent-hub from this checkout. Safe to re-run.
#   ./install.sh            install into ~/agent-hub (or $HUB_HOME)
# It links the CLI, starts an empty kb, links skills into each agent's skills dir,
# and PRINTS the hook / config snippets. It never edits your Claude or Codex config files.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
HUB="${HUB_HOME:-$HOME/agent-hub}"
command -v sqlite3 >/dev/null || { echo "sqlite3 is required (macOS ships it; apt install sqlite3 on Linux)"; exit 1; }

if [ "$SRC" != "$HUB" ]; then
  if [ -e "$HUB" ]; then
    echo "$HUB already exists. Clone this repo there, or set HUB_HOME to use another path."; exit 1
  fi
  echo "copying $SRC -> $HUB"
  mkdir -p "$HUB"
  cp -R "$SRC"/. "$HUB"/
  rm -rf "$HUB/.git"
fi

chmod +x "$HUB/bin/hub" "$HUB"/hooks/*.sh

# Empty knowledge base (examples/kb shows what a filled one looks like)
mkdir -p "$HUB/kb/projects" "$HUB/kb/topics"
if [ ! -f "$HUB/kb/INDEX.md" ]; then
  cat > "$HUB/kb/INDEX.md" <<'EOF'
# Knowledge base index

Facts too small for a skill. One file per project or topic, one line per fact, newest at the bottom.
Append with `hub note projects/<name> "..."` or `hub note topics/<name> "..."`; read with `hub kb <name>`.

## Projects

## Topics
EOF
fi

mkdir -p "$HOME/.local/bin"
ln -sfn "$HUB/bin/hub" "$HOME/.local/bin/hub"
echo "linked ~/.local/bin/hub (make sure ~/.local/bin is on PATH)"

"$HUB/bin/hub" sync

cat <<EOF

Next steps (copy what applies; nothing below was changed for you):

1. Claude Code: make Claude read the rules. Add this line to ~/.claude/CLAUDE.md
     @$HUB/AGENTS.md

2. Codex: point Codex at the same rules
     ln -s $HUB/AGENTS.md ~/.codex/AGENTS.md      # only if you have no ~/.codex/AGENTS.md yet

3. Claude Code hooks (optional: digest at session start, new messages on each prompt). Merge into ~/.claude/settings.json:
     "hooks": {
       "SessionStart":     [{"hooks": [{"type": "command", "command": "bash $HUB/hooks/claude-hub.sh session-start"}]}],
       "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "bash $HUB/hooks/claude-hub.sh prompt"}]}],
       "Stop":             [{"hooks": [{"type": "command", "command": "bash $HUB/hooks/claude-hub.sh stop"}]}]
     }

4. Codex activity log (optional). In ~/.codex/config.toml:
     notify = ["bash", "$HUB/hooks/codex-notify.sh"]
   If you already had a notify program, export CODEX_NOTIFY_ORIG=<its path> so it keeps running.

Try it:  hub status   |   hub kb   |   hub note topics/example "first fact"
EOF
