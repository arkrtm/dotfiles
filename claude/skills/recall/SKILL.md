---
name: recall
description: Search this project's long-term memory for relevant past decisions and facts. Manual companion to the automatic memory_recall MCP tool. Use to look something up from memory.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(mise exec:*), Bash(uv run:*)
argument-hint: <what to recall>
---

# /recall — search long-term memory

```!
P="$HOME/dotfiles/claude-memory"
if command -v mise >/dev/null 2>&1; then mise exec -- uv run --quiet --project "$P" cc-memory recall "$ARGUMENTS"
else uv run --quiet --project "$P" cc-memory recall "$ARGUMENTS"; fi
```
The scored memories above are for the current project. Use them to orient — then read the actual code before acting (memory reflects the past, not the current state).
