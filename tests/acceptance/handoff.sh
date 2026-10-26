#!/bin/sh
# handoff の受け入れ検査: 偽の herdr で、herdr の外では 1（herdr を呼ばない）、中では裏の処理が自分の pane の
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
    [ -e "$T/wait_long" ] && { sleep 30 & echo \$! > "$T/sleeppid"; wait; }
    # $T/switch があれば、待っている間に人が同じ pane で /clear・/resume した（SessionStart が走った）ことにする
    [ -e "$T/switch" ] && echo '{"source":"resume"}' | HERDR_ENV=1 HERDR_PANE_ID="\$3" "$ROOT/bin/handoff" --session-start
    printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "\$(cat "$T/wait_status" 2>/dev/null || echo idle)" ;;
  "agent prompt") [ "\$4" = /clear ] && [ -e "$T/resume_before_clear" ] && echo '{"source":"resume"}' | HERDR_ENV=1 HERDR_PANE_ID="\$3" "$ROOT/bin/handoff" --session-start
    [ "\$4" = /clear ] && [ ! -e "$T/no_clear" ] && echo "{\"source\":\"\$(cat "$T/after_clear" 2>/dev/null || echo clear)\"}" | HERDR_ENV=1 HERDR_PANE_ID="\$3" "$ROOT/bin/handoff" --session-start ;;
esac
exit 0
SH
chmod +x "$T/bin/herdr"
export PATH="$ROOT/bin:$T/bin:$PATH"
nlines() { cat "$NLOG" 2>/dev/null | wc -l | tr -d ' '; }
# settle: 裏の処理が結果（送った・止めた・何もしない）を handoff.log に書くまで最大 8 秒待つ
done_lines() { grep -cE '続きを送った|止めた|何もしない' "$XDG_STATE_HOME/handoff.log" 2>/dev/null || true; }
settle() { i=0; while [ "$(done_lines)" = "$1" ] && [ "$i" -lt 80 ]; do sleep 0.1; i=$((i + 1)); done; sleep 0.2; }
run() { rm -f "$LOG"; d0="$(done_lines)"; HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "前の作業の続き" >/dev/null 2>&1; rc=$?; settle "$d0"; }

# ---- herdr の外・使い方
handoff "x" >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$LOG" ] && grep -q '/clear' "$T/err" && ok "herdr の外では 1 で、人の /clear を促す（herdr を呼ばない）" || ng "外: rc=$rc $(cat "$T/err")"
HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff >/dev/null 2>&1; [ $? = 2 ] && ok "続きの指示が無ければ 2" || ng "引数なしが 2 でない"

# ---- 中: idle を待って /clear、clear の印の後に続きを送る
run
[ "$rc" = 0 ] && [ "$(cat "$LOG" 2>/dev/null | cut -d' ' -f1-4)" = "agent wait w1:p2 --until
agent prompt w1:p2 /clear
agent prompt w1:p2 [handoff" ] && ok "idle を待って /clear し、clear の後に続きの指示を自分の pane に送る" || ng "中: rc=$rc log=$(cat "$LOG" 2>/dev/null)"
grep -q -- '--until idle' "$LOG" && grep -q '前の作業の続き' "$LOG" && ok "続きの指示はそのまま 1 つの引数で送る" || ng "指示の渡し方: $(cat "$LOG")"
[ -s "$XDG_STATE_HOME/handoff.log" ] && ok "handoff.log に経過を残す" || ng "handoff.log が無い"

# ---- 送らないとき
echo blocked > "$T/wait_status"; n0="$(nlines)"; run
! grep -q 'agent prompt' "$LOG" && [ "$(nlines)" -gt "$n0" ] && ok "blocked なら /clear を送らず notify" || ng "blocked: $(cat "$LOG")"
rm -f "$T/wait_status"
touch "$T/no_clear"; n0="$(nlines)"; run
grep -q 'prompt w1:p2 /clear' "$LOG" && ! grep -q '前の作業の続き' "$LOG" && [ "$(nlines)" -gt "$n0" ] \
  && ok "clear の印が来なければ続きを送らず notify" || ng "印なし: $(cat "$LOG")"
rm -f "$T/no_clear"
# ロックはカーネルのファイルロック（flock）: ほかの処理が持っている間は送らず、持ち主が消えたら自動で外れる
if command -v flock >/dev/null 2>&1; then
  L="$XDG_STATE_HOME/handoff-w1_p2.lock"; mkdir -p "$XDG_STATE_HOME"
  (exec 9>>"$L"; flock 9; sleep 30) & holder=$!; sleep 0.3
  rm -f "$LOG"; d0="$(done_lines)"; HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "前の作業の続き" >/dev/null 2>&1; settle "$d0"
  ! grep -q 'agent prompt' "$LOG" 2>/dev/null && ok "ほかの handoff がロックを持っている間は送らない" || ng "ロック中: $(cat "$LOG")"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; run
  grep -q '前の作業の続き' "$LOG" && ok "持ち主が消えたらロックは外れ、次の handoff は進む" || ng "持ち主が消えた後: $(cat "$LOG" 2>/dev/null)"
fi
# 同時に 2 つ呼んでも /clear は 1 回だけ（1 本目が待っている間に 2 本目が来る）
touch "$T/wait_sleep"; rm -f "$LOG"; d0="$(done_lines)"
for x in 1 2; do HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "前の作業の続き" >/dev/null 2>&1; done
i=0; while [ "$(done_lines)" -lt $((d0 + 2)) ] && [ "$i" -lt 80 ]; do sleep 0.1; i=$((i + 1)); done; sleep 0.2
[ "$(grep -c 'prompt w1:p2 /clear' "$LOG")" = 1 ] && ok "同時に 2 つ呼んでも /clear は 1 回" || ng "二重: $(cat "$LOG")"
rm -f "$T/wait_sleep"

# 待っている間にセッションが替わったら（同じ pane で SessionStart）、替わった後の会話に /clear も続きも送らない
touch "$T/switch"; n0="$(nlines)"; run
! grep -q 'agent prompt' "$LOG" && [ "$(nlines)" -gt "$n0" ] && ok "待っている間にセッションが替わったら取り消して notify" || ng "切り替え: $(cat "$LOG")"
rm -f "$T/switch"

# /clear の確認を待つ間に別の理由（resume・fork）で SessionStart が来たら、続きを送らない
for src in resume fork; do
  echo "$src" > "$T/after_clear"; n0="$(nlines)"; run
  grep -q 'prompt w1:p2 /clear' "$LOG" && ! grep -q '前の作業の続き' "$LOG" && [ "$(nlines)" -gt "$n0" ] \
    && ok "clear の確認の代わりに $src が来たら続きを送らず notify" || ng "clear の代わりに $src: $(cat "$LOG")"
done
rm -f "$T/after_clear"
# 印を確かめた直後・/clear の直前に人が /resume した（印に resume と clear が並ぶ）ときも続きを送らない
touch "$T/resume_before_clear"; run
! grep -q '前の作業の続き' "$LOG" && ok "/clear の直前に /resume が挟まったら続きを送らない" || ng "直前の resume: $(cat "$LOG")"
rm -f "$T/resume_before_clear"
# 裏の処理が herdr を待っている間に死んでも、待っている子がロックを持ち続けない（止めるのは検査が起こしたプロセスだけ）
touch "$T/wait_long"; rm -f "$LOG" "$T/sleeppid"; HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "前の作業の続き" >/dev/null 2>&1
i=0; while [ ! -s "$T/sleeppid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
wpid="$(sed -n 's/.*開始 pid=\([0-9]*\).*/\1/p' "$XDG_STATE_HOME/handoff.log" | tail -n 1)"
kill "$wpid" 2>/dev/null; sleep 0.3; rm -f "$T/wait_long"; run
grep -q '前の作業の続き' "$LOG" && ok "裏の処理が死んだら、待っていた子が残っていてもロックは外れる" || ng "子がロックを持ったまま: $(cat "$LOG" 2>/dev/null)"
kill "$(cat "$T/sleeppid" 2>/dev/null)" 2>/dev/null

# 合言葉: 続きの指示に id を付け、自分たちが起こした clear の SessionStart だけがその id を会話に入れる
id="$(sed -n 's/^agent prompt w1:p2 \[handoff \([^]]*\)\].*/\1/p' "$LOG")"
[ -n "$id" ] && grep -q "handoff $id の続きの指示が.*届く」という案内が無ければ" "$LOG" && ok "続きの指示に合言葉と、案内が無いときは従わない旨を付ける" || ng "合言葉: $(tail -n 1 "$LOG")"
mkdir -p "$XDG_STATE_HOME"; echo 123-9 > "$XDG_STATE_HOME/handoff-w1_p2.pending"
out="$(echo '{"source":"resume"}' | HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff --session-start)"
[ -z "$out" ] && ok "resume の SessionStart は合言葉を入れない（使い切りもしない）" || ng "resume の案内: $out"
out="$(echo '{"source":"clear"}' | HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff --session-start)"
printf '%s' "$out" | grep -q 'handoff 123-9' && ok "待っている handoff の clear の SessionStart は合言葉を会話に入れる" || ng "clear の案内: $out"
out="$(echo '{"source":"clear"}' | HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff --session-start)"
[ -z "$out" ] && ok "合言葉は最初の clear で使い切り、次の clear には入れない" || ng "2 回目の clear: $out"
[ ! -e "$XDG_STATE_HOME/handoff-w1_p2.pending" ] && ok "送った後は待ちの印を残さない" || ng "pending が残った"

# 呼んだ直後（裏の処理が始まる前）に人が /resume しても取り消す
rm -f "$LOG"; d0="$(done_lines)"; n0="$(nlines)"; touch "$T/wait_sleep"
HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff "前の作業の続き" >/dev/null 2>&1
echo '{"source":"resume"}' | HERDR_ENV=1 HERDR_PANE_ID=w1:p2 handoff --session-start >/dev/null; settle "$d0"; rm -f "$T/wait_sleep"
! grep -q 'agent prompt' "$LOG" && [ "$(nlines)" -gt "$n0" ] && ok "呼んだ直後の /resume でも取り消す" || ng "直後の resume: $(cat "$LOG")"

# ---- session-start は herdr の外では何もしない
rm -f "$XDG_STATE_HOME"/handoff-*.cleared; echo '{"source":"clear"}' | handoff --session-start; [ $? = 0 ] && ! ls "$XDG_STATE_HOME"/handoff-*.cleared >/dev/null 2>&1 \
  && ok "--session-start は herdr の外では何もしない" || ng "--session-start が外で印を作った"

[ "$fail" = 0 ] && echo "acceptance handoff: ok"
[ "$fail" = 0 ]
