#!/usr/bin/env bash
# Update an already-installed dotfiles checkout.
#   1. Pull latest from git
#   2. Self-update each managed tool
#   3. Re-run install.sh to pick up any newly added steps
#
# Symlinked configs (~/.claude/CLAUDE.md, ~/.claude/settings.json) update
# automatically via the git pull — no extra step needed.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

#--- 0. Pull repo -----------------------------------------------------------
log "Pulling latest dotfiles"
git -C "$DOTFILES_DIR" pull --ff-only

#--- 1. uv ------------------------------------------------------------------
if have uv; then
  log "Updating uv"
  uv self update || warn "uv self update failed"
fi

#--- 2. rtk -----------------------------------------------------------------
if have rtk; then
  log "Updating rtk"
  if [[ "$OS" == "Darwin" ]] && have brew && brew list rtk >/dev/null 2>&1; then
    brew upgrade rtk || warn "brew upgrade rtk failed"
  else
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  fi
fi

#--- 3. claude-mem ----------------------------------------------------------
if have npx; then
  log "Updating claude-mem"
  npx -y claude-mem@latest install || warn "claude-mem update failed"
fi

#--- 4. andrej-karpathy-skills (re-pull skill + CLAUDE.md) ------------------
KARPATHY_DIR="$HOME/.claude/skills/karpathy-guidelines"
KARPATHY_CLAUDE_MD="$HOME/.claude/karpathy-CLAUDE.md"
if [[ -d "$KARPATHY_DIR" ]]; then
  log "Refreshing andrej-karpathy-skills"
  tmp="$(mktemp -d)"
  git clone --depth 1 https://github.com/forrestchang/andrej-karpathy-skills "$tmp"
  rm -rf "$KARPATHY_DIR"
  cp -R "$tmp/skills/karpathy-guidelines" "$KARPATHY_DIR"
  cp    "$tmp/CLAUDE.md"                  "$KARPATHY_CLAUDE_MD"
  rm -rf "$tmp"
fi

#--- 5. Re-run install.sh to pick up any new tools added to the script ------
log "Re-running install.sh (idempotent)"
"$DOTFILES_DIR/install.sh"

log "Update complete. Restart your shell if PATH or hooks changed."
