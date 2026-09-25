#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
py="scripts/herdr-claude-session-title.py"
fail() { echo "FAIL: $1" >&2; exit 1; }

# synthetic messages must never produce a title
for synthetic in \
  '<task-notification> <task-id>a5b586e23594b6ae5</task-id> <tool>done</tool>' \
  '<system-reminder>Codebase and user instructions are shown below</system-reminder>' \
  '<cross-session-message from="worker">check if tests pass</cross-session-message>' \
  '<local-command-stdout>ok</local-command-stdout>'
do
  if printf '%s' "$synthetic" | python3 "$py" prompt >/dev/null 2>&1; then
    fail "expected synthetic message to produce no title: $synthetic"
  fi
done

# empty / whitespace-only prompt produces no title
if printf '   \n  ' | python3 "$py" prompt >/dev/null 2>&1; then
  fail "expected blank prompt to produce no title"
fi

# real prompt becomes the title, truncated to 60 chars
title=$(printf 'help me fix the login bug in auth.py' | python3 "$py" prompt)
[ "$title" = "help me fix the login bug in auth.py" ] || fail "got: $title"

long_title=$(printf 'x%.0s' $(seq 1 80) | python3 "$py" prompt)
[ "${#long_title}" -eq 60 ] || fail "expected 60-char truncation, got length: ${#long_title}"

# pasted content keeps the user's text but drops the wrapper tag
title=$(printf '<pasted_content id="e5c9">\nfix the pane title bug please\n</pasted_content>' | python3 "$py" prompt)
[ "$title" = "fix the pane title bug please" ] || fail "got: $title"

# text around a pasted block is preserved
title=$(printf 'look at this: <pasted_content id="x">inner text</pasted_content> thanks' | python3 "$py" prompt)
[ "$title" = "look at this: inner text thanks" ] || fail "got: $title"

echo "test-prompt: OK"
