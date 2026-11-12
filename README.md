# agent-hub

A shared memory for the AI coding agents on your machine (Claude Code, Codex, or anything that can run a shell).

Every agent session starts from zero. It rediscovers how your project runs, which flag matters, and which test command actually works, and then forgets it all when the session ends. agent-hub is one folder outside your repos that every agent reads and writes:

- **skills/**: procedures worth keeping (a deploy check, a test recipe, a setup sequence). Each skill is linked into every agent's skills directory, so Claude and Codex both pick it up.
- **kb/**: facts too small for a skill, one line each, per project or topic.
- **bus.db**: a tiny SQLite message bus plus an activity log, so one agent can leave a note for the other and see where it was last active.
- **bin/hub**: one bash CLI over all of it. Needs bash and `sqlite3`, nothing else.

It's plain files and a shell script. There's no server, no daemon and no API key.

## Install

```bash
git clone <this repo> ~/agent-hub
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

Long project files are capped at the newest 40 facts (`HUB_DIGEST_FACTS`). The digest never shows another agent's replies or activity from other projects.

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
warn   skills/grill-me and skills/grilling look like overlapping skills (shared word 'grill'); merge them if they do the same job
error  skills/report: references ~/scripts/report.sh, which does not exist
lint: 12 skill(s), model-visible descriptions total 3410 chars; 1 error(s), 2 warning(s)
```

Two skills that mention each other are treated as deliberately related, and aliases with `disable-model-invocation: true` don't count toward the budget because their description never loads. If a skill depends on a script owned by another tool, declare it in the SKILL.md body with `<!-- hub-lint: external ~/that/dir (reason) -->`. Lint then stops warning about it, but still errors if the file goes missing.

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
```

`HUB_HOME` moves the hub somewhere other than `~/agent-hub`. `HUB_AGENT` sets the sender name for `post` and `note`. `HUB_DIGEST_FACTS` (default 40) and `HUB_DESC_MAX` (default 350) tune the digest and lint.

Unknown options and stray arguments are errors, never silently ignored: `hub sync --dry-run` refuses instead of doing a real sync, and an unquoted `hub note projects/app two words` refuses instead of saving only "two".

Nothing runs in the background. `hub` runs once per command and exits; the hooks run it for a few milliseconds at session start, on each prompt, and at the end of each turn.

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
  skills/            your skills (+ _TEMPLATE, + the agent-hub skill that teaches agents the CLI)
  kb/                your facts (created by install.sh, git-ignored)
  bus.db             messages + activity (git-ignored)
  examples/          a sample skill and a sample kb to copy from
  tests/             test-hub.sh, runs against a throwaway hub
```

## Lessons from using it

- **Skills pay off more than the kb.** A skill turns a 20-minute rediscovery into one step. A kb fact saves a minute.
- **Descriptions cost tokens in every session.** Every skill description loads into every session, so keep them to one or two lines and merge near-duplicate skills.
- **Never store secrets.** Write the env var or keychain item name, not the value. `.gitignore` already keeps `kb/` and `bus.db` out of the repo, so your own data stays local.
- **Facts go stale.** Every note is dated. Agents are told to re-check a fact before acting on it when it's old or the action is hard to undo.
- **Agent-to-agent chat is opt-in.** `hub ask` costs tokens. In practice the bus is used far less than the kb and skills.

## License

MIT
