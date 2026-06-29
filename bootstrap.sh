#!/usr/bin/env bash
# bootstrap.sh — provision a fresh machine. Run OUTSIDE a Claude Code session.
#   git clone https://github.com/arkrtm/dotfiles ~/dotfiles && ~/dotfiles/bootstrap.sh
#
# NOTE: Claude Code itself is NOT installed/managed here — install & update it yourself.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
warn(){ printf '! %s\n' "$*" >&2; }
ok(){   printf '✓ %s\n' "$*"; }
step(){ printf '\n=== %s ===\n' "$*"; }

step "1. Homebrew"
command -v brew >/dev/null 2>&1 || { warn "Homebrew not found — install from https://brew.sh then re-run"; exit 1; }
ok "brew present"

step "2. base tools (jq, git, gitleaks)"
for f in jq git gitleaks; do
  command -v "$f" >/dev/null 2>&1 || brew install "$f" || warn "brew install $f failed"
done

step "3. mise"
command -v mise >/dev/null 2>&1 || brew install mise || { warn "mise install failed"; exit 1; }
ok "mise $(mise --version 2>&1 | head -1)"

step "4. deploy dotfiles (makes the pinned mise config live)"
"$DOTFILES/install.sh" apply

step "5. install pinned runtimes (node/python/uv) via mise"
eval "$(mise activate bash)"
mise trust "$DOTFILES/mise/config.toml" 2>/dev/null || true   # mise resolves the symlink to the repo path
mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || true
mise install || warn "mise install had issues"
if command -v uv >/dev/null 2>&1; then ok "uv $(uv --version)"; else warn "uv not on PATH after mise install — check mise activation / shims in your shell rc"; fi

step "6. pre-commit (local quality gate; no CI) + secret-scan on this dotfiles repo"
command -v pre-commit >/dev/null 2>&1 || uv tool install pre-commit || warn "pre-commit install failed"
( cd "$DOTFILES" && command -v pre-commit >/dev/null 2>&1 && pre-commit install >/dev/null 2>&1 ) \
  && ok "secret-scan git hook installed in $DOTFILES" || warn "pre-commit install in dotfiles skipped"

step "7. leftover checks"
[[ -e "$HOME/.config/uv" ]] && warn "~/.config/uv exists — a stray uv.toml there can conflict with the mise pin; review it"

step "8. cc-memory (machine-local data dirs + deps)"
mkdir -p "$HOME/.local/share/cc-memory" "$HOME/.local/state/cc-learn"
if [[ -f "$DOTFILES/claude-memory/pyproject.toml" ]]; then
  ( cd "$DOTFILES/claude-memory" && uv sync ) || warn "cc-memory uv sync failed"
  ( cd "$DOTFILES/claude-memory" && uv run cc-memory init ) >/dev/null 2>&1 || warn "cc-memory init skipped (build cc-memory first)"
else
  warn "claude-memory/ not present yet — build it before relying on long-term memory"
fi

step "9. Claude Code MCP registration (cc-memory, user scope)"
if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>&1 | head -1)"
  if [[ -f "$DOTFILES/claude-memory/pyproject.toml" ]]; then
    claude mcp add --scope user cc-memory -- mise exec -- uv run --project "$DOTFILES/claude-memory" cc-memory mcp 2>/dev/null \
      && ok "registered cc-memory MCP" || warn "cc-memory MCP add skipped (already registered?)"
  fi
else
  warn "Claude Code not installed (this repo does not manage it). After installing, run:"
  warn "  claude mcp add --scope user cc-memory -- mise exec -- uv run --project $DOTFILES/claude-memory cc-memory mcp"
fi

ok "bootstrap complete — open a new shell (so mise/uv are on PATH), then run: $DOTFILES/install.sh --check"
