# Agent hub rules (read by Claude Code and Codex, every project)

The shared library is `~/agent-hub`. Its CLI is `hub` (linked at `~/.local/bin/hub`; if `hub` is not found, call `~/agent-hub/bin/hub`).
Your agent name is `claude` in Claude Code and `codex` in Codex.

## At the start of a task
- Run `hub kb` and open any project or topic file that matches the task before exploring code. If a skill covers the task, use it instead of rediscovering the procedure.

## While working
- When you learn a fact the next session would otherwise rediscover (a flag, a gotcha, where something lives, how to run something, which server runs what), append it: `hub note projects/<project> "..."` or `hub note topics/<topic> "..."`. One line, concrete, no narrative.
- Treat kb facts as "true when written": verify a server, version or path fact before acting on it if the note is old or the action is hard to undo.
- Never write secrets (passwords, tokens, keys) into the kb or a skill. Name the env var or keychain item instead.

## Before finishing a task
- If you worked out a reusable procedure that took real effort (a test script and how to run it, a setup sequence, a debugging recipe, a deploy/verify flow), save it as a skill: `hub skill new <name>`, then fill `~/agent-hub/skills/<name>/SKILL.md` and put the script next to it. Keep the frontmatter `description` precise: it is what triggers the skill next time.
- Scripts that only make sense inside one repo stay in that repo; the skill then says where they are and how to run them.
- Do not write session narrative into the hub. Facts and procedures only.

## Second opinions
- `hub ask <agent> "..."` runs the other agent as a subprocess and roughly doubles the tokens for that exchange. Use it when a decision has real downside and a second view could change what you do: a platform or version pin, a schema or data migration, a design with several defensible shapes. Skip it for routine edits.

## Costs
- Every skill's description is loaded into every session. Keep descriptions to one or two lines and merge near-duplicate skills.
- Only check the message bus (`hub inbox`) when the session-start digest says there is something unread.
