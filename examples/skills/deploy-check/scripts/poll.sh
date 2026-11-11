#!/usr/bin/env bash
# poll.sh <url> — wait for a preview deploy to answer HTTP 200 (5 tries, 15 s apart).
# Basic auth from PREVIEW_USER / PREVIEW_PASS if set.
set -euo pipefail
url="${1:?usage: poll.sh <url>}"
auth=()
[ -n "${PREVIEW_USER:-}" ] && auth=(-u "$PREVIEW_USER:${PREVIEW_PASS:-}")
for i in 1 2 3 4 5; do
  code=$(curl -sk "${auth[@]+"${auth[@]}"}" -o /dev/null -w '%{http_code}' --max-time 20 "$url" || echo 000)
  echo "poll $i: $code"
  [ "$code" = "200" ] && exit 0
  [ "$i" -lt 5 ] && sleep 15
done
echo "not live after 5 polls: check the CI pipeline"
exit 1
