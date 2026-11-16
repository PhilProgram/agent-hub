# council

The hub improves itself. Agents file feedback while they work; a council of agents reviews it on a schedule and applies the safe changes.

```text
agents (Claude, Codex)  --hub feedback "..."-->  feedback table (bus.db)
                                                    |
scheduler, every 2h (launchd or cron) -->  council/run.sh
   pre-check: open feedback or changed `hub lint` output?  no -> exit, 0 tokens
   tier 1  analysts   Claude (sonnet) + Codex, independently, read-only -> proposals with evidence
   tier 2  chair      Claude (opus) checks evidence, merges duplicates, decides accept / queue / reject (max 5 accepts)
   tier 3  implementer Claude (sonnet), may edit only kb/ and existing skills/*/SKILL.md
   gate     paths whitelist, no deletions, no new lint errors, tests, secret scan, kb facts not cut >30%
            any failure -> the snapshot is restored
   queue    risky but valuable proposals (CLI, hooks, AGENTS.md, scripts, new skills) become feedback with
            status 'queued'; the session-start digest tells the next supervised session to handle them
   report   council/reports/<ts>.md, decisions appended to state/history.jsonl
```

## Commands

```bash
hub feedback [--area kb|skill|cli|hooks|rules|other] "what slowed you down or was missing"
hub feedback list [--all | --status queued]
hub council status      # last report, spend today, feedback counts, scheduler state
hub council run         # what the scheduler runs (skips when nothing is new)
hub council force       # run even when nothing is new
hub council dry-run     # analysts + chair only, nothing applied
hub council queue       # proposals waiting for a supervised session
```

## Limits and safety

- Daily Claude spend cap `COUNCIL_DAILY_USD` (default 6), per-call caps $1-1.50. Codex runs on the ChatGPT plan.
- Council agents run with no user settings (`--setting-sources ""`), hooks off, no MCP servers, an explicit tool allow-list, and path-scoped Edit/Write. They cannot run arbitrary shell commands, commit, push or touch anything outside the hub.
- Snapshots of kb/, skills/, AGENTS.md, bin/, hooks/ before every applied run: `council/snapshots/<ts>/` (last 20 kept).
- A rollback only undoes changes in kb/ and SKILL.md files; a change elsewhere during the run belongs to another session and is left alone (logged).
- Models: `COUNCIL_MODEL_ANALYST` / `_CHAIR` / `_IMPL`; `COUNCIL_CODEX=0` drops the Codex analyst; `COUNCIL_MAX_ACCEPT` caps unattended changes per run.

## Requirements

The `claude` CLI (logged in) and `python3`. The `codex` CLI is optional; without it the council runs with one analyst.

## Scheduler

Nothing is scheduled until you run `council/install-scheduler.sh` yourself. `COUNCIL_INTERVAL` sets the interval in seconds (default 7200).

**macOS.** The script writes `~/Library/LaunchAgents/com.agenthub.council.plist` and loads it. The job runs only while you're logged in and the Mac is awake.

```bash
launchctl bootout gui/$(id -u)/com.agenthub.council      # stop
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agenthub.council.plist   # start
```

**Linux.** There is no launchd, so the script schedules nothing. It prints a cron line for you to add with `crontab -e`:

```text
0 */2 * * * HUB_HOME=$HOME/agent-hub /bin/bash $HOME/agent-hub/council/run.sh run >> $HOME/agent-hub/council/logs/cron.log 2>&1
```

The Linux path has not been run on a Linux machine yet. Try `hub council dry-run` by hand before scheduling it.

Logs: `council/logs/council.log`, plus `council/logs/launchd.log` on macOS or `council/logs/cron.log` on Linux.
