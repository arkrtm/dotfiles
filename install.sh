#!/usr/bin/env bash
# install.sh — deploy ~/dotfiles into the live locations.
#   ./install.sh           apply: per-item symlink content, COPY settings.json, symlink mise config
#   ./install.sh --check   verify deployment (used by update.sh as a precheck); nonzero on drift
#
# Sync classes (see README): content=symlink, settings.json=COPY (app atomic-writes it),
# mise/config.toml=symlink (mise writes in place).
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SRC="$DOTFILES/claude"
CLAUDE_DST="$HOME/.claude"
MISE_SRC="$DOTFILES/mise/config.toml"
MISE_DST="$HOME/.config/mise/config.toml"
# Top-level items symlinked into ~/.claude/ (settings.json is handled separately = COPY).
CONTENT_ITEMS=(CLAUDE.md statusline.sh skills agents hooks commands output-styles)

c_red=$'\033[31m'; c_yel=$'\033[33m'; c_grn=$'\033[32m'; c_rst=$'\033[0m'
ok(){   printf '%s✓%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn(){ printf '%s!%s %s\n' "$c_yel" "$c_rst" "$*" >&2; }
err(){  printf '%s✗%s %s\n' "$c_red" "$c_rst" "$*" >&2; }
ts(){ date +%Y%m%d%H%M%S; }

# Back up a real (non-symlink) target FIRST, then link — avoids ln -sfn nesting into an existing dir.
link_item(){
  local name="$1" src="$CLAUDE_SRC/$1" dst="$CLAUDE_DST/$1"
  [[ -e "$src" || -L "$src" ]] || { warn "skip $name (not in repo yet)"; return; }
  if [[ -L "$dst" ]]; then
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then
    local bak="$dst.bak.$(ts)"; warn "real $name exists -> backup $bak"; mv "$dst" "$bak"
  fi
  ln -sfn "$src" "$dst"; ok "link $name"
}

copy_settings(){
  local src="$CLAUDE_SRC/settings.json" dst="$CLAUDE_DST/settings.json"
  [[ -f "$src" ]] || { warn "no settings.json in repo yet"; return; }
  mkdir -p "$CLAUDE_DST"
  if [[ -L "$dst" ]]; then
    warn "settings.json is a symlink -> $(readlink "$dst") (app would detach it); replacing with a copy"
    rm -f "$dst"
  elif [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
    local bak="$dst.bak.$(ts)"; warn "live settings.json differs; backup -> $bak (repo wins)"; cp "$dst" "$bak"
  fi
  cp "$src" "$dst"; ok "copy settings.json (repo -> live)"
}

link_mise(){
  [[ -f "$MISE_SRC" ]] || { warn "no mise/config.toml in repo"; return; }
  mkdir -p "$(dirname "$MISE_DST")"
  if [[ -L "$MISE_DST" ]]; then
    rm -f "$MISE_DST"
  elif [[ -e "$MISE_DST" ]]; then
    local bak="$MISE_DST.bak.$(ts)"; warn "real mise config exists -> backup $bak"; mv "$MISE_DST" "$bak"
  fi
  ln -sfn "$MISE_SRC" "$MISE_DST"; ok "link mise config"
}

chmod_execs(){
  [[ -f "$CLAUDE_SRC/statusline.sh" ]] && chmod +x "$CLAUDE_SRC/statusline.sh"
  local d
  for d in hooks skills; do
    [[ -d "$CLAUDE_SRC/$d" ]] && find "$CLAUDE_SRC/$d" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
  done
}

apply(){
  mkdir -p "$CLAUDE_DST"
  local n; for n in "${CONTENT_ITEMS[@]}"; do link_item "$n"; done
  copy_settings
  link_mise
  chmod_execs
  ok "install complete"
}

check(){
  local problems=0 n src dst
  for n in "${CONTENT_ITEMS[@]}"; do
    src="$CLAUDE_SRC/$n"; dst="$CLAUDE_DST/$n"
    [[ -e "$src" || -L "$src" ]] || continue   # not in repo yet — not a problem
    if [[ ! -L "$dst" ]]; then err "$n is not a symlink"; problems=$((problems+1)); continue; fi
    [[ "$(readlink "$dst")" == "$src" ]] || { err "$n -> $(readlink "$dst") (expected $src)"; problems=$((problems+1)); }
    [[ -e "$dst" ]] || { err "$n dangling symlink"; problems=$((problems+1)); }
  done
  if [[ -f "$CLAUDE_SRC/settings.json" ]]; then
    dst="$CLAUDE_DST/settings.json"
    if [[ -L "$dst" ]]; then err "settings.json is a symlink (must be a COPY)"; problems=$((problems+1))
    elif [[ ! -f "$dst" ]]; then err "settings.json not deployed"; problems=$((problems+1))
    elif ! cmp -s "$CLAUDE_SRC/settings.json" "$dst"; then err "settings.json drift (live != repo)"; problems=$((problems+1)); fi
  fi
  if [[ -f "$MISE_SRC" ]]; then
    if [[ ! -L "$MISE_DST" ]]; then err "mise config is not a symlink to the repo"; problems=$((problems+1))
    elif [[ "$(readlink "$MISE_DST")" != "$MISE_SRC" ]]; then err "mise config -> $(readlink "$MISE_DST") (expected $MISE_SRC)"; problems=$((problems+1)); fi
  fi
  if [[ "$problems" -eq 0 ]]; then ok "all checks passed"; return 0; else err "$problems problem(s)"; return 1; fi
}

case "${1:-apply}" in
  --check|check) check ;;
  apply|"")      apply ;;
  *) err "usage: install.sh [apply|--check]"; exit 2 ;;
esac
