#!/usr/bin/env bash
set -uo pipefail
input=$(cat)
jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
model=$(jqr '.model.display_name // "?"')
eff=$(jqr '.effort.level // empty')                # reasoning effort (ultracode reports as xhigh); absent if unsupported
proj=$(jqr '.workspace.project_dir // .workspace.current_dir // .cwd // empty')   # dir the session was opened in
cwd=$(jqr '.workspace.current_dir // .cwd // empty')
ctx=$(jqr '.context_window.used_percentage // empty')
[ -z "$model" ] && model="?"                       # S2: fail-open to ?
dir=""                                             # ~-abbreviated session dir
case "$proj" in "$HOME") dir="~" ;; "$HOME"/*) dir="~${proj#"$HOME"}" ;; ?*) dir="$proj" ;; esac
branch=""; [ -n "$cwd" ] && branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
venv=""
if [ -n "${VIRTUAL_ENV:-}" ]; then venv=$(basename "$VIRTUAL_ENV")
elif [ -n "$cwd" ] && [ -d "$cwd/.venv" ]; then venv=".venv"; fi
DIM=$'\033[2m'; RST=$'\033[0m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'; MAG=$'\033[35m'; BLU=$'\033[34m'
out="${CYN}${model}${RST}"
[ -n "$eff" ] && out+="${DIM} | ${RST}${MAG}eff ${eff}${RST}"
[ -n "$dir" ] && out+="${DIM} | ${RST}${BLU}${dir}${RST}"
if [ -n "$ctx" ]; then
  ctxi=${ctx%%.*}; c=$GRN                            # S1: integer-ize float percentage
  [ "${ctxi:-0}" -ge 50 ] && c=$YEL
  [ "${ctxi:-0}" -ge 80 ] && c=$RED
  out+="${DIM} | ${RST}${c}ctx ${ctxi}%${RST}"
fi
[ -n "$branch" ] && out+="${DIM} | ${RST}${branch}"
[ -n "$venv" ] && out+="${DIM} | ${RST}venv ${venv}"
printf '%s' "$out"
