#!/usr/bin/env bash
# memory_session_end.sh — SessionEnd (/exit): deterministically capture this session as one
# low-importance episodic memory (files/commands/goal/outcome from the transcript). /dream
# later refines it. Logging-only (SessionEnd cannot block/inject); fail-open.
set -uo pipefail
P="$HOME/dotfiles/claude-memory"
[ -f "$P/pyproject.toml" ] || exit 0
if command -v mise >/dev/null 2>&1; then
  exec mise exec -- uv run --quiet --project "$P" cc-memory hook session-end
elif command -v uv >/dev/null 2>&1; then
  exec uv run --quiet --project "$P" cc-memory hook session-end
fi
exit 0
