---
name: remember
description: Store a durable memory for this project (manual companion to memory_remember). Use when the user says "remember this" or you learn a project fact/convention worth keeping across sessions.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(mise exec:*), Bash(uv run:*)
argument-hint: <the fact to remember>
---

# /remember — store a memory

Store the note as a project memory. To avoid argv quoting/injection issues, pipe the content via **stdin** (do NOT interpolate it into the command). Run (substituting the real content into the heredoc):

```
SCOPE="$(mise exec -- uv run --quiet --project "$HOME/dotfiles/claude-memory" cc-memory scope)"
mise exec -- uv run --quiet --project "$HOME/dotfiles/claude-memory" cc-memory remember --stdin --scope "$SCOPE" --type semantic <<'MEMO'
<the content to remember, verbatim, on its own lines>
MEMO
```
Choose `--type`: **semantic** (a fact), **procedural** (a how-to), **episodic** (an event). Likely secrets are refused — that is intended. Report the returned id.
