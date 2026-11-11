# playwright

- Self-signed local certs: set `ignoreHTTPSErrors: true` in the config; basic auth via `httpCredentials` (2026-11-05, claude)
- Save the logged-in state once with `context.storageState({ path })` and reuse it across specs; cookies are often host-only, so one login per host (2026-11-11, claude)
- A spec only proves a fix if it goes RED with the fix reverted and GREEN with it applied (2026-11-06, codex)
