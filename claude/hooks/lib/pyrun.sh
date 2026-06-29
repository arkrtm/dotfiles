#!/usr/bin/env bash
# pyrun.sh — print the command prefix for running a Python tool.
# Inside a uv project: `uv run --no-sync <tool>` (project-pinned).
# Outside a project:   `uvx <tool>` (works on .py files outside any uv project).
#   read -r -a RUFF <<<"$("$LIB/pyrun.sh" ruff)"; "${RUFF[@]}" check --fix "$f"
set -uo pipefail
tool="${1:?usage: pyrun.sh <tool>}"
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/uv.lock" ]; then
  printf 'uv run --no-sync %s' "$tool"
else
  printf 'uvx %s' "$tool"
fi
