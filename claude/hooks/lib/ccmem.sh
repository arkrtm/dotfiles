#!/usr/bin/env bash
# ccmem.sh — single entry point to the cc-memory CLI from anywhere (slash commands + future hooks).
# Resolves the toolchain (mise > uv) and pins --project so it works regardless of cwd; scope is
# still resolved from the CALLER's cwd by cc-memory itself (git toplevel | cwd), matching the
# session-start/end hooks. NOT fail-open on its own: it returns the CLI's real exit code (so a
# command can surface refusals/errors), and exits 127 only when no toolchain is present.
#   $HOME/.claude/hooks/lib/ccmem.sh recall "auth flow"
#   $HOME/.claude/hooks/lib/ccmem.sh remember "X" --type semantic
#   $HOME/.claude/hooks/lib/ccmem.sh dream --emit-candidates
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"   # GUI-launched thin PATH
P="$HOME/dotfiles/claude-memory"
[ -f "$P/pyproject.toml" ] || { echo "ccmem: cc-memory project not found at $P" >&2; exit 127; }
if command -v mise >/dev/null 2>&1; then
  exec mise exec -- uv run --quiet --project "$P" cc-memory "$@"
elif command -v uv >/dev/null 2>&1; then
  exec uv run --quiet --project "$P" cc-memory "$@"
fi
echo "ccmem: neither mise nor uv on PATH" >&2
exit 127
