#!/bin/sh
# herdr plugin action: registers the Claude Code hook for session title reporting
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hooks_dir="$claude_dir/hooks"
hook_sh="$hooks_dir/herdr-claude-session-title.sh"
hook_py="$hooks_dir/herdr-claude-session-title.py"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$hooks_dir"
cp "$plugin_root/scripts/herdr-claude-session-title.sh" "$hook_sh"
cp "$plugin_root/scripts/herdr-claude-session-title.py" "$hook_py"
chmod +x "$hook_sh"

HOOK_COMMAND="sh '$hook_sh'" SETTINGS_PATH="$claude_dir/settings.json" python3 - <<'PY'
import json
import os
import tempfile

settings_path = os.environ["SETTINGS_PATH"]
hook_command = os.environ["HOOK_COMMAND"]
marker = "herdr-claude-session-title.sh"
events = ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd"]

settings = {}
if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)
    backup = settings_path + ".bak-claude-session-title"
    with open(backup, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")

if not isinstance(settings, dict):
    raise SystemExit("error: settings.json root is not a JSON object; refusing to modify")
hooks = settings.setdefault("hooks", {})
if not isinstance(hooks, dict):
    raise SystemExit("error: settings.json 'hooks' is not a JSON object; refusing to modify")
for event in events:
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        raise SystemExit("error: settings.json 'hooks.{}' is not a list; refusing to modify".format(event))
    kept = []
    for entry in entries:
        if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
            had_marker = any(
                isinstance(h, dict) and marker in str(h.get("command", ""))
                for h in entry["hooks"]
            )
            if had_marker:
                entry["hooks"] = [
                    h for h in entry["hooks"]
                    if not (isinstance(h, dict) and marker in str(h.get("command", "")))
                ]
                if not entry["hooks"]:
                    continue
        kept.append(entry)
    new_entry = {"hooks": [{"type": "command", "command": hook_command, "timeout": 10}]}
    if event == "SessionStart":
        new_entry["matcher"] = "*"
    kept.append(new_entry)
    hooks[event] = kept

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_path) or ".", prefix=".settings-")
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(tmp_path, settings_path)
print("registered hooks: " + ", ".join(events))
PY

echo "installed: $hook_sh"
echo "note: already-running Claude Code sessions pick up new hooks on restart"
