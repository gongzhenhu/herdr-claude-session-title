# herdr-claude-session-title

Herdr plugin: mirrors the Claude Code session title (set with `/rename`,
or the auto-generated summary) into the herdr pane metadata title.

## How it works

The `install` action registers a small hook script with Claude Code
(`~/.claude/settings.json`, events: SessionStart, UserPromptSubmit, Stop).
On each event the hook reads the session transcript, picks the latest
`custom-title` record (your `/rename`), falls back to the latest `ai-title`
record (Claude Code's auto-generated session name; legacy
`sessions-index.json` summaries are a last resort), and reports it to the
herdr server over the herdr socket as pane metadata
(`pane.report_metadata`). The pane label is not
touched; the title shows up in herdr's navigator/detail view.

The hook is silent by design: outside herdr, or on any error, it exits 0
without output and never blocks Claude Code (0.5s socket timeout).

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with hooks support
- python3 on PATH

## Install

    herdr plugin install gongzhenhu/herdr-claude-session-title
    herdr plugin action invoke gongzhenhu.claude-session-title.install

Restart any Claude Code session that was already running; hooks are read
at session start.

## Verify

1. Inside herdr, open Claude Code in a pane.
2. Run `/rename my-task-name`, then send any message.
3. Open the herdr navigator: the pane detail shows `my-task-name`.

Check installation state any time:

    herdr plugin action invoke gongzhenhu.claude-session-title.status

## Uninstall

    herdr plugin action invoke gongzhenhu.claude-session-title.uninstall
    herdr plugin uninstall gongzhenhu.claude-session-title

## Development

    sh tests/run.sh        # offline tests, no herdr/Claude needed
    herdr plugin link .    # register the working tree with herdr

Troubleshooting: `herdr plugin log list --plugin gongzhenhu.claude-session-title`
