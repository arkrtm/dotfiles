#!/usr/bin/env bash
# update.sh — pull the latest dotfiles and re-deploy.
#   ./update.sh                 pull + install + mise install + cc-memory sync
#   ./update.sh --with-plugins   also update plugin marketplaces (none by default = zero-plugin)
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
warn(){ printf '! %s\n' "$*" >&2; }
ok(){   printf '✓ %s\n' "$*"; }

# Precheck deployment drift BEFORE pulling, so /config edits to live settings.json aren't silently clobbered.
if ! "$DOTFILES/install.sh" --check >/dev/null 2>&1; then
  warn "deployment drift detected (e.g. settings.json changed via /config):"
  "$DOTFILES/install.sh" --check || true
  warn "If the live changes are wanted, copy them into $DOTFILES/claude/settings.json before continuing."
fi

git -C "$DOTFILES" pull --ff-only || { warn "git pull --ff-only failed (diverged?) — resolve manually"; exit 1; }
"$DOTFILES/install.sh" apply

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
  mise install || warn "mise install had issues"
fi

if [[ -f "$DOTFILES/claude-memory/pyproject.toml" ]] && command -v uv >/dev/null 2>&1; then
  ( cd "$DOTFILES/claude-memory" && uv sync ) || warn "cc-memory uv sync had issues"
fi

if [[ "${1:-}" == "--with-plugins" ]] && command -v claude >/dev/null 2>&1; then
  claude plugin marketplace update 2>/dev/null || true
fi

ok "update complete"
