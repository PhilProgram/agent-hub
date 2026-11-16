#!/usr/bin/env python3
"""agent-hub improvement council.

Tiers:  analysts (Claude + Codex, independent, read-only)  ->  chair (Claude, decides)  ->  implementer (Claude,
        may edit only kb/ and existing skills/*/SKILL.md)  ->  gate (path whitelist, hub lint, tests, secret scan,
        fact-loss check; any failure restores the snapshot).
Risky proposals are queued as feedback (status 'queued'); the session-start digest tells the next supervised
agent session about them.

Usage: council.py run | force | dry-run | status | queue
  run      skip (0 tokens) unless there is open feedback or `hub lint` output changed since the last run
  force    run even if nothing changed
  dry-run  analysts + chair only; no edits, no feedback updates
"""
import datetime as dt
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HUB = Path(os.environ.get("HUB_HOME", Path.home() / "agent-hub"))
C = HUB / "council"
STATE, LOGS, REPORTS, SNAPS, RUNS = (C / d for d in ("state", "logs", "reports", "snapshots", "runs"))
HUBBIN = HUB / "bin" / "hub"
TESTS = Path(os.environ.get("COUNCIL_TESTS") or HUB / "tests" / "test-hub.sh")

DAILY_USD = float(os.environ.get("COUNCIL_DAILY_USD", "6"))
MAX_ACCEPT = int(os.environ.get("COUNCIL_MAX_ACCEPT", "5"))
MODEL_ANALYST = os.environ.get("COUNCIL_MODEL_ANALYST", "sonnet")
MODEL_CHAIR = os.environ.get("COUNCIL_MODEL_CHAIR", "opus")
MODEL_IMPL = os.environ.get("COUNCIL_MODEL_IMPL", "sonnet")
USE_CODEX = os.environ.get("COUNCIL_CODEX", "1") != "0"
TIMEOUT = 20 * 60
KEEP = 20  # snapshots / run dirs kept

SECRET_RE = re.compile(r"(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|"
                       r"-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*['\"]?[A-Za-z0-9/+_\-]{8,})", re.I)
TRACKED = ["kb", "skills", "AGENTS.md", "bin", "hooks"]


def now():
    return dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def log(msg):
    LOGS.mkdir(parents=True, exist_ok=True)
    line = f"{now()} {msg}"
    print(line, flush=True)
    with open(LOGS / "council.log", "a") as f:
        f.write(line + "\n")


def sh(args, env=None, cwd=None, timeout=300):
    e = dict(os.environ, **(env or {}))
    p = subprocess.run(args, capture_output=True, text=True, env=e, cwd=cwd, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def hub(*args, env=None):
    rc, out, err = sh([str(HUBBIN), *args], env=dict({"HUB_AGENT": "council"}, **(env or {})), cwd=str(HUB))
    if rc != 0 and args and args[0] in ("feedback", "log"):
        log(f"hub {args[0]} failed (rc={rc}): {(err or out).strip()[:300]}")
    return rc, out, err


# ---------- spend + lock ----------
def spend_file():
    return STATE / f"spend-{dt.date.today().isoformat()}.json"


def spent_today():
    try:
        return float(json.loads(spend_file().read_text())["usd"])
    except Exception:
        return 0.0


def add_spend(usd):
    STATE.mkdir(parents=True, exist_ok=True)
    spend_file().write_text(json.dumps({"usd": round(spent_today() + (usd or 0), 4)}))


def acquire_lock():
    lock = STATE / "lock"
    STATE.mkdir(parents=True, exist_ok=True)
    try:
        lock.mkdir()
    except FileExistsError:
        if time.time() - lock.stat().st_mtime > 3 * 3600:
            log("removing stale lock")
            shutil.rmtree(lock, ignore_errors=True)
            lock.mkdir()
        else:
            log("another council run holds the lock; exiting")
            sys.exit(0)
    return lock


# ---------- agents ----------
NO_HOOKS = json.dumps({"disableAllHooks": True})


def claude(prompt, model, budget, tools, schema_file, label, run_dir):
    remaining = DAILY_USD - spent_today()
    if remaining <= 0.05:
        raise RuntimeError(f"daily budget ${DAILY_USD} used up")
    budget = min(budget, remaining)
    schema = json.dumps(json.loads(Path(schema_file).read_text()))
    cmd = ["claude", "-p", prompt, "--model", model, "--max-budget-usd", f"{budget:.2f}",
           "--strict-mcp-config", "--setting-sources", "", "--settings", NO_HOOKS,
           "--permission-mode", "dontAsk", "--output-format", "json", "--json-schema", schema,
           "--allowedTools", *tools]
    t0 = time.time()
    rc, out, err = sh(cmd, cwd=str(HUB), timeout=TIMEOUT, env={"HUB_AGENT": "council"})
    (run_dir / f"{label}.raw.json").write_text(out or err)
    try:
        d = json.loads(out)
    except Exception:
        raise RuntimeError(f"{label}: no JSON from claude (rc={rc}): {(err or out)[:300]}")
    cost = d.get("total_cost_usd") or 0
    add_spend(cost)
    log(f"{label}: {model} {time.time()-t0:.0f}s ${cost:.3f} turns={d.get('num_turns')} error={d.get('is_error')}")
    so = d.get("structured_output")
    if d.get("is_error") or so is None:
        raise RuntimeError(f"{label}: failed ({d.get('subtype')}): {str(d.get('result'))[:300]}")
    (run_dir / f"{label}.json").write_text(json.dumps(so, indent=2))
    return so, cost


def codex(prompt, schema_file, label, run_dir):
    out = run_dir / f"{label}.json"
    t0 = time.time()
    rc, o, e = sh(["codex", "exec", "-s", "read-only", "--skip-git-repo-check", "-C", str(HUB),
                   "--output-schema", str(schema_file), "-o", str(out), prompt], timeout=TIMEOUT)
    (run_dir / f"{label}.log").write_text((o or "") + "\n" + (e or ""))
    if rc != 0 or not out.exists():
        raise RuntimeError(f"{label}: codex rc={rc}: {(e or o)[-300:]}")
    data = json.loads(out.read_text())
    log(f"{label}: codex {time.time()-t0:.0f}s proposals={len(data.get('proposals', []))}")
    return data


# ---------- snapshot + gate ----------
def files_under(root):
    out = {}
    for rel in TRACKED:
        p = root / rel
        if p.is_file():
            out[rel] = p
        elif p.is_dir():
            for f in p.rglob("*"):
                if f.is_file() and "__pycache__" not in f.parts and f.name != ".DS_Store":
                    out[str(f.relative_to(root))] = f
    return out


def snapshot(ts):
    dst = SNAPS / ts
    dst.mkdir(parents=True)
    for rel, src in files_under(HUB).items():
        t = dst / rel
        t.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, t)
    for old in sorted(SNAPS.iterdir())[:-KEEP]:
        shutil.rmtree(old, ignore_errors=True)
    return dst


def changes(snap):
    before, after = files_under(snap), files_under(HUB)
    added = sorted(set(after) - set(before))
    deleted = sorted(set(before) - set(after))
    modified = sorted(r for r in set(before) & set(after) if before[r].read_bytes() != after[r].read_bytes())
    return added, modified, deleted


def allowed(rel, snap):
    if rel.startswith("kb/") and rel.endswith(".md"):
        return True
    m = re.fullmatch(r"skills/([^/]+)/SKILL\.md", rel)
    return bool(m and m.group(1) != "_TEMPLATE" and (snap / rel).exists())


def fact_count(root):
    return sum(1 for f in (root / "kb").rglob("*.md") for line in f.read_text(errors="replace").splitlines() if line.startswith("- "))


def lint_errors():
    _, out, _ = hub("lint")
    return {l for l in out.splitlines() if l.startswith("error")}


def gate(snap, base_errors):
    added, modified, deleted = changes(snap)
    problems = []
    if deleted:
        problems.append(f"deleted files: {deleted}")
    bad = [r for r in added + modified if not allowed(r, snap)]
    if bad:
        problems.append(f"changed outside kb/ and existing SKILL.md: {bad}")
    for r in added + modified:
        old = (snap / r).read_text(errors="replace").splitlines() if (snap / r).exists() else []
        new = (HUB / r).read_text(errors="replace").splitlines()
        plus = [l[1:] for l in difflib.unified_diff(old, new, lineterm="", n=0) if l.startswith("+") and not l.startswith("+++")]
        hits = [l for l in plus if SECRET_RE.search(l)]
        if hits:
            problems.append(f"possible secret added in {r}")
    fb, fa = fact_count(snap), fact_count(HUB)
    if fb and fa < 0.7 * fb:
        problems.append(f"kb facts dropped from {fb} to {fa}")
    new_errors = lint_errors() - base_errors  # only errors this change introduced
    if new_errors:
        problems.append("new hub lint errors:\n" + "\n".join(sorted(new_errors)))
    if TESTS.exists():
        rc, out, err = sh(["bash", str(TESTS), str(HUB)], timeout=600)
        if rc != 0:
            problems.append("tests failed: " + (out.strip().splitlines() or ["?"])[-1])
    return problems, added, modified


def restore(snap, added, modified):
    """Undo changes in the paths the implementer can write (kb/, existing SKILL.md). A change elsewhere cannot
    come from the implementer (its permissions forbid it), so it is another session's work: report, don't revert."""
    untouched = []
    for r in added:
        if allowed(r, snap):
            (HUB / r).unlink(missing_ok=True)
        else:
            untouched.append(r)
    for r in modified:
        if allowed(r, snap):
            shutil.copy2(snap / r, HUB / r)
        else:
            untouched.append(r)
    if untouched:
        log(f"left alone (changed outside the implementer's paths, likely another session): {untouched}")
    return untouched


# ---------- context ----------
def build_context(run_dir):
    parts = []
    _, fb, _ = hub("feedback", "list")
    parts.append("## Open feedback from agents\n```\n" + fb.strip() + "\n```")
    _, lint, _ = hub("lint")
    parts.append("## hub lint\n```\n" + lint.strip() + "\n```")
    digests = []
    for f in sorted((HUB / "kb" / "projects").glob("*.md")):
        _, d, _ = hub("digest", "claude", env={"HUB_PROJECT": f"/council/{f.stem}"})
        head = d.splitlines()[1] if len(d.splitlines()) > 1 else "(no facts)"
        digests.append(f"{f.stem}: {head}")
    parts.append("## Session digest per project (what agents see at session start)\n```\n" + "\n".join(digests) + "\n```")
    _, sk, _ = hub("skill", "list")
    parts.append("## Skills\n```\n" + sk.strip() + "\n```")
    _, st, _ = hub("status")
    parts.append("## hub status\n```\n" + st.strip() + "\n```")
    parts.append("## AGENTS.md\n```\n" + (HUB / "AGENTS.md").read_text() + "\n```")
    hist = STATE / "history.jsonl"
    if hist.exists():
        rows = [json.loads(l) for l in hist.read_text().splitlines()[-40:] if l.strip()]
        parts.append("## Earlier council decisions (do not repeat rejected ones without new evidence)\n" +
                     "\n".join(f"- {r['ts'][:10]} {r['decision']}: {r['title']} ({r['reason'][:160]})" for r in rows))
    ctx = run_dir / "context.md"
    ctx.write_text("# Council context " + now() + "\n\n" + "\n\n".join(parts) + "\n")
    return ctx, lint


def lint_sha(lint):
    return hashlib.sha1(lint.encode()).hexdigest()


def open_feedback_count():
    rc, out, _ = sh(["sqlite3", "-batch", str(HUB / "bus.db"), "SELECT count(*) FROM feedback WHERE status='open'"])
    return int(out.strip() or 0) if rc == 0 else 0


# ---------- run ----------
def run(mode):
    lock = acquire_lock()
    try:
        _run(mode)
    finally:
        shutil.rmtree(lock, ignore_errors=True)


def _run(mode):
    ts = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    _, lint, _ = hub("lint")
    last = (STATE / "last-lint.sha").read_text().strip() if (STATE / "last-lint.sha").exists() else ""
    nopen = open_feedback_count()
    if mode == "run" and nopen == 0 and lint_sha(lint) == last:
        log("nothing new (0 open feedback, lint unchanged): skipped, 0 tokens")
        return
    if spent_today() >= DAILY_USD:
        log(f"daily budget ${DAILY_USD} reached (${spent_today():.2f}); skipped")
        return
    run_dir = RUNS / ts
    run_dir.mkdir(parents=True)
    for old in sorted(RUNS.iterdir())[:-KEEP]:
        shutil.rmtree(old, ignore_errors=True)
    log(f"run {ts} mode={mode} open_feedback={nopen}")
    ctx, lint = build_context(run_dir)
    report = [f"# Council run {ts} ({mode})", "", f"Open feedback: {nopen}. Context: `{ctx}`", ""]
    cost = 0.0

    # tier 1: analysts in parallel (codex in background while claude works)
    prompt_a = (C / "prompts" / "analyst.md").read_text() + f"\n\nContext file: {ctx}\n"
    proposals = {}
    cproc = None
    if USE_CODEX and shutil.which("codex"):
        cout = run_dir / "codex-analyst.json"
        cproc = subprocess.Popen(["codex", "exec", "-s", "read-only", "--skip-git-repo-check", "-C", str(HUB),
                                  "--output-schema", str(C / "schemas" / "proposals.json"), "-o", str(cout), prompt_a],
                                 stdout=open(run_dir / "codex-analyst.log", "w"), stderr=subprocess.STDOUT)
    ro_tools = ["Read", "Grep", "Glob", "Bash(hub kb:*)", "Bash(hub search:*)", "Bash(hub lint)",
                "Bash(hub skill list)", "Bash(hub feedback list:*)", "Bash(hub status)"]
    try:
        so, c = claude(prompt_a, MODEL_ANALYST, 1.00, ro_tools, C / "schemas" / "proposals.json", "claude-analyst", run_dir)
        proposals["claude"] = so.get("proposals", [])
        cost += c
    except Exception as e:
        log(f"claude analyst failed: {e}")
        report.append(f"Claude analyst failed: {e}")
    if cproc:
        try:
            cproc.wait(timeout=TIMEOUT)
            proposals["codex"] = json.loads((run_dir / "codex-analyst.json").read_text()).get("proposals", [])
            log(f"codex-analyst: proposals={len(proposals['codex'])}")
        except Exception as e:
            cproc.kill()
            log(f"codex analyst failed: {e}")
            report.append(f"Codex analyst failed: {e}")
    nprop = sum(len(v) for v in proposals.values())
    report += ["## Proposals", ""] + [f"- **{src}:{p['id']}** [{p['area']}, {p['risk']}] {p['title']}" for src, ps in proposals.items() for p in ps] + [""]
    if nprop == 0 and nopen == 0:
        log("no proposals and no open feedback; done")
        finish(ts, report, lint, cost)
        return

    # tier 2: chair
    for src, ps in proposals.items():
        (run_dir / f"proposals-{src}.json").write_text(json.dumps(ps, indent=2))
    prompt_c = (C / "prompts" / "chair.md").read_text().replace("MAX_ACCEPT", str(MAX_ACCEPT)) + (
        f"\n\nContext file: {ctx}\nClaude proposals: {run_dir / 'proposals-claude.json'}\n"
        f"Codex proposals: {run_dir / 'proposals-codex.json'}\n(a missing file means that analyst produced nothing)\n")
    try:
        dec, c = claude(prompt_c, MODEL_CHAIR, 1.50, ["Read", "Grep", "Glob", "Bash(hub kb:*)", "Bash(hub search:*)",
                                                      "Bash(hub feedback list:*)"], C / "schemas" / "decisions.json", "chair", run_dir)
        cost += c
    except Exception as e:
        log(f"chair failed: {e}")
        report.append(f"Chair failed: {e}")
        finish(ts, report, lint, cost)
        return
    accepted = [d for d in dec["decisions"] if d["decision"] == "accept"][:MAX_ACCEPT]
    report += ["## Decisions", "", dec.get("summary", ""), ""] + [
        f"- **{d['decision']}** {d['proposal_id']}: {d['title']} ({d['reason']})" for d in dec["decisions"]] + [""]
    history(ts, dec["decisions"])

    applied_ok = False
    if mode == "dry-run":
        report.append("Dry run: nothing applied, no feedback updated.")
        finish(ts, report, lint, cost)
        return

    # tier 3: implementer + gate
    if accepted:
        snap = snapshot(ts)
        base_errors = lint_errors()
        acc_file = run_dir / "accepted.json"
        acc_file.write_text(json.dumps(accepted, indent=2))
        prompt_i = (C / "prompts" / "implementer.md").read_text() + f"\n\nAccepted changes: {acc_file}\n"
        kb_abs, sk_abs = "//" + str(HUB / "kb").lstrip("/") + "/**", "//" + str(HUB / "skills").lstrip("/") + "/*/SKILL.md"
        tools = ["Read", "Grep", "Glob", f"Edit({kb_abs})", f"Write({kb_abs})", f"Edit({sk_abs})", "Bash(hub lint)", "Bash(hub kb:*)"]
        try:
            res, c = claude(prompt_i, MODEL_IMPL, 1.50, tools, C / "schemas" / "applied.json", "implementer", run_dir)
            cost += c
        except Exception as e:
            res = {"applied": [], "skipped": []}
            log(f"implementer failed: {e}")
            report.append(f"Implementer failed: {e}")
        problems, added, modified = gate(snap, base_errors)
        if problems:
            restore(snap, added, modified)
            log("gate FAILED, restored snapshot: " + " | ".join(problems))
            report += ["## Gate: FAILED, all changes rolled back", ""] + [f"- {p}" for p in problems] + [""]
        else:
            applied_ok = True
            report += ["## Applied (gate passed: paths, lint, tests, secrets, fact count)", ""] + [
                f"- {a['proposal_id']}: {a['summary']} ({', '.join(a['files'])})" for a in res["applied"]] + [
                f"- skipped {s['proposal_id']}: {s['reason']}" for s in res["skipped"]] + [
                "", f"Files changed: {', '.join(added + modified) or 'none'}. Snapshot: `{snap}`", ""]
            done_ids = {a["proposal_id"] for a in res["applied"]}
            for d in accepted:
                if d["proposal_id"] in done_ids:
                    for fid in d["feedback_ids"]:
                        hub("feedback", "close", str(fid), "done", f"council {ts}: {d['title']}")

    # queued proposals become queued feedback for a supervised session
    for d in dec["decisions"]:
        if d["decision"] == "queue":
            if d["feedback_ids"]:
                for fid in d["feedback_ids"]:
                    hub("feedback", "close", str(fid), "queued", f"council {ts}: {d['title']} :: {d['change'][:600]}")
            else:
                rc, out, _ = hub("feedback", "--area", d["area"], f"[council {ts}] {d['title']} :: {d['change'][:1200]} (files: {', '.join(d['files'])})")
                m = re.search(r"#(\d+)", out)
                if m:
                    hub("feedback", "close", m.group(1), "queued", f"council {ts}: proposed, needs a supervised session")
        elif d["decision"] == "reject":
            for fid in d["feedback_ids"]:
                hub("feedback", "close", str(fid), "rejected", f"council {ts}: {d['reason'][:400]}")
    for f in dec.get("feedback", []):
        if f["status"] != "open":
            hub("feedback", "close", str(f["id"]), f["status"], f"council {ts}: {f['resolution'][:400]}")
    finish(ts, report, lint if not applied_ok else hub("lint")[1], cost)


def history(ts, decisions):
    with open(STATE / "history.jsonl", "a") as f:
        for d in decisions:
            f.write(json.dumps({"ts": ts, "decision": d["decision"], "title": d["title"], "reason": d["reason"]}) + "\n")


def finish(ts, report, lint, cost):
    report += [f"Cost this run: ${cost:.3f} (Claude; Codex runs on the ChatGPT plan). Spent today: ${spent_today():.2f} of ${DAILY_USD}."]
    REPORTS.mkdir(parents=True, exist_ok=True)
    (REPORTS / f"{ts}.md").write_text("\n".join(report) + "\n")
    (STATE / "last-lint.sha").write_text(lint_sha(lint))
    hub("log", "council", "run", f"report council/reports/{ts}.md cost ${cost:.2f}")
    log(f"report: {REPORTS / (ts + '.md')}")


def status():
    rs = sorted(REPORTS.glob("*.md"))
    print(f"council: {C}")
    print(f"last report: {rs[-1] if rs else 'none'}")
    print(f"spent today: ${spent_today():.2f} of ${DAILY_USD}")
    _, o, _ = sh(["sqlite3", "-batch", str(HUB / "bus.db"), "SELECT status||'='||count(*) FROM feedback GROUP BY status"])
    print("feedback: " + (", ".join(o.split()) or "none"))
    if sys.platform == "darwin":
        rc, _, _ = sh(["launchctl", "print", f"gui/{os.getuid()}/com.agenthub.council"])
        print("scheduler: " + ("loaded (launchd com.agenthub.council)" if rc == 0 else "not loaded"))
    else:  # no launchd: look for the cron line install-scheduler.sh prints
        tab = sh(["crontab", "-l"])[1] if shutil.which("crontab") else ""
        on = any("council/run.sh" in ln and not ln.lstrip().startswith("#") for ln in tab.splitlines())
        print("scheduler: " + ("scheduled (crontab)" if on else "not scheduled (council/install-scheduler.sh prints the cron line)"))
    lg = LOGS / "council.log"
    if lg.exists():
        print("recent log:\n  " + "\n  ".join(lg.read_text().splitlines()[-5:]))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "run"
    if mode in ("run", "force", "dry-run"):
        run(mode)
    elif mode == "status":
        status()
    elif mode == "queue":
        os.execv(str(HUBBIN), [str(HUBBIN), "feedback", "list", "--status", "queued"])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
