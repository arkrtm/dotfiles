#!/bin/sh
# Claude Code のフックと notify の受け入れ検査（ARK-86）: 一時 HOME で、
# notify は標準エラーとログに 1 行、check.sh（Stop）は scripts/check が無ければ 0・失敗で 2・同じセッションで 3 回目は止めて notify・成功で回数が戻る、
# fmt.sh（PostToolUse）は scripts/fmt があればファイルを渡して呼び、無い・空入力では何もしない。フックは入力の cwd で scripts/ を探す
#   sh tests/acceptance/claude-hooks.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/claude-hooks.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_STATE_HOME="$T/state"
mkdir -p "$HOME/.local/bin" "$T/repo/scripts" "$T/elsewhere"
ln -s "$ROOT/bin/notify" "$HOME/.local/bin/notify"
LOG="$XDG_STATE_HOME/agent-notify.log"
CHECK="$ROOT/config/claude/hooks/check.sh"; FMT="$ROOT/config/claude/hooks/fmt.sh"
lines() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
cd "$T/elsewhere" # フックは Claude Code の cwd でなく入力の cwd を見る

# ---- notify
err="$("$HOME/.local/bin/notify" hello world 2>&1 >/dev/null)"
[ "$err" = "hello world" ] && ok "notify は標準エラーにメッセージを出す" || ng "notify の標準エラー: $err"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} hello world$' "$LOG" 2>/dev/null && [ "$(lines)" = 1 ] \
  && ok "notify はログに日時つきで 1 行追記する" || ng "notify のログ: $(cat "$LOG" 2>/dev/null)"

# ---- check.sh
stop() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$2" | sh "$CHECK" 2>"$T/err"; }
stop s0 "$T/elsewhere"; [ $? = 0 ] && ok "check.sh: scripts/check が無ければ 0" || ng "check.sh: scripts/check が無いのに 0 でない"
printf '#!/bin/sh\necho boom; exit 1\n' > "$T/repo/scripts/check"; chmod +x "$T/repo/scripts/check"
stop s1 "$T/repo"; rc=$?
[ "$rc" = 2 ] && grep -q boom "$T/err" && ok "check.sh: 失敗すると 2 で検査の出力を標準エラーに" || ng "check.sh の失敗 1 回目: rc=$rc err=$(cat "$T/err")"
stop s1 "$T/repo"; [ $? = 2 ] && ok "check.sh: 2 回目の失敗も 2" || ng "check.sh: 2 回目の失敗が 2 でない"
n0="$(lines)"; stop s1 "$T/repo"; rc=$?
[ "$rc" = 0 ] && [ "$(lines)" = $((n0 + 1)) ] && ok "check.sh: 3 回目の失敗で止めて notify する" || ng "check.sh の 3 回目: rc=$rc ログ $n0 → $(lines)"
stop s1 "$T/repo"; [ $? = 2 ] && ok "check.sh: 止めた後は数え直す" || ng "check.sh: 止めた後の失敗が 2 でない"
# 成功で回数が戻る: 失敗 1（上）→ 成功 → 失敗 2 回はどちらも 2
printf '#!/bin/sh\nexit 0\n' > "$T/repo/scripts/check"
stop s1 "$T/repo"; [ $? = 0 ] && ok "check.sh: 成功すると 0" || ng "check.sh: 成功なのに 0 でない"
printf '#!/bin/sh\necho boom; exit 1\n' > "$T/repo/scripts/check"
stop s1 "$T/repo"; a=$?; stop s1 "$T/repo"; b=$?
[ "$a" = 2 ] && [ "$b" = 2 ] && ok "check.sh: 成功すると失敗の回数が戻る" || ng "check.sh: 成功の後の失敗 2 回が $a $b"
stop s2 "$T/repo"; [ $? = 2 ] && ok "check.sh: 回数はセッションごと" || ng "check.sh: 別セッションの 1 回目が 2 でない"

# ---- fmt.sh
printf '#!/bin/sh\necho "$1" > "%s"\n' "$T/fmt-arg" > "$T/repo/scripts/fmt"; chmod +x "$T/repo/scripts/fmt"
printf '{"cwd":"%s","tool_input":{"file_path":"x"}}' "$T/repo" | sh "$FMT"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$T/fmt-arg" 2>/dev/null)" = x ] && ok "fmt.sh: scripts/fmt にファイルを渡して呼ぶ" || ng "fmt.sh: rc=$rc 引数=$(cat "$T/fmt-arg" 2>/dev/null)"
rm -f "$T/fmt-arg"
printf '{"cwd":"%s","tool_input":{"file_path":"x"}}' "$T/elsewhere" | sh "$FMT"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/fmt-arg" ] && ok "fmt.sh: scripts/fmt が無ければ何もせず 0" || ng "fmt.sh: scripts/fmt が無いとき rc=$rc"
printf '' | sh "$FMT"; [ $? = 0 ] && ok "fmt.sh: 空の入力でも 0" || ng "fmt.sh: 空の入力で 0 でない"

[ "$fail" = 0 ] && echo "acceptance claude-hooks: ok"
[ "$fail" = 0 ]
