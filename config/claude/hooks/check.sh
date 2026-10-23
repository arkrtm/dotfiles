#!/bin/sh
# Claude Code の Stop フック: リポジトリの scripts/check を実行し、失敗したら終了コード 2 で Claude に作業を続けさせる。
# 同じセッションで 3 回続けて失敗したら止めて notify で知らせる（上限を使い切らないように）
input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && cd "$cwd" || exit 0
[ -x scripts/check ] || exit 0
state="${XDG_STATE_HOME:-$HOME/.local/state}/agent-check/$sid"
mkdir -p "$(dirname "$state")"

if out="$(scripts/check 2>&1)"; then rm -f "$state"; exit 0; fi

n=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
if [ "$n" -ge 3 ]; then
  rm -f "$state"
  "$HOME/.local/bin/notify" "検査が 3 回続けて失敗したので止めました: $(basename "$PWD")"
  exit 0
fi
echo "$n" > "$state"
printf '%s\n' "$out" | tail -n 40 >&2
exit 2
