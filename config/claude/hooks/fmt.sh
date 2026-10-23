#!/bin/sh
# Claude Code の PostToolUse フック（Edit|Write）: リポジトリの scripts/fmt で編集したファイルを整形する。失敗しても Claude の操作は止めない
input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$file" ] && [ -n "$cwd" ] && cd "$cwd" && [ -x scripts/fmt ] || exit 0
scripts/fmt "$file" >/dev/null 2>&1
exit 0
