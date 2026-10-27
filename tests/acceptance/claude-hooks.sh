#!/bin/sh
# notify の受け入れ検査: 一時 HOME で、notify は標準エラーとログに 1 行。
# check.sh・fmt.sh のフックはやめた
#   sh tests/acceptance/claude-hooks.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/claude-hooks.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
export HOME="$T/home" XDG_STATE_HOME="$T/state"
mkdir -p "$HOME/.local/bin"
ln -s "$ROOT/bin/notify" "$HOME/.local/bin/notify"
LOG="$XDG_STATE_HOME/agent-notify.log"
lines() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }

# ---- notify
err="$("$HOME/.local/bin/notify" hello world 2>&1 >/dev/null)"
[ "$err" = "hello world" ] && ok "notify は標準エラーにメッセージを出す" || ng "notify の標準エラー: $err"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} hello world$' "$LOG" 2>/dev/null && [ "$(lines)" = 1 ] \
  && ok "notify はログに日時つきで 1 行追記する" || ng "notify のログ: $(cat "$LOG" 2>/dev/null)"

[ "$fail" = 0 ] && echo "acceptance claude-hooks: ok"
[ "$fail" = 0 ]
