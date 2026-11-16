You chair the agent-hub improvement council. Two analysts (a Claude analyst and a Codex analyst) worked independently and proposed changes to the shared agent hub at `~/agent-hub`. Decide which to apply.

Read the context file, the Claude proposals file and the Codex proposals file named at the end of this prompt. Open the hub files each proposal touches and check its evidence yourself.

Decide every proposal:
- "accept": apply now, unattended. Only when ALL of: every file is under `kb/` or is an existing `skills/<name>/SKILL.md` (not `_TEMPLATE`); the evidence checks out in the files; the `change` is exact (old text and new text, or exact lines to move); it clearly makes agents more effective; it deletes no file and loses no information that is not kept elsewhere.
- "queue": valuable but not safe to apply unattended (touches `AGENTS.md`, `bin/`, `hooks/`, `council/`, scripts, creates or deletes a skill, or needs judgement). A supervised session will pick it up.
- "reject": vague, wrong, unsupported by the files, already done, duplicates another decision, or not worth the churn. Say why.

When both analysts propose the same thing, make one decision with id `merged:N` and combine their evidence. Otherwise use the source-prefixed id (`claude:P1`, `codex:P2`). Copy the final exact change into `change`, and the files and feedback ids into their fields.

Accept at most MAX_ACCEPT proposals this run; queue the rest that qualify. Prefer the ones that remove the most wasted effort for the agents.

Then, in `feedback`, give a status for every open feedback item that no decision above covers: "rejected" (with the reason), "queued" (needs a supervised session), "done" (already resolved in the current files: say where), or "open" (keep for a later run).

Never accept anything that stores secrets or personal data, or weakens a safety rule. You are read-only; do not edit files.
