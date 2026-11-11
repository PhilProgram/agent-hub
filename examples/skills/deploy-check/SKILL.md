---
name: deploy-check
description: Verify a pushed feature branch deployed to its preview URL. Use when the user says "I pushed", "pushed it", "check the deploy", or "/deploy-check".
---

# deploy-check

Example skill. It shows the shape a good skill takes: a sharp trigger, a short procedure, a script, and the gotchas that cost time last time.

## When to use
- Right after a branch is pushed and CI deploys it to `https://<branch>.preview.example.com`.

## Prerequisites
- The branch name equals the preview subdomain.
- The preview sits behind basic auth: env vars `PREVIEW_USER` / `PREVIEW_PASS` (names only, never values here).

## Procedure
1. `git branch --show-current`, then build the URL.
2. Run `scripts/poll.sh <url>`. It retries 5 times, 15 s apart, until it gets HTTP 200.
3. Fetch every page the diff touched (`git diff main --name-only`) and grep for `fatal error|exception|warning:`. Expect zero hits.
4. For a change that writes data, save on the preview, reload, screenshot, then restore the original value.
5. Report: live or not, status per page, and what was not checked.

## Scripts
- `scripts/poll.sh <url>` exits 0 on HTTP 200, 1 after 5 failures.

## Gotchas
- The first poll often returns 500 while the deploy is still swapping. That is not a failure until the retries run out.
- A 200 on an admin page can be the login form. Check the page title before calling it a pass.

## Last verified
- 2026-11-11 by claude, on example-app: live, 3 pages OK, save/restore OK.
