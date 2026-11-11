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
`hub kb` prints the index. `hub kb <name>` prints a project or topic file.

## Messages
`hub inbox <you>` / `hub post <other> "subject" "body"` / `hub ack <id>|all <you>`. `hub activity` shows recent turns and events from both agents.

## Asking the other agent (costs tokens)
`hub ask codex "question"` or `hub ask claude "question"`. Requires the `codex` or `claude` CLI on PATH. Use for a second opinion on a design or a review, not routinely.
