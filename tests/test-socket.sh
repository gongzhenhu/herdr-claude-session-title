#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
out="$tmp/herdr-calls.txt"
fail() { echo "FAIL: $1" >&2; exit 1; }

# fake herdr binary: records its arguments, one line per invocation
mkdir -p "$tmp/bin"
cat > "$tmp/bin/herdr" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$out"
exit 0
EOF
chmod +x "$tmp/bin/herdr"

# --- case 1: Stop event reports the transcript title via the CLI ---
printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"Stop"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$tmp/herdr.sock" \
  HERDR_BIN_PATH="$tmp/bin/herdr" \
  sh scripts/herdr-claude-session-title.sh

grep -q "^pane report-metadata %42 --source agent:title --agent claude --token title=second-name$" "$out" \
  || fail "unexpected herdr invocation(s): $(cat "$out")"
echo "case 1 (report): OK"

# --- case 2: SessionStart of a session with no title clears the pane title ---
: > "$out"
printf '{"session_id":"sid-9","transcript_path":"%s","hook_event_name":"SessionStart","source":"startup"}' \
  "$PWD/tests/fixtures/transcript-bare.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$tmp/herdr.sock" \
  HERDR_BIN_PATH="$tmp/bin/herdr" \
  sh scripts/herdr-claude-session-title.sh

grep -q -- "--clear-token title$" "$out" || fail "expected title clear, got: $(cat "$out")"
echo "case 2 (clear on titleless SessionStart): OK"

# --- case 3: SessionStart of a session WITH a title reports it ---
: > "$out"
printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"SessionStart","source":"resume"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$tmp/herdr.sock" \
  HERDR_BIN_PATH="$tmp/bin/herdr" \
  sh scripts/herdr-claude-session-title.sh

grep -q -- "--token title=second-name$" "$out" || fail "expected title report, got: $(cat "$out")"
echo "case 3 (report on titled SessionStart): OK"

# --- case 4: subagent event must not invoke herdr at all ---
: > "$out"
printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"Stop","agent_id":"agent-xyz"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$tmp/herdr.sock" \
  HERDR_BIN_PATH="$tmp/bin/herdr" \
  sh scripts/herdr-claude-session-title.sh
[ ! -s "$out" ] || fail "subagent event invoked herdr: $(cat "$out")"
echo "case 4 (subagent skip): OK"

# --- case 5: outside herdr the wrapper exits silently ---
printf '{"session_id":"sid-1"}' | sh scripts/herdr-claude-session-title.sh \
  || fail "wrapper must exit 0 outside herdr"
echo "case 5 (outside herdr): OK"

echo "test-socket: OK"
