#!/bin/sh
# handoff の受け入れ検査（ARK-90）: 偽の herdr で、herdr の外では 1（herdr を呼ばない）、中では裏の処理が自分の pane の
# エージェントが idle になるのを待って /clear を送り、clear の後の SessionStart（handoff --session-start）の印を待ってから
# 続きの指示を送ること。blocked・印が来ない・ほかの handoff が動いているときは送らない（notify）。死んだロックは回収する
#   sh tests/acceptance/handoff.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/handoff.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }
# HOME を替えると mise の shim が設定を読めないので、替える前に本物の jq の場所を PATH の先頭に入れる
PATH="$(dirname "$(mise which jq 2>/dev/null || command -v jq)"):$PATH"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID # herdr の中で走らせても本物の pane を指さない
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_STATE_HOME="$T/state" HANDOFF_TIMEOUT_MS=2000 HANDOFF_CLEAR_WAIT_S=2
mkdir -p "$HOME" "$T/bin"
LOG="$T/herdr.log"; NLOG="$XDG_STATE_HOME/agent-notify.log"
# 偽の herdr: 呼び出しを herdr.log に。agent wait は $T/wait_status（既定 idle）を返す。
# agent prompt <pane> /clear を受けたら、clear の後の SessionStart の代わりに handoff --session-start をその pane の環境で呼ぶ（$T/no_clear があれば呼ばない）
cat > "$T/bin/herdr" <<SH
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "agent wait") printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "\$(cat "$T/wait_status" 2>/dev/null || echo idle)" ;;
  "agent prompt") [ "\$4" = /clear ] && [ ! -e "$T/no_clear" ] && HERDR_ENV=1 HERDR_PANE_ID="\$3" "$ROOT/bin/handoff" --session-start </dev/null ;;
esac
exit 0
SH
chmod +x "$T/bin/herdr"
export PATH="$ROOT/bin:$T/bin:$PATH"
nlines() { cat "$NLOG" 2>/dev/null | wc -l | tr -d ' '; }
# settle: 裏の処理が結果（送った・止めた・何もしない）を handoff.log に書くまで最大 8 秒待つ
done_lines() { grep -cE '続きを送った|止めた|何もしない' "$XDG_STATE_HOME/handoff.log" 2>/dev/null || true; }
settle() { i=0; while [ "$(done_lines)" = "$1" ] && [ "$i" -lt 80 ]; do sleep 0.1; i=$((i + 1)); done; sleep 0.2; }
run() { rm -f "$LOG"; d0="$(done_lines)"; HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "ARK-1 の続き" >/dev/null 2>&1; rc=$?; settle "$d0"; }

# ---- herdr の外・使い方
handoff "x" >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$LOG" ] && grep -q '/clear' "$T/err" && ok "herdr の外では 1 で、人の /clear を促す（herdr を呼ばない）" || ng "外: rc=$rc $(cat "$T/err")"
HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff >/dev/null 2>&1; [ $? = 2 ] && ok "続きの指示が無ければ 2" || ng "引数なしが 2 でない"

# ---- 中: idle を待って /clear、clear の印の後に続きを送る
run
[ "$rc" = 0 ] && [ "$(cat "$LOG" 2>/dev/null | cut -d' ' -f1-4)" = "agent wait w1:p2 --until
agent prompt w1:p2 /clear
agent prompt w1:p2 ARK-1" ] && ok "idle を待って /clear し、clear の後に続きの指示を自分の pane に送る" || ng "中: rc=$rc log=$(cat "$LOG" 2>/dev/null)"
grep -q -- '--until idle' "$LOG" && grep -q 'ARK-1 の続き' "$LOG" && ok "続きの指示はそのまま 1 つの引数で送る" || ng "指示の渡し方: $(cat "$LOG")"
[ -s "$XDG_STATE_HOME/handoff.log" ] && ok "handoff.log に経過を残す" || ng "handoff.log が無い"

# ---- 送らないとき
echo blocked > "$T/wait_status"; n0="$(nlines)"; run
! grep -q 'agent prompt' "$LOG" && [ "$(nlines)" -gt "$n0" ] && ok "blocked なら /clear を送らず notify" || ng "blocked: $(cat "$LOG")"
rm -f "$T/wait_status"
touch "$T/no_clear"; n0="$(nlines)"; run
grep -q 'prompt w1:p2 /clear' "$LOG" && ! grep -q 'ARK-1' "$LOG" && [ "$(nlines)" -gt "$n0" ] \
  && ok "clear の印が来なければ続きを送らず notify" || ng "印なし: $(cat "$LOG")"
rm -f "$T/no_clear"
mkdir -p "$XDG_STATE_HOME/handoff-w1_p2.lock"; echo $$ > "$XDG_STATE_HOME/handoff-w1_p2.lock/pid"
rm -f "$LOG"; d0="$(done_lines)"; HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "ARK-1 の続き" >/dev/null 2>&1; settle "$d0"
! grep -q 'agent prompt' "$LOG" 2>/dev/null && ok "ほかの handoff が動いている（生きたロック）なら送らない" || ng "生きたロック: $(cat "$LOG")"
echo 999999 > "$XDG_STATE_HOME/handoff-w1_p2.lock/pid"; run
grep -q 'ARK-1' "$LOG" && ok "死んだプロセスのロックは回収して進む" || ng "死んだロック: $(cat "$LOG" 2>/dev/null)"

# ---- session-start は herdr の外では何もしない
rm -f "$XDG_STATE_HOME"/handoff-*.cleared; handoff --session-start </dev/null; [ $? = 0 ] && ! ls "$XDG_STATE_HOME"/handoff-*.cleared >/dev/null 2>&1 \
  && ok "--session-start は herdr の外では何もしない" || ng "--session-start が外で印を作った"

[ "$fail" = 0 ] && echo "acceptance handoff: ok"
[ "$fail" = 0 ]
