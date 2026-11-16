# agent-hub

A shared memory for the AI coding agents on your machine (Claude Code, Codex, or anything that can run a shell).

Every agent session starts from zero. It rediscovers how your project runs, which flag matters, and which test command actually works, and then forgets it all when the session ends. agent-hub is one folder outside your repos that every agent reads and writes:

- **skills/**: procedures worth keeping (a deploy check, a test recipe, a setup sequence). Each skill is linked into every agent's skills directory, so Claude and Codex both pick it up.
- **kb/**: facts too small for a skill, one line each, per project or topic.
- **bus.db**: a tiny SQLite message bus plus an activity log, so one agent can leave a note for the other and see where it was last active.
- **bin/hub**: one bash CLI over all of it. Needs bash and `sqlite3`, nothing else.

It's plain files and a shell script. There's no server, no daemon and no API key.

## Requirements

- macOS or Linux, with bash 3.2 or newer and `sqlite3`. On Windows, run it inside WSL.
- At least one agent that can run shell commands. Claude Code and Codex work out of the box; see [Using another agent](#using-another-agent) for the rest.
- It is developed and tested on macOS. The CLI and hooks use nothing macOS-specific on purpose, but they have not been run on Linux yet: run `tests/test-hub.sh` first and open an issue if a check fails.

## Install

```bash
git clone https://github.com/PhilProgram/agent-hub.git ~/agent-hub
~/agent-hub/install.sh
```

`install.sh` links `hub` into `~/.local/bin`, creates an empty `kb/`, and links the skills into `~/.claude/skills`, `~/.codex/skills` and `~/.agents/skills`. It then **prints** the lines to add to your Claude and Codex config; it never edits those files for you.

The key step is making each agent read [`AGENTS.md`](AGENTS.md), the rules that tell agents when to read the kb, when to write a fact, and when a procedure deserves a skill:

```text
# ~/.claude/CLAUDE.md
@~/agent-hub/AGENTS.md
```

```bash
ln -s ~/agent-hub/AGENTS.md ~/.codex/AGENTS.md
```

## Setup by an agent

If you are an AI agent asked to install agent-hub for someone, follow this section. It separates what you can do on your own from what edits the owner's global agent config and needs their yes first.

**1. Check before installing**

- `command -v sqlite3` must succeed.
- If `~/agent-hub` (or `$HUB_HOME`) already exists, stop and ask. `install.sh` refuses to overwrite it; don't work around that.

**2. Install.** This step changes no config file, so it needs no further approval once the owner asked for the install:

```bash
git clone https://github.com/PhilProgram/agent-hub.git ~/agent-hub
~/agent-hub/install.sh
```

It links `hub` into `~/.local/bin`, creates an empty `kb/`, and links the skills into `~/.claude/skills`, `~/.codex/skills` and `~/.agents/skills`. A skill folder of the same name that is already there and is not a link is skipped, not replaced; report any `skip` line to the owner.

**3. Config edits: show the exact change, get a yes, then apply.** `install.sh` prints these and applies none of them. Each one affects every future session, so ask per change:

| Change | File | How to apply it |
|---|---|---|
| Rules for Claude Code | `~/.claude/CLAUDE.md` | Append the line `@~/agent-hub/AGENTS.md`. Never replace the file. |
| Rules for Codex | `~/.codex/AGENTS.md` | Symlink to `~/agent-hub/AGENTS.md` only if the file does not exist. If it does, ask the owner how to combine them. |
| Claude Code hooks (optional) | `~/.claude/settings.json` | Back the file up. Add the three commands to the `SessionStart`, `UserPromptSubmit` and `Stop` arrays, keeping every hook already there. Confirm the file still parses as JSON. |
| Codex activity log (optional) | `~/.codex/config.toml` | Set `notify`. If one is already set, keep the old program running through `CODEX_NOTIFY_ORIG`. |

**4. Leave to the owner**

- The council scheduler (`council/install-scheduler.sh`). It installs a background job that spends model tokens whenever it finds work. Give the owner the command; don't run it.
- `hub council dry-run` and `hub ask` call models and cost tokens. Ask before the first run.
- Anything that needs a login, such as authenticating the `claude` or `codex` CLI.

**5. Verify**

```bash
hub status
```

Each `links in ...` line should count every skill, and there should be no `unlinked or wrong` line.

```bash
~/agent-hub/tests/test-hub.sh
```

The tests run against a throwaway hub with a fake `HOME`, so they are safe on a live install. The last line must read `passed N, failed 0`.

If you installed the hooks, pipe a fake event through one and expect exit code 0:

```bash
echo '{"session_id":"setup","cwd":"/tmp"}' | bash ~/agent-hub/hooks/claude-hub.sh session-start
```

It prints nothing on a fresh hub, because there are no facts or messages yet. The rules and hooks only load in a new session, so tell the owner to start one.

**6. Don't**

- Don't write a password, token or key anywhere in the hub. Name the env var or keychain item.
- Don't copy `examples/kb` into `kb/`. The examples are made up; a real kb starts empty and fills as agents work.
- Don't commit `kb/` or `bus.db`. `.gitignore` keeps them out so the owner's data stays local.

**7. Report** what you installed, which config changes you applied and which you left for the owner (with the exact lines), and the output of the verify step.

## What it looks like in use

An agent finishes a fiddly task and saves what it learned:

```console
$ hub note projects/example-app "Admin date pickers render a hidden <name> input plus a visible text_<name> input; tests must fill the visible one and blur"
noted in projects/example-app.md
```

The next session, in either agent, starts on that project and reads it before exploring:

```console
$ hub kb example-app
# example-app

- Runs in docker: use `docker exec -w /app php php` for any PHP CLI call, never the host php (2026-11-02, claude)
- Schema changes go through `php command migrate`; deploy runs it automatically, so never ALTER by hand (2026-11-03, codex)
- Admin date pickers render a hidden <name> input plus a visible text_<name> input; tests must fill the visible one and blur (2026-11-11, claude)
```

When a procedure took real effort, it becomes a skill:

```console
$ hub skill new deploy-check
created ~/agent-hub/skills/deploy-check/SKILL.md (linked). Fill it in: description, procedure, scripts, gotchas, last verified.
```

The skill's `description` line is what makes it trigger next time ("Use when the user says 'I pushed'..."). See [`examples/skills/deploy-check`](examples/skills/deploy-check/SKILL.md) for a filled-in one with a script, and [`examples/kb`](examples/kb) for a filled-in knowledge base.

With the optional Claude Code hooks, each session starts with the facts for the project you're in, so the agent doesn't have to remember to look them up. The project is the nearest folder (the working directory or a parent) that has a `kb/projects/<name>.md`, so starting a session in `example-app/src/admin` still works. It prints nothing when there's nothing to say:

```text
[agent-hub]
kb facts for example-app (kb/projects/example-app.md):
- Runs in docker: use `docker exec -w /app php php` for any PHP CLI call, never the host php (2026-11-02, claude)
- Schema changes go through `php command migrate`; deploy runs it automatically, so never ALTER by hand (2026-11-03, codex)
codex last active here: 2026-11-10T20:36:33Z
```

The digest is budgeted so it can't crowd the context: the newest facts that fit about 3,000 characters, each cut to about 220 and marked `…` when shortened (`HUB_DIGEST_BYTES`, `HUB_DIGEST_WIDTH`, `HUB_DIGEST_FACTS`). `hub lint` warns when a project file has outgrown it. The digest never shows another agent's replies or activity from other projects.

Find anything across every project and skill:

```console
$ hub search "basic auth"
kb/topics/staging.md:4:- Staging sits behind basic auth; credentials are in the keychain item staging-basic-auth (2026-11-05, claude)
skills/deploy-check/SKILL.md:12:Poll the deployed URL with basic auth until it returns 200.
(2 line(s) in 2 file(s))
```

Keep the skills healthy as the library grows:

```console
$ hub lint
warn   skills/deploy-check: description is 412 chars (budget 350); it loads into every session
warn   skills/release-check and skills/release-notes look like overlapping skills (shared word 'relea'); merge them if they do the same job
error  skills/report: references ~/scripts/report.sh, which does not exist
lint: 12 skill(s), model-visible descriptions total 3410 chars; 1 error(s), 2 warning(s)
```

Two skills that mention each other are treated as deliberately related, and aliases with `disable-model-invocation: true` don't count toward the budget because their description never loads. If a skill depends on a script owned by another tool, declare it in the SKILL.md body with `<!-- hub-lint: external ~/that/dir (reason) -->`. Lint then stops warning about it, but still errors if the file goes missing.

## The hub improves itself (optional council)

Agents file feedback whenever the hub slowed them down or was missing something:

```console
$ hub feedback --area kb "projects/example-app: the digest only fits 13 of 32 facts; the deploy steps got cut"
feedback #12 recorded (kb); the council reviews open feedback
```

A council of agents reviews it on a schedule (every 2 hours by default) and applies the safe fixes itself:

1. **Analysts:** Claude and Codex, independently and read-only, each propose up to 6 changes, with evidence quoted from the files.
2. **Chair:** a stronger Claude model checks the evidence, merges duplicates, and decides accept, queue or reject. It accepts at most 5 per run.
3. **Implementer:** applies the accepted changes. It can only edit `kb/` and existing `SKILL.md` files.
4. **Gate:** checks the allowed paths, no deletions, no new lint errors, the tests, a secret scan, and that kb facts weren't cut by more than 30%. Any failure restores the snapshot.

Changes that are valuable but risky (the CLI, hooks, `AGENTS.md`, new skills) are queued instead. The next session's digest says so, and the user oversees those.

It costs nothing when there is nothing to do: a run with no new feedback and unchanged lint output exits before calling any model. Claude spend is capped per day (`COUNCIL_DAILY_USD`, default $6). The council's agents run with no user settings, hooks off, no MCP servers and an explicit tool allow-list. Details in [`council/README.md`](council/README.md).

The council needs the `claude` CLI and `python3`; Codex is an optional second analyst. `council/install-scheduler.sh` sets up a launchd job on macOS. On Linux it prints a cron line for you to add, and that path has not been run yet.

```console
$ hub council status
last report: ~/agent-hub/council/reports/20260105-140000.md
spent today: $0.84 of $6.0
feedback: done=2, queued=1
scheduler: loaded (launchd com.agenthub.council)
```

## Commands

```text
hub kb [name]                              print the index, or one project/topic file
hub note <projects|topics>/<name> <text>   append one fact (creates and indexes the file)
hub skill new <name> | hub skill list      scaffold a skill from the template / list skills
hub sync                                   (re)link every skill into each agent's skills dir
hub search <text>                          case-insensitive search across kb/ and skills/ (exit 1 when nothing matches)
hub lint                                   check skills, kb index and links (exit 1 on errors)
hub inbox <agent> [--all]                  unread messages for an agent
hub post [--from me] <to> <subject> [body] leave a message for another agent
hub ack <id>|all <agent>                   mark read
hub activity [n]                           recent events from all agents
hub digest <agent>                         the session-start block: project facts, unread messages (used by the hook)
hub ask <claude|codex> <question>          run the other agent once for a second opinion (costs tokens)
hub status                                 counts and link health
hub feedback [--area a] <text>             suggest a hub improvement (kb skill cli hooks rules other)
hub feedback list [--all|--status s]       open (or all) feedback; close <id> <done|rejected|queued> [note]
hub council run|force|dry-run|status|queue the self-improvement council
```

`HUB_HOME` moves the hub somewhere other than `~/agent-hub`. `HUB_AGENT` sets the sender name for `post` and `note`. `HUB_LINK_DIRS` replaces the list of skill folders that `sync`, `lint` and `status` use. `HUB_DIGEST_BYTES` (3000), `HUB_DIGEST_WIDTH` (220), `HUB_DIGEST_FACTS` (40) and `HUB_DESC_MAX` (350) tune the digest and lint.

Unknown options and stray arguments are errors, never silently ignored: `hub sync --dry-run` refuses instead of doing a real sync, and an unquoted `hub note projects/app two words` refuses instead of saving only "two".

`hub` itself never runs in the background. It runs once per command and exits; the hooks run it for a few milliseconds at session start, on each prompt, and at the end of each turn. The only scheduled piece is the optional council.

## Using another agent

Nothing in the kb, the bus or the CLI is tied to Claude Code or Codex. Any agent that can run a shell command can use the hub once three things are true:

1. **It reads the rules.** Point the agent's global instruction file at [`AGENTS.md`](AGENTS.md), by include, symlink or copy, whichever that agent supports.
2. **It has a name.** Export `HUB_AGENT=<short-name>` in the environment the agent runs in. That name signs its notes and addresses its messages.
3. **It can find the skills.** `hub sync` links every skill into `~/.claude/skills`, `~/.codex/skills` and `~/.agents/skills`. If your agent reads skills from somewhere else, list every folder you want, separated by colons:

```bash
export HUB_LINK_DIRS="$HOME/.claude/skills:$HOME/.my-agent/skills"
hub sync
```

`HUB_LINK_DIRS` replaces the default list, so include the defaults you still use. Set it in your shell profile so `hub sync`, `hub lint` and `hub status` all see the same list.

Two pieces are specific to Claude and Codex: the session hooks in `hooks/`, and `hub ask`, which only knows how to start the `claude` and `codex` CLIs. An agent without a session-start hook gets no automatic digest, so its rules file should tell it to run `hub digest <its-name>` at the start of a task.

## Upgrade, back up, uninstall

**Upgrade.** The install is the clone, so pull and re-run the installer, which is safe to repeat:

```bash
cd ~/agent-hub && git pull && ./install.sh
```

Your `kb/`, `bus.db` and your own skills are git-ignored, so a pull never touches them. If you installed by running `install.sh` from a different folder, the hub is a copy without `.git`; move your `kb/`, `bus.db` and skills aside, clone, and move them back.

**Back up.** `kb/`, `bus.db` and your own skills exist only on your machine. Include `~/agent-hub` in your normal backups, or keep `kb/` and your skills in a private repository of your own. Never push them to a fork of this one.

**Uninstall.** Undo each step you applied at install time:

1. Remove the `@~/agent-hub/AGENTS.md` line from `~/.claude/CLAUDE.md`, and the `~/.codex/AGENTS.md` symlink if it points at the hub.
2. Remove the three `claude-hub.sh` hooks from `~/.claude/settings.json` and the `notify` line from `~/.codex/config.toml`.
3. If you scheduled the council: `~/agent-hub/council/install-scheduler.sh --remove` on macOS, or delete the cron line on Linux.
4. Remove the skill links and the CLI link:

```bash
find ~/.claude/skills ~/.codex/skills ~/.agents/skills -maxdepth 1 -type l -lname "$HOME/agent-hub/*" -delete
```

```bash
rm ~/.local/bin/hub
```

5. Back up `kb/` and your skills if you want them, then delete `~/agent-hub`.

## Tests

```bash
tests/test-hub.sh
```

Runs every command against a throwaway hub with a fake `HOME`, so your real skills and kb are never touched. Needs only bash and sqlite3.

## Layout

```text
~/agent-hub/
  AGENTS.md          rules every agent reads
  bin/hub            the CLI
  hooks/             Claude Code session hooks, Codex notify wrapper
  skills/            your skills (git-ignored) + _TEMPLATE + the agent-hub skill that teaches agents the CLI
  kb/                your facts (created by install.sh, git-ignored)
  bus.db             messages + activity (git-ignored)
  examples/          a sample skill and a sample kb, to show the shape of a filled-in one
  tests/             test-hub.sh, runs against a throwaway hub
  council/           the self-improvement council: runner, prompts, schemas, scheduler installer
```

## Lessons from using it

- **Skills pay off more than the kb.** A skill turns a 20-minute rediscovery into one step. A kb fact saves a minute.
- **Descriptions cost tokens in every session.** Every skill description loads into every session, so keep them to one or two lines and merge near-duplicate skills.
- **Never store secrets.** Write the env var or keychain item name, not the value. `.gitignore` already keeps `kb/`, `bus.db` and your own skills out of the repo, so your own data stays local.
- **Facts go stale.** Every note is dated. Agents are told to re-check a fact before acting on it when it's old or the action is hard to undo.
- **Agent-to-agent chat is opt-in.** `hub ask` costs tokens. In practice the bus is used far less than the kb and skills.

## License

MIT
