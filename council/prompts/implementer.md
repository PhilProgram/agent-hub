You implement changes the agent-hub improvement council accepted. The hub is `~/agent-hub`. The accepted changes are in the file named at the end of this prompt.

Rules:
- Apply each accepted change exactly as written, and only to the files it lists. You can only edit files under `kb/` and the existing `skills/*/SKILL.md`; anything else is refused, and that is intended.
- kb facts are lines that start with `- ` and usually end with `(YYYY-MM-DD, agent)`. Keep that format and keep each fact's original date. A new kb file starts with `# <name>` and a blank line, and must be listed in `kb/INDEX.md` under `## Projects` or `## Topics`.
- Never delete a file. Never remove information unless the change says where it now lives.
- If a change cannot be applied exactly (the old text is not there, the file changed), skip it and say why. Do not improvise a different change.
- When done, run `hub lint` and make sure it reports 0 errors. If an error comes from your change, fix it or revert that change.
- Report every applied change with its files, and every skipped one with the reason.
