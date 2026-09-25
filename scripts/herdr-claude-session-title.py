#!/usr/bin/env python3
"""Reports the Claude Code session title to herdr as pane metadata title.

Modes:
  (no args)                             hook mode: Claude Code hook input JSON on stdin
  extract <transcript_path> <sid>       print extracted title (test entrypoint)
  prompt                                print fallback title for the prompt on stdin (test entrypoint)
"""
import json
import os
import re
import subprocess
import sys

SOURCE = "agent:title"
MAX_TITLE_CHARS = 120
MAX_PROMPT_CHARS = 60

# Synthetic messages Claude Code delivers as user prompts. They are not real
# user input and must never become the pane title.
SKIP_PROMPT_PREFIXES = (
    "<task-notification>",
    "<system-reminder>",
    "<cross-session-message",
    "<local-command-stdout>",
    "<local-command-stderr>",
)

# A pasted block *is* real user content; only its wrapper tag is synthetic.
# Note: Claude Code closes the wrapper as </pasted_content id="xxxx"> (the id
# is repeated on the closing tag), not plain </pasted_content>.
PASTED_CONTENT_RE = re.compile(
    r"<pasted_content[^>]*>(.*?)</pasted_content[^>]*>", re.DOTALL
)


def sanitize(title):
    if not isinstance(title, str):
        return None
    cleaned = "".join(
        " " if (ch < " " or ch == "\x7f" or "\x80" <= ch <= "\x9f") else ch
        for ch in title
    )
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        return None
    return cleaned[:MAX_TITLE_CHARS]


def title_from_transcript(transcript_path):
    # /rename writes {"type":"custom-title","customTitle":...}; Claude Code's
    # auto-naming writes {"type":"ai-title","aiTitle":...}. A user-chosen name
    # always beats the auto name, regardless of which record appears later.
    custom_title = None
    ai_title = None
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if '"custom-title"' not in line and '"ai-title"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict):
                    continue
                if record.get("type") == "custom-title":
                    candidate = sanitize(record.get("customTitle"))
                    if candidate:
                        custom_title = candidate
                elif record.get("type") == "ai-title":
                    candidate = sanitize(record.get("aiTitle"))
                    if candidate:
                        ai_title = candidate
    except OSError:
        return None
    return custom_title or ai_title


def summary_from_index(transcript_path, session_id):
    index_path = os.path.join(os.path.dirname(transcript_path), "sessions-index.json")
    try:
        with open(index_path, encoding="utf-8") as handle:
            index = json.load(handle)
    except (OSError, ValueError):
        return None
    entries = index.get("entries") if isinstance(index, dict) else None
    if not isinstance(entries, list):
        return None
    for entry in entries:
        if isinstance(entry, dict) and entry.get("sessionId") == session_id:
            return sanitize(entry.get("summary"))
    return None


def title_from_prompt(prompt):
    """Derive a fallback title from a UserPromptSubmit prompt, or None."""
    if not isinstance(prompt, str):
        return None
    text = prompt.strip()
    if not text:
        return None
    # Drop synthetic wrappers: task notifications, system reminders and
    # cross-session messages are not user input.
    if text.startswith(SKIP_PROMPT_PREFIXES):
        return None
    # Keep the content of pasted blocks but strip the wrapper tag.
    text = PASTED_CONTENT_RE.sub(lambda m: " {} ".format(m.group(1)), text)
    text = " ".join(text.split())
    if not text or text.startswith(SKIP_PROMPT_PREFIXES):
        return None
    cleaned = sanitize(text)
    if not cleaned:
        return None
    return cleaned[:MAX_PROMPT_CHARS]


def extract_title(transcript_path, session_id):
    title = title_from_transcript(transcript_path)
    if title:
        return title
    # last resort: legacy index (current Claude Code no longer maintains it,
    # but old sessions may still have a summary there)
    return summary_from_index(transcript_path, session_id)


def report(pane_id, title):
    _report_metadata(pane_id, ["--token", "title={}".format(title)])


def clear_reported_title(pane_id):
    _report_metadata(pane_id, ["--clear-token", "title"])


def _report_metadata(pane_id, extra):
    herdr_bin = os.environ.get("HERDR_BIN_PATH") or "herdr"
    cmd = [
        herdr_bin, "pane", "report-metadata", pane_id,
        "--source", SOURCE,
        "--agent", "claude",
    ] + extra
    try:
        subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except Exception:
        pass


def hook_mode():
    pane_id = os.environ.get("HERDR_PANE_ID")
    socket_path = os.environ.get("HERDR_SOCKET_PATH")
    if not pane_id or not socket_path:
        return
    try:
        hook_input = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(hook_input, dict):
        return
    if hook_input.get("agent_id"):
        # subagent event: its transcript does not represent the main session
        return
    if hook_input.get("hook_event_name") == "SessionEnd":
        # session over (Ctrl+C exit = reason prompt_input_exit): drop the
        # pane title so the next session in this pane does not inherit it
        clear_reported_title(pane_id)
        return
    session_id = hook_input.get("session_id")
    transcript_path = hook_input.get("transcript_path")
    if not isinstance(session_id, str) or not isinstance(transcript_path, str):
        return
    title = extract_title(transcript_path, session_id)
    if not title and hook_input.get("hook_event_name") == "UserPromptSubmit":
        title = title_from_prompt(hook_input.get("prompt"))
    if not title:
        return
    report(pane_id, title)


def main():
    args = sys.argv[1:]
    if args[:1] == ["extract"] and len(args) == 3:
        title = extract_title(args[1], args[2])
        if not title:
            return 1
        print(title)
        return 0
    if args[:1] == ["prompt"]:
        # prompt text comes on stdin (may be multi-line)
        title = title_from_prompt(sys.stdin.read())
        if not title:
            return 1
        print(title)
        return 0
    try:
        hook_mode()
    except Exception:
        # a hook must never disturb Claude Code
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
