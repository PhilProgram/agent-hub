#!/usr/bin/env bash
# Throwaway-hub tests for bin/hub + hooks/claude-hub.sh. Fake HOME so nothing touches real skill dirs.
# usage: tests/test-hub.sh [hub source dir]   (defaults to this checkout; exit 0 = all passed)
set -u
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
T=$(mktemp -d "${TMPDIR:-/tmp}/hubtest.XXXX")
export HOME="$T/home" HUB_HOME="$T/hub" TMPDIR="$T/tmp/"
unset HUB_LINK_DIRS HUB_AGENT HUB_PROJECT
mkdir -p "$HOME" "$TMPDIR" "$HUB_HOME/kb/projects" "$HUB_HOME/kb/topics" "$HUB_HOME/skills"
cp -R "$SRC/bin" "$SRC/hooks" "$HUB_HOME/"
cp -R "$SRC/skills/_TEMPLATE" "$HUB_HOME/skills/"
printf '# Index\n\n## Projects\n\n## Topics\n' > "$HUB_HOME/kb/INDEX.md"
H="$HUB_HOME/bin/hub"; HOOK="$HUB_HOME/hooks/claude-hub.sh"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "PASS $*"; }
bad()  { fail=$((fail+1)); echo "FAIL $*"; }
expect_rc() { local want=$1 label=$2; shift 2; local out rc; out=$("$@" 2>&1); rc=$?; [ "$rc" = "$want" ] && ok "$label (rc=$rc)" || bad "$label: want rc=$want got $rc: $out"; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1: missing '$3' in: $2" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1: unexpected '$3' in: $2" ;; *) ok "$1" ;; esac; }

# --- 3: unknown options / stray args are rejected
expect_rc 1 "sync --dry-run rejected" "$H" sync --dry-run
expect_rc 1 "status extra arg rejected" "$H" status foo
expect_rc 1 "inbox bad option rejected" "$H" inbox claude --bogus
expect_rc 1 "unquoted note rejected" "$H" note projects/app two words
expect_rc 1 "skill new -x rejected" "$H" skill new --dry-run
expect_rc 1 "activity non-number rejected" "$H" activity abc
expect_rc 1 "unknown command rejected" "$H" frobnicate
expect_rc 1 "note bad name rejected" "$H" note "projects/../x" "fact"
expect_rc 0 "sync with no args works" "$H" sync
expect_rc 0 "inbox --all still works" "$H" inbox claude --all

# --- 4: digest prints project facts, finds project from a subfolder, caps long files
HUB_AGENT=claude "$H" note projects/app "first fact" >/dev/null
HUB_AGENT=codex  "$H" note projects/app "second fact" >/dev/null
mkdir -p "$T/work/app/src/deep"
d=$(HUB_PROJECT="$T/work/app/src/deep" "$H" digest claude)
has "digest shows facts" "$d" "- first fact"
has "digest shows second fact" "$d" "- second fact"
has "digest names project from subfolder" "$d" "kb facts for app"
for i in $(seq 1 50); do "$H" note projects/big "fact $i" >/dev/null; done
d=$(HUB_PROJECT="$T/work/big" "$H" digest claude)
has "digest caps fact count" "$d" "newest 40 of 50 shown; full text: hub kb big"
has "digest shows newest fact" "$d" "- fact 50"
hasnt "digest hides oldest fact" "$d" "- fact 1 ("

# digest: long facts are shortened, total size is budgeted, notes don't get two dates
longfact=$(printf 'L%.0s' $(seq 1 600))
for i in $(seq 1 30); do "$H" note projects/wordy "fact $i $longfact" >/dev/null; done
d=$(HUB_PROJECT="$T/work/wordy" "$H" digest claude)
bytes=$(printf '%s' "$d" | wc -c | tr -d ' ')
[ "$bytes" -le 3300 ] && ok "digest stays within budget ($bytes bytes)" || bad "digest too big: $bytes bytes"
has "digest says facts were shortened" "$d" "shortened (…); full text: hub kb wordy"
has "digest keeps newest long fact" "$d" "- fact 30 LLL"
maxline=$(printf '%s\n' "$d" | awk '{ if (length($0) > m) m = length($0) } END { print m }')
[ "$maxline" -le 240 ] && ok "digest lines shortened (longest $maxline bytes)" || bad "digest line too long: $maxline"
d=$(HUB_PROJECT="$T/work/wordy" HUB_DIGEST_BYTES=100000 HUB_DIGEST_WIDTH=100000 "$H" digest claude)
has "digest budget is configurable" "$d" "- fact 1 LLL"
"$H" note projects/dated "already dated (2026-01-02, codex)" >/dev/null
"$H" note projects/dated "plain fact" >/dev/null
n=$(grep -cE '\([0-9-]+[^)]*\) \([0-9-]+' "$HUB_HOME/kb/projects/dated.md")
[ "$n" = 0 ] && ok "note does not stack a second date" || bad "note stacked dates: $(cat "$HUB_HOME/kb/projects/dated.md")"
grep -qE '^- plain fact \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$HUB_HOME/kb/projects/dated.md" && ok "note still dates plain facts" || bad "plain fact not dated"
d=$(HUB_PROJECT="$T/work/nothing" "$H" digest claude)
[ -z "$d" ] && ok "digest empty when nothing to say" || bad "digest not empty: $d"

# --- 2: other agent shown only for this project, never its message text
HUB_PROJECT="$T/work/other" "$H" log codex agent-turn-complete "SECRET-LOOKING REPLY TEXT from another project"
d=$(HUB_PROJECT="$T/work/app" "$H" digest claude)
hasnt "other project's activity hidden" "$d" "SECRET-LOOKING"
hasnt "other project's agent line hidden" "$d" "last active here"
HUB_PROJECT="$T/work/app" "$H" log codex agent-turn-complete "REPLY TEXT in app"
d=$(HUB_PROJECT="$T/work/app" "$H" digest claude)
has "same-project activity time shown" "$d" "codex last active here:"
hasnt "activity detail text never shown" "$d" "REPLY TEXT"

# --- 1: hook does not replay a message every turn
J="{\"session_id\":\"s1\",\"cwd\":\"$T/work/app\"}"
echo "$J" | bash "$HOOK" session-start >/dev/null
HUB_AGENT=codex "$H" post claude "hello" "body" >/dev/null
t1=$(echo "$J" | bash "$HOOK" prompt); echo "$J" | bash "$HOOK" stop
t2=$(echo "$J" | bash "$HOOK" prompt); echo "$J" | bash "$HOOK" stop
has "message shown on first turn" "$t1" "hello"
[ -z "$t2" ] && ok "message not replayed on second turn" || bad "replayed: $t2"
HUB_AGENT=codex "$H" post claude "second" "b2" >/dev/null
t3=$(echo "$J" | bash "$HOOK" prompt)
has "new message shown" "$t3" "second"
hasnt "old message not repeated with new one" "$t3" "hello"

# --- 5: search
s=$("$H" search "SECOND fact"); rc=$?
[ $rc = 0 ] && has "search finds case-insensitively" "$s" "kb/projects/app.md" || bad "search rc=$rc: $s"
s=$("$H" search "zzz-not-there"); rc=$?
[ $rc = 1 ] && has "search no-hit message" "$s" "no matches" || bad "search no-hit rc=$rc: $s"
mkdir -p "$HUB_HOME/skills/demo/scripts"; printf '#!/bin/sh\necho needle-in-script\n' > "$HUB_HOME/skills/demo/scripts/run.sh"
printf -- '---\nname: demo\ndescription: Demo skill. Use when testing.\n---\nRun `scripts/run.sh`.\n' > "$HUB_HOME/skills/demo/SKILL.md"
s=$("$H" search needle-in-script)
has "search covers skill scripts" "$s" "skills/demo/scripts/run.sh"
hasnt "search skips template" "$("$H" search 'One or two lines' || true)" "_TEMPLATE"

# --- 6: lint
"$H" sync >/dev/null
l=$("$H" lint); rc=$?
[ $rc = 0 ] && ok "lint clean hub passes" || bad "lint clean rc=$rc: $l"
"$H" skill new draft-it >/dev/null
"$H" skill new drafting >/dev/null
mkdir -p "$HUB_HOME/skills/longdesc"; printf -- "---\nname: wrongname\ndescription: %s\n---\nUses ~/nowhere/missing.sh and tests/e2e/login.mjs\n" "$(printf 'x%.0s' $(seq 1 400))" > "$HUB_HOME/skills/longdesc/SKILL.md"
echo "orphan" > "$HUB_HOME/kb/topics/orphan.md"
printf -- '- [ghost](topics/ghost.md)\n' >> "$HUB_HOME/kb/INDEX.md"
ln -s "$HUB_HOME/skills/deleted" "$HOME/.claude/skills/deleted"
l=$("$H" lint); rc=$?
[ $rc = 1 ] && ok "lint fails on errors" || bad "lint rc=$rc"
has "lint: template placeholder" "$l" "skills/draft-it: still contains template placeholder"
has "lint: duplicate names" "$l" "skills/draft-it and skills/drafting look like overlapping"
has "lint: name mismatch" "$l" "frontmatter name is 'wrongname'"
has "lint: long description" "$l" "description is 400 chars"
has "lint: missing absolute script" "$l" "references ~/nowhere/missing.sh, which does not exist"
has "lint: relative script outside skill" "$l" "mentions tests/e2e/login.mjs"
hasnt "lint: script inside skill folder ok" "$l" "skills/demo"
has "lint: unlinked skill" "$l" "longdesc is not linked"
has "lint: dangling link" "$l" "deleted is a dangling link"
has "lint: index ghost" "$l" "links topics/ghost.md, which does not exist"
has "lint: unindexed file" "$l" "kb/topics/orphan.md is not listed"

# SQL quoting: apostrophes round-trip and can't break out of the string (bash 3.2 regression)
HUB_AGENT=codex "$H" post claude "it's a 'quoted' subject" "body with it's" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && ok "post with apostrophes works" || bad "post with apostrophes rc=$rc"
has "apostrophes round-trip" "$("$H" inbox claude)" "it's a 'quoted' subject"
HUB_AGENT=claude "$H" feedback "x'); DROP TABLE feedback; --" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && ok "feedback with injection text stored" || bad "feedback injection text rc=$rc"
has "feedback table survives injection text" "$("$H" feedback list)" "DROP TABLE feedback"
"$H" log codex turn-ended "Codex's reply mentions it's done" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && ok "log detail with apostrophe works" || bad "log with apostrophe rc=$rc"

# feedback lifecycle
fid=$(HUB_AGENT=claude "$H" feedback --area kb "example-app facts too long" | sed -E 's/^feedback #([0-9]+).*/\1/')
expect_rc 1 "feedback bad area rejected" "$H" feedback --area nope "x"
expect_rc 1 "feedback unquoted rejected" "$H" feedback two words
expect_rc 1 "feedback close bad status" "$H" feedback close "$fid" maybe
expect_rc 0 "feedback close queued" "$H" feedback close "$fid" queued "needs a supervised session"
has "queued feedback listed" "$("$H" feedback list --status queued)" "example-app facts too long"
has "digest announces queued work" "$(HUB_PROJECT="$T/work/app" "$H" digest claude)" "hub improvement(s) queued for a supervised session"

# lint: deliberate relationships and declared dependencies are not flagged
mk() { mkdir -p "$HUB_HOME/skills/$1"; printf -- "---\nname: %s\ndescription: %s\n%s---\n%s\n" "$1" "$2" "${4:-}" "$3" > "$HUB_HOME/skills/$1/SKILL.md"; }
long=$(printf 'y%.0s' $(seq 1 500))
mk backup-run "Run a backup." "Tools are in [[backup-tools]]."
mk backup-tools "Where the tools live." "Inventory."
mk alias-me "$long" "Call the Skill tool with \"backup-run\"." "disable-model-invocation: true
"
mkdir -p "$HOME/ext/lib"; echo 'echo hi' > "$HOME/ext/lib/ok.sh"
mk ext-declared "Uses an external script." "<!-- hub-lint: external ~/ext (owned by another tool) -->
Run ~/ext/lib/ok.sh and ~/ext/lib/gone.sh"
mk ext-undeclared "Uses an external script." "Run ~/ext/lib/ok.sh"
"$H" sync >/dev/null
l=$("$H" lint)
hasnt "lint: skills that name each other are not overlaps" "$l" "backup-run and skills/backup-tools"
hasnt "lint: alias description not budgeted" "$l" "skills/alias-me: description is"
hasnt "lint: declared external not warned" "$l" "skills/ext-declared: depends on"
has "lint: declared external still errors when missing" "$l" "skills/ext-declared: references ~/ext/lib/gone.sh, which does not exist"
has "lint: undeclared external warned" "$l" "skills/ext-undeclared: depends on ~/ext/lib/ok.sh"

# HUB_LINK_DIRS replaces the default skill folders (colon-separated, leading ~ expanded, empty entries ignored)
HUB_LINK_DIRS="$T/other/a::~/custom-skills" "$H" sync >/dev/null
[ -L "$T/other/a/backup-run" ] && ok "HUB_LINK_DIRS: skill linked into a custom folder" || bad "HUB_LINK_DIRS: no link in $T/other/a"
[ -L "$HOME/custom-skills/backup-run" ] && ok "HUB_LINK_DIRS: leading ~ expanded" || bad "HUB_LINK_DIRS: no link in $HOME/custom-skills"
st=$(HUB_LINK_DIRS="$T/other/a" "$H" status)
has "HUB_LINK_DIRS: status checks the custom folder" "$st" "links in $T/other/a:"
hasnt "HUB_LINK_DIRS: status drops the default folders" "$st" "links in $HOME/.claude/skills"
has "no HUB_LINK_DIRS: defaults still used" "$("$H" status)" "links in $HOME/.claude/skills"

echo "---"; echo "passed $pass, failed $fail"
rm -rf "$T"
[ "$fail" = 0 ]
