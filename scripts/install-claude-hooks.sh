#!/usr/bin/env bash
# OPTIONAL. Points Claude Code's hooks at kutu's status socket so boxes show
# live session state. kutu works fully without it; boxes just show no dot.
# Any other tool can report the same way in one line:
#   echo '{"kutu":"status","arg":"myBox","state":"working"}' \
#     | nc -U ~/.local/state/kutu/kutu.sock
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
SOCKET="$HOME/.local/state/kutu/kutu.sock"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.kutu-backup"

python3 - "$SETTINGS" "$SOCKET" <<'PYEOF'
import json, sys

settings_path, socket_path = sys.argv[1], sys.argv[2]
with open(settings_path) as handle:
    settings = json.load(handle)

# Claude Code delivers the hook payload as JSON on stdin, already carrying
# hook_event_name, cwd and session_id. Forwarding stdin untouched avoids shell
# quoting entirely and depends on no environment variables.
command = f"/usr/bin/nc -U -w1 {socket_path} >/dev/null 2>&1 || true"

hooks = settings.setdefault("hooks", {})
for event in ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]:
    matchers = hooks.setdefault(event, [])
    # Drop any previous kutu entry so re-running stays idempotent.
    matchers[:] = [
        m for m in matchers
        if not any("kutu/kutu.sock" in h.get("command", "") for h in m.get("hooks", []))
    ]
    matchers.append({"hooks": [{"type": "command", "command": command}]})

with open(settings_path, "w") as handle:
    json.dump(settings, handle, indent=2)
print(f"registered kutu hooks for {len(hooks)} events in {settings_path}")
PYEOF
