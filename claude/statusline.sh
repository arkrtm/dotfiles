#!/usr/bin/env bash
set -uo pipefail
input=$(cat)
jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
model=$(jqr '.model.display_name // "?"')
cwd=$(jqr '.workspace.current_dir // .cwd // empty')
ctx=$(jqr '.context_window.used_percentage // empty')
[ -z "$model" ] && model="?"                       # S2: fail-open to ?
branch=""; [ -n "$cwd" ] && branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
venv=""
if [ -n "${VIRTUAL_ENV:-}" ]; then venv=$(basename "$VIRTUAL_ENV")
elif [ -n "$cwd" ] && [ -d "$cwd/.venv" ]; then venv=".venv"; fi
DIM=$'\033[2m'; RST=$'\033[0m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'
out="${CYN}${model}${RST}"
if [ -n "$ctx" ]; then
  ctxi=${ctx%%.*}; c=$GRN                            # S1: integer-ize float percentage
  [ "${ctxi:-0}" -ge 50 ] && c=$YEL
  [ "${ctxi:-0}" -ge 80 ] && c=$RED
  out+="${DIM} | ${RST}${c}ctx ${ctxi}%${RST}"
fi
[ -n "$branch" ] && out+="${DIM} | ${RST}${branch}"
[ -n "$venv" ] && out+="${DIM} | ${RST}venv ${venv}"
printf '%s' "$out"
