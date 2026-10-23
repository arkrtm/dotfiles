#!/bin/sh
# handoff の受け入れ検査（ARK-90）: 偽の herdr で、herdr の外では 1（herdr を呼ばない）、中では裏の処理が自分の pane の
# エージェントが idle になるのを待って /clear を送り、clear の後の SessionStart（handoff --session-start）の印を待ってから
# 続きの指示を送ること。blocked・印が来ない・ほかの handoff が動いているときは送らない（notify）。ロックは持ち主が消えたら外れる
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
  "agent wait") [ -e "$T/wait_sleep" ] && sleep 1
    # $T/switch があれば、待っている間に人が同じ pane で /clear・/resume した（SessionStart が走った）ことにする
    [ -e "$T/switch" ] && HERDR_ENV=1 HERDR_PANE_ID="\$3" "$ROOT/bin/handoff" --session-start </dev/null
    printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "\$(cat "$T/wait_status" 2>/dev/null || echo idle)" ;;
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
# ロックはカーネルのファイルロック（flock）: ほかの処理が持っている間は送らず、持ち主が消えたら自動で外れる
if command -v flock >/dev/null 2>&1; then
  L="$XDG_STATE_HOME/handoff-w1_p2.lock"; mkdir -p "$XDG_STATE_HOME"
  (exec 9>>"$L"; flock 9; sleep 30) & holder=$!; sleep 0.3
  rm -f "$LOG"; d0="$(done_lines)"; HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "ARK-1 の続き" >/dev/null 2>&1; settle "$d0"
  ! grep -q 'agent prompt' "$LOG" 2>/dev/null && ok "ほかの handoff がロックを持っている間は送らない" || ng "ロック中: $(cat "$LOG")"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; run
  grep -q 'ARK-1' "$LOG" && ok "持ち主が消えたらロックは外れ、次の handoff は進む" || ng "持ち主が消えた後: $(cat "$LOG" 2>/dev/null)"
fi
# 同時に 2 つ呼んでも /clear は 1 回だけ（1 本目が待っている間に 2 本目が来る）
touch "$T/wait_sleep"; rm -f "$LOG"; d0="$(done_lines)"
for x in 1 2; do HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "ARK-1 の続き" >/dev/null 2>&1; done
i=0; while [ "$(done_lines)" -lt $((d0 + 2)) ] && [ "$i" -lt 80 ]; do sleep 0.1; i=$((i + 1)); done; sleep 0.2
[ "$(grep -c 'prompt w1:p2 /clear' "$LOG")" = 1 ] && ok "同時に 2 つ呼んでも /clear は 1 回" || ng "二重: $(cat "$LOG")"
rm -f "$T/wait_sleep"

# 待っている間にセッションが替わったら（同じ pane で SessionStart）、替わった後の会話に /clear も続きも送らない
touch "$T/switch"; n0="$(nlines)"; run
! grep -q 'agent prompt' "$LOG" && [ "$(nlines)" -gt "$n0" ] && ok "待っている間にセッションが替わったら取り消して notify" || ng "切り替え: $(cat "$LOG")"
rm -f "$T/switch"

# ---- session-start は herdr の外では何もしない
rm -f "$XDG_STATE_HOME"/handoff-*.cleared; handoff --session-start </dev/null; [ $? = 0 ] && ! ls "$XDG_STATE_HOME"/handoff-*.cleared >/dev/null 2>&1 \
  && ok "--session-start は herdr の外では何もしない" || ng "--session-start が外で印を作った"

[ "$fail" = 0 ] && echo "acceptance handoff: ok"
[ "$fail" = 0 ]
