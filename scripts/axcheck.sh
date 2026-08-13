#!/usr/bin/env bash
# Build, launch and report the Accessibility integration harness.
set -euo pipefail
cd "$(dirname "$0")/.."

LOG="$HOME/.local/state/kutu/axcheck.log"
mkdir -p "$(dirname "$LOG")"
rm -f "$LOG"

APP="$(scripts/build-app.sh kutu-axcheck co.halit.kutu.axcheck KutuAXCheck)"
open "$APP"

for _ in $(seq 1 60); do
    if [ -f "$LOG" ] && grep -q '^AXCHECK:' "$LOG"; then break; fi
    /bin/sleep 0.5
done

if [ ! -f "$LOG" ]; then
    echo "harness produced no output — is KutuAXCheck granted Accessibility?" >&2
    exit 1
fi
cat "$LOG"
grep -q '^AXCHECK: PASS' "$LOG"
