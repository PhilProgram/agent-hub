#!/usr/bin/env bash
# Install (or remove) the launchd job that runs the council every 2 hours while you're logged in and awake.
#   council/install-scheduler.sh            install + load
#   council/install-scheduler.sh --remove   unload + delete
# macOS only. Anywhere else it schedules nothing and prints the cron line to add yourself (exit 1).
set -euo pipefail
HUB="${HUB_HOME:-$HOME/agent-hub}"
LABEL=com.agenthub.council
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL="${COUNCIL_INTERVAL:-7200}"
case "$INTERVAL" in ''|*[!0-9]*) echo "COUNCIL_INTERVAL must be seconds" >&2; exit 1 ;; esac

if [ "$(uname -s)" != "Darwin" ]; then
  if [ "${1:-}" = "--remove" ]; then
    echo "no launchd on this system: delete the council/run.sh line with 'crontab -e'"; exit 0
  fi
  h=$((INTERVAL / 3600)); m=$((INTERVAL / 60)); when="0 */2 * * *"
  if [ $((INTERVAL % 3600)) -eq 0 ] && [ "$h" -ge 1 ] && [ "$h" -le 23 ]; then when="0 */$h * * *"
  elif [ $((INTERVAL % 60)) -eq 0 ] && [ "$m" -ge 1 ] && [ "$m" -le 59 ]; then when="*/$m * * * *"
  fi
  mkdir -p "$HUB/council/logs"
  cat <<EOF
No launchd on this system, so nothing was scheduled. To run the council from cron, add this line with 'crontab -e':

  $when HUB_HOME=$HUB /bin/bash $HUB/council/run.sh run >> $HUB/council/logs/cron.log 2>&1

'hub council status' reports "scheduled (crontab)" once the line is in your crontab.
EOF
  exit 1
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then rm -f "$PLIST"; echo "removed $LABEL"; exit 0; fi

mkdir -p "$HOME/Library/LaunchAgents" "$HUB/council/logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$HUB/council/run.sh</string><string>run</string></array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key><string>$HOME</string>
    <key>HUB_HOME</key><string>$HUB</string>
  </dict>
  <key>StandardOutPath</key><string>$HUB/council/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$HUB/council/logs/launchd.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "loaded $LABEL: every ${INTERVAL}s while logged in and awake (log: $HUB/council/logs/launchd.log)"
