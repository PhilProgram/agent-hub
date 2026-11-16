---
name: agent-hub
description: How to use the shared agent library at ~/agent-hub (skills, knowledge base, message bus between Claude and Codex). Use when asked to "save this as a skill", "note this for next time", "leave a message for codex/claude", "check the hub", "what do we know about <project>", or when a task's procedure took real effort and should survive the session.
---

# agent-hub

Shared library for every agent on this machine. CLI: `~/agent-hub/bin/hub` (`hub help`).

## Save a procedure as a skill
1. `hub skill new <kebab-name>` creates `~/agent-hub/skills/<name>/SKILL.md` from the template and links it into Claude, Codex and `~/.agents/skills`.
2. Fill the sections. The `description` line decides whether the skill triggers next time, so name the feature, project and trigger phrases.
3. Put scripts in `~/agent-hub/skills/<name>/scripts/` if they are generic, or leave them in the repo and link to them if they only work there.
4. Record "Last verified" with the date and outcome.

## Save a fact
`hub note projects/<project> "fact"` or `hub note topics/<topic> "fact"`. Creates the file if needed and lists it in `kb/INDEX.md`.

## Read
In Claude Code the session-start digest already prints the current project's facts (the project is the nearest folder, cwd or above, with a `kb/projects/<name>.md`). It shows the newest facts that fit about 3,000 characters, each cut to about 220 (`HUB_DIGEST_BYTES`, `HUB_DIGEST_WIDTH`, `HUB_DIGEST_FACTS`); a fact ending in `…` was shortened, so run `hub kb <project>` when it matters. `hub kb` prints the index. `hub kb <name>` prints a project or topic file. `hub search <text>` searches every kb file and skill (including scripts) case-insensitively, and says so when nothing matches.

## Check
`hub lint` after adding or editing a skill. Errors (exit 1): name/folder mismatch, missing or multi-line description, leftover template text, a referenced script that doesn't exist, broken skill links, kb index entries with no file. Warnings: descriptions over the length budget (`HUB_DESC_MAX`, default 350), overlapping skill names, scripts living outside the hub, kb files missing from the index.
- Not flagged on purpose: aliases with `disable-model-invocation: true` (their description never loads, so it has no budget), and overlapping names when one skill mentions the other (deliberately related).
- A script that must stay outside the hub (owned by another tool) is declared in the SKILL.md body with `<!-- hub-lint: external ~/dir (reason) -->`. Lint then stops warning but still errors if a referenced file is missing.
- Avoid `: ` inside a description line; YAML may read it as a nested key.

## Feedback and the council
When the hub slowed you down or was missing something, file it: `hub feedback --area kb|skill|cli|hooks|rules|other "what happened and what would have helped"`. The council (`~/agent-hub/council`, README there) reviews open feedback when run (every 2 hours only if `council/install-scheduler.sh` was run; otherwise `hub council run` by hand): Claude and Codex analysts, an Opus chair, an implementer limited to `kb/` and existing `SKILL.md` files, and a gate that rolls back on any failure. Risky proposals become `queued` feedback; the session digest announces them. Handle them in a supervised session: `hub feedback list --status queued`, apply and test, then `hub feedback close <id> done|rejected "note"`. `hub council status` shows the last report and today's spend.

## Messages
`hub inbox <you>` / `hub post <other> "subject" "body"` / `hub ack <id>|all <you>`. `hub activity` shows recent turns and events from both agents.

## Asking the other agent (costs tokens)
`hub ask codex "question"` or `hub ask claude "question"`. Requires the `codex` or `claude` CLI on PATH. Use for a second opinion on a design or a review, not routinely.
