---
name: open-chad-restart
description: Restart OpenCode in the current pane to reload config and model preferences
agent: build
---

# open-chad Restart

Restart OpenCode in the current openchad tmux pane. This reloads all configuration changes (model preferences, MCP servers, instructions, themes) without creating a new session.

## When to Use

- After changing model preferences via `omp`
- After modifying `opencode.json` (MCP servers, plugins, instructions)
- After updating agents or instruction files
- After running `openchad update`

## Execution

Run the restart command:

```bash
openchad restart
```

This will:
1. Verify you're inside an openchad tmux session (`oc-*`)
2. Preserve the current working directory
3. Kill the current OpenCode process in this pane
4. Respawn OpenCode in the same pane with the preserved cwd

## What Gets Preserved

- Tmux session (same `oc-*` session name)
- Tmux window and pane
- Working directory
- Status bar (metrics, LLM gauges, session title)

## What Gets Reloaded

- `opencode.json` configuration
- MCP server connections
- Agent definitions and instructions
- Theme settings
- Model preferences

## Error Conditions

The command will refuse to run if:
- Not inside a tmux session
- `TMUX_PANE` is not set
- The session name doesn't match `oc-*` (not an openchad session)

In these cases, it prints an error message and exits without making changes.
