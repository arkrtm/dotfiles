#!/usr/bin/env bash
# Bootstrap script for a fresh macOS / Linux machine.
# Idempotent: safe to run repeatedly.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

backup_if_real() {
  # If $1 exists and is NOT already a symlink we own, move it aside.
  local target="$1"
  if [[ -e "$target" && ! -L "$target" ]]; then
    local bak="${target}.bak.$(date +%Y%m%d%H%M%S)"
    warn "Backing up existing $target -> $bak"
    mv "$target" "$bak"
  fi
}

link() {
  # link SRC DEST  — create symlink DEST -> SRC, replacing existing symlinks.
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  backup_if_real "$dest"
  ln -sfn "$src" "$dest"
  log "Linked $dest -> $src"
}

#--- 1. uv (Python package manager) -----------------------------------------
if ! have uv; then
  log "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  log "uv already installed ($(uv --version))"
fi

#--- 2. rtk (Rust Token Killer, Claude Code context compressor) -------------
if ! have rtk; then
  log "Installing rtk"
  if [[ "$OS" == "Darwin" ]] && have brew; then
    brew install rtk || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  else
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  fi
else
  log "rtk already installed"
fi

#--- 3. Claude Code config directory ----------------------------------------
mkdir -p "$HOME/.claude/skills"

#--- 4. Symlink tracked Claude settings -------------------------------------
# Symlinking BEFORE claude-mem / rtk init means their automatic edits land
# in the dotfiles repo, where we can review and commit them.
link "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
link "$DOTFILES_DIR/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"

#--- 5. Karpathy CLAUDE.md (auto-load via @-import) -------------------------
# The skill itself is installed by Claude Code's plugin system (declared in
# settings.json's `enabledPlugins`). The repo's root CLAUDE.md is NOT a plugin
# asset, so we fetch it manually for ~/.claude/CLAUDE.md to @-import.
KARPATHY_CLAUDE_MD="$HOME/.claude/karpathy-CLAUDE.md"
if [[ ! -f "$KARPATHY_CLAUDE_MD" ]]; then
  log "Fetching karpathy CLAUDE.md (for @-import auto-load)"
  curl -fsSL -o "$KARPATHY_CLAUDE_MD" \
    https://raw.githubusercontent.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md
else
  log "karpathy CLAUDE.md already present"
fi

# NOTE: andrej-karpathy-skills (skill) and claude-mem (memory hooks) are
# installed declaratively by Claude Code on next launch, via
# `extraKnownMarketplaces` + `enabledPlugins` in claude/settings.json.
# No shell-side install required.

#--- 6. rtk init (registers Claude Code hook + writes ~/.claude/RTK.md) -----
if have rtk; then
  log "Running rtk init -g"
  rtk init -g || warn "rtk init -g failed; continue manually"
fi

log "Done. Restart your shell to pick up PATH / shell hook changes."
