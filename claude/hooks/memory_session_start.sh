#!/usr/bin/env bash
# memory_session_start.sh — SessionStart: inject this project's relevant long-term memory
# (+ the resolved scope path). Thin shim over cc-memory; fail-open if uv/mise unavailable.
set -uo pipefail
P="$HOME/dotfiles/claude-memory"
[ -f "$P/pyproject.toml" ] || exit 0
if command -v mise >/dev/null 2>&1; then
  exec mise exec -- uv run --quiet --project "$P" cc-memory hook session-start
elif command -v uv >/dev/null 2>&1; then
  exec uv run --quiet --project "$P" cc-memory hook session-start
fi
exit 0
