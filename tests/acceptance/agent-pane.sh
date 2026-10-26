#!/bin/sh
# agent-pane の受け入れ検査: 偽の herdr で、herdr の中ではサブエージェントの開始で pane を分けて view を動かし
# （1 つ目はメインを右に半分ずつ、2・3 つ目は右の列のいちばん下を下に分ける。同時に 3 つまで。workflow のエージェントでは開かない。
# 同じエージェントの再通知・並行の開始でも上限を守る）、終了で閉じること。開いたとき・閉じたときに右の列の高さをそろえること。
# 消えた pane・中断で finished のものは数えず閉じ、cleanup はすべて閉じること。herdr の外では何もしないこと。
# view は記録（jsonl）の文とツールの呼び出しを 1 行ずつ出すこと
#   sh tests/acceptance/agent-pane.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/agent-pane.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID # herdr の中で走らせても本物の pane を触らない
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export XDG_STATE_HOME="$T/state"
mkdir -p "$T/bin" "$T/live" "$T/proj/s1/subagents"
LOG="$T/herdr.log"
# 偽の herdr: split は新しい pane（w1:p<連番。使い回さない>）を live に作り、get は live にあれば 0、close は live から消す。
# layout は $T/layout.json があればそれ、無ければ live の pane を開いた順に上から並べる（分割の情報は無し）。$T/split_fail があれば split は失敗
cat > "$T/bin/herdr" <<SH
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "pane run") [ -e "$T/run_fail" ] && exit 1 ;;
  "pane split") [ -e "$T/split_fail" ] && exit 1; n=\$(( \$(cat "$T/seq" 2>/dev/null || echo 9) + 1 )); echo "\$n" > "$T/seq"; touch "$T/live/w1:p\$n"; printf '{"result":{"pane":{"pane_id":"w1:p%s"}}}\n' "\$n" ;;
  "pane layout") [ -e "$T/layout_fail" ] && exit 1
    if [ -e "$T/layout.json" ]; then cat "$T/layout.json"; else ls "$T/live" | sort -t p -k 2 -n |
    jq -Rnc '{result: {layout: {panes: ([inputs] | to_entries | map({pane_id: .value, rect: {x: 75, y: (.key * 10), width: 75, height: 10}})), splits: []}}}'; fi ;;
  "pane get"|"pane close")
    # $T/broken があれば通信の失敗（pane_not_found 以外のエラー）
    [ -e "$T/broken" ] && { echo '{"error":{"code":"server_unavailable"}}'; exit 1; }
    [ -e "$T/live/\$3" ] || { echo '{"error":{"code":"pane_not_found"}}'; exit 1; }
    [ "\$2" = close ] && rm -f "$T/live/\$3" ;;
esac
exit 0
SH
chmod +x "$T/bin/herdr"
export PATH="$ROOT/bin:$T/bin:$PATH"
in_herdr() { HERDR_ENV=1 HERDR_PANE_ID=w1:p1 "$@"; }
ev() { printf '{"session_id":"s1","transcript_path":"%s/proj/s1.jsonl","cwd":"%s","agent_id":"%s","agent_type":"%s"}' "$T" "$T" "$1" "${2:-general-purpose}"; }
start() { ev "$@" | in_herdr agent-pane start; }
stop() { ev "$1" | in_herdr agent-pane stop; }
splits() { grep -c '^pane split' "$LOG" 2>/dev/null || true; }
reset() { rm -rf "$LOG" "$XDG_STATE_HOME" "$T/live"/* "$T/seq" "$T/layout.json" "$T/layout_fail" "$T/split_fail"; }

# ---- herdr の外では何もしない
ev a1 | agent-pane start; [ $? = 0 ] && [ ! -e "$LOG" ] && ok "herdr の外では何もしない" || ng "外で herdr を呼んだ"

# ---- 開始で pane を分けて view、上限 3
start a1; start a2; start a3
[ "$(splits)" = 3 ] && [ "$(grep -c '^pane run' "$LOG")" = 3 ] && ok "開始で pane を分けて view を動かす" || ng "開始: $(cat "$LOG")"
[ "$(grep '^pane split' "$LOG" | sed -n 1p)" = "pane split --pane w1:p1 --direction right --ratio 0.5 --no-focus --cwd $T" ] \
  && ok "1 つ目はメインを右に半分ずつで分ける（フォーカスは移さない）" || ng "1 つ目の分け方: $(cat "$LOG")"
[ "$(grep '^pane split' "$LOG" | sed -n '2,3p' | tr '\n' '|')" = "pane split --pane w1:p10 --direction down --no-focus --cwd $T|pane split --pane w1:p11 --direction down --no-focus --cwd $T|" ] \
  && ! grep -q '^pane swap' "$LOG" && ok "2・3 つ目は右の列のいちばん下のサブの pane を下に分ける（メインは分けず、入れ替えない）" || ng "2・3 つ目の分け方: $(cat "$LOG")"
grep -q "pane run w1:p10 agent-pane view '$T/proj/s1/subagents/agent-a1.jsonl'" "$LOG" && ok "view にサブエージェントの記録のパスを渡す" || ng "view の引数: $(grep 'pane run' "$LOG")"
start a4; [ "$(splits)" = 3 ] && ok "同時に 3 つを超えたら開かない（バックグラウンドのまま）" || ng "上限: $(splits)"
start a1; [ "$(splits)" = 3 ] && ok "同じエージェントの再通知では開かない" || ng "再通知で開いた"
stop a1; ! [ -e "$T/live/w1:p10" ] && grep -q '^pane close w1:p10' "$LOG" && ok "終了でその pane を閉じる" || ng "終了: $(cat "$LOG")"
start a5; [ "$(splits)" = 4 ] && grep -q "^pane split --pane w1:p12 --direction down --no-focus --cwd $T\$" "$LOG" \
  && ok "閉じた分だけまた開ける（いちばん上が閉じても、いちばん下を分ける）" || ng "閉じた後: $(cat "$LOG")"
rm -f "$T/live/w1:p11"; start a2; [ "$(splits)" = 5 ] && grep -q "^pane split --pane w1:p13 --direction down" "$LOG" \
  && ok "人が閉じた pane は、同じエージェントの再通知で開き直す（閉じた pane でなく、いちばん下を分ける）" || ng "開き直し: $(cat "$LOG")"
# layout が読めなければ（通信の失敗）2 つ目からは開かない（メインを分けない）。再通知で開ける
reset; start k1; touch "$T/layout_fail"; start k2; rm -f "$T/layout_fail"
[ "$(splits)" = 1 ] && [ ! -e "$XDG_STATE_HOME/agent-pane/w1_p1/k2" ] && ok "layout が読めなければ 2 つ目は開かない" || ng "layout の失敗: $(cat "$LOG")"
start k2; [ "$(splits)" = 2 ] && ok "layout が読めるようになった後の再通知で開く" || ng "layout の失敗の後: $(splits)"

# ---- 右の列の高さをそろえる: 開いたとき・閉じたときに、herdr の layout から上から k 番目（0 から）の境界の分割の割合を 1/(n-k) に resize で動かす
lay() { printf '{"result":{"layout":{"panes":[%s],"splits":[%s]}}}\n' "$1" "$2" > "$T/layout.json"; }
pn() { printf '{"pane_id":"w1:p%s","rect":{"x":221,"y":%s,"width":73,"height":%s}}' "$1" "$2" "$3"; }
sp() { printf '{"direction":"down","ratio":%s,"rect":{"x":221,"y":%s,"width":73,"height":%s}}' "$1" "$2" "$3"; }
reset; start r1; start r2
lay "$(pn 10 0 30),$(pn 11 30 15),$(pn 12 45 14)" "$(sp 0.5 0 59),$(sp 0.5 30 29)" # 本物の herdr で 3 つ目を開いた直後（30・15・14 行）
start r3
grep -q "^pane split --pane w1:p11 --direction down" "$LOG" && grep -q '^pane resize --pane w1:p11 --direction up --amount 0\.1666' "$LOG" \
  && [ "$(grep -c '^pane resize' "$LOG")" = 1 ] && ok "開いたら右の列の高さをそろえる（いちばん上の境界を 3 分の 1 に）" || ng "開いたときのそろえ: $(grep '^pane' "$LOG")"
lay "$(pn 10 0 20),$(pn 12 20 39)" "$(sp 0.3333333 0 59)" # 真ん中を閉じた直後（20・39 行）
stop r2
grep -q '^pane resize --pane w1:p10 --direction down --amount 0\.1666' "$LOG" && [ "$(grep -c '^pane resize' "$LOG")" = 2 ] \
  && ok "閉じたら残りの高さをそろえる" || ng "閉じたときのそろえ: $(grep '^pane resize' "$LOG")"
# 人が境界を 0.9 まで動かした後に 3 つ目を開いた直後（53・3・3 行）: 動かす量 0.5667 を herdr の 1 回の上限 0.5 以下に分けて送る
reset; start u1; start u2
lay "$(pn 10 0 53),$(pn 11 53 3),$(pn 12 56 3)" "$(sp 0.9 0 59),$(sp 0.5 53 6)"
start u3
[ "$(grep '^pane resize' "$LOG" | sed 's/\(--amount [0-9.]\{1,6\}\).*/\1/' | tr '\n' '|')" = "pane resize --pane w1:p11 --direction up --amount 0.5|pane resize --pane w1:p11 --direction up --amount 0.0666|" ] \
  && ok "1 回に 0.5 を超えて動かす分は分けて resize する" || ng "上限を超える resize: $(grep '^pane resize' "$LOG")"
# 右の列が 24 行で同じく 0.9 から 3 つ目を開いた直後（22・1・1 行）: 1 行の pane が続いて隣の境界も ±1 行に入っても、下の境界に上の割合を使わない
reset; start t1; start t2
lay "$(pn 10 0 22),$(pn 11 22 1),$(pn 12 23 1)" "$(sp 0.9 0 24),$(sp 0.5 22 2)"
start t3
[ "$(grep '^pane resize' "$LOG" | sed 's/\(--amount [0-9.]\{1,6\}\).*/\1/' | tr '\n' '|')" = "pane resize --pane w1:p11 --direction up --amount 0.5|pane resize --pane w1:p11 --direction up --amount 0.0666|" ] \
  && ok "1 行の pane が続いても、境界ごとにいちばん近い分割の割合を使う" || ng "1 行の pane の境界: $(grep '^pane resize' "$LOG")"
# 開く前に finished の pane を閉じ（回収）、その後の分割に失敗しても、残りの高さをそろえる（start はロックの後のどの出口でもそろえる）
reset; start v1; start v2; start v3; echo '{"finished":true}' > "$T/proj/s1/subagents/agent-v2.meta.json"
lay "$(pn 10 0 20),$(pn 12 20 39)" "$(sp 0.3333333 0 59)" # 真ん中（p11）を回収した直後（20・39 行）
touch "$T/split_fail"; start v4; rm -f "$T/split_fail" "$T/proj/s1/subagents"/*.meta.json
grep -q '^pane close w1:p11' "$LOG" && [ ! -e "$XDG_STATE_HOME/agent-pane/w1_p1/v4" ] && grep -q '^pane resize --pane w1:p10 --direction down --amount 0\.1666' "$LOG" \
  && ok "回収の後に分けられなくても、残りの高さをそろえる" || ng "回収と分割の失敗: $(grep '^pane' "$LOG")"

# ---- workflow のエージェントでは開かず、何も記録しない
reset; start w1 workflow-subagent
[ ! -e "$LOG" ] && [ -z "$(ls "$XDG_STATE_HOME/agent-pane/w1_p1" 2>/dev/null)" ] && ok "workflow のエージェントでは開かない" || ng "workflow: $(cat "$LOG" 2>/dev/null)"

# ---- 終了は開始と同じロックを取る（開始が数えたサブの pane を、分ける前に閉じない）
if command -v flock >/dev/null 2>&1; then
  reset; start l1; D1="$XDG_STATE_HOME/agent-pane/w1_p1"
  ( exec 9>>"$D1.lock"; flock 9; sleep 1; echo released >> "$LOG" ) & h=$!; sleep 0.3; stop l1; wait $h
  [ "$(grep 'released\|^pane close' "$LOG" | tr '\n' '|')" = "released|pane close w1:p10|" ] \
    && ok "終了はロックが外れるのを待ってから閉じる" || ng "終了のロック: $(cat "$LOG")"
fi

# ---- 記録のパスに ' があっても view のコマンドが壊れない（シェルが解釈した結果がそのパス）
reset; Q="$T/it's"; mkdir -p "$Q/s1/subagents"
printf '{"session_id":"s1","transcript_path":"%s/s1.jsonl","cwd":"%s","agent_id":"q1"}' "$Q" "$T" | in_herdr agent-pane start
cmd="$(sed -n 's/^pane run w1:p[0-9]* //p' "$LOG")"
eval "set -- $cmd" 2>/dev/null && [ "${3:-}" = "$Q/s1/subagents/agent-q1.jsonl" ] && ok "パスの ' を正しくエスケープする" || ng "引用符: $cmd"

# ---- 消えた pane・中断（finished）は数えない
reset; start b1; start b2; start b3; rm -f "$T/live"/*; start b4
[ "$(splits)" = 4 ] && ok "消えた pane は数えない" || ng "消えた pane: $(splits)"
reset; start c1; start c2; start c3; echo '{"finished":true}' > "$T/proj/s1/subagents/agent-c1.meta.json"; start c4
[ "$(splits)" = 4 ] && grep -q '^pane close w1:p10' "$LOG" && ok "中断で finished のものは閉じて数えない" || ng "finished: $(cat "$LOG")"
rm -f "$T/proj/s1/subagents"/*.meta.json

# ---- herdr との通信が失敗したときは、覚えた pane を消さない（数えて、後で閉じられるように）
reset; start e1; touch "$T/broken"; stop e1
[ -e "$XDG_STATE_HOME/agent-pane/w1_p1/e1" ] && ok "close が通信の失敗なら覚えた pane を残す" || ng "通信の失敗で記録を消した"
start e2; start e3; rm -f "$T/broken"; start e4
[ "$(splits)" = 3 ] && ok "get が通信の失敗なら pane を数えたままにする" || ng "通信の失敗: splits=$(splits)"

# finished でも閉じられなかった（通信の失敗）pane は数える
reset; start f1; start f2; start f3; echo '{"finished":true}' > "$T/proj/s1/subagents/agent-f1.meta.json"; touch "$T/broken"; start f4; rm -f "$T/broken"
[ "$(splits)" = 3 ] && ok "finished でも閉じられなかった pane は数える" || ng "finished と close の失敗: splits=$(splits)"
rm -f "$T/proj/s1/subagents"/*.meta.json

# 表示を起動できなければ pane を閉じて記録も残さない
reset; touch "$T/run_fail"; start g1; rm -f "$T/run_fail"
[ -z "$(ls "$T/live")" ] && [ ! -e "$XDG_STATE_HOME/agent-pane/w1_p1/g1" ] && ok "表示の起動に失敗したら pane を閉じて記録を消す" || ng "起動の失敗: live=$(ls "$T/live")"
start g1; [ "$(splits)" = 2 ] && ok "起動に失敗した後の再通知で開き直す" || ng "再通知: $(splits)"

# ---- 並行の開始でも上限を守る
reset; for a in d1 d2 d3 d4; do start "$a" & done; wait
[ "$(splits)" = 3 ] && [ "$(grep -c '^pane split --pane w1:p1 ' "$LOG")" = 1 ] && [ "$(grep -c '^pane split --pane w1:p10 ' "$LOG")" = 1 ] \
  && [ "$(grep -c '^pane split --pane w1:p11 ' "$LOG")" = 1 ] && ok "4 つ同時に開始しても開くのは 3 つで、それぞれその時のいちばん下を分ける" || ng "並行: $(grep '^pane split' "$LOG")"

# ---- 片づけに失敗した pane は、次のセッション（clear の後）の片づけで閉じる（記録はメインの pane ごと）
reset; start h1; touch "$T/broken"; printf '{"session_id":"s1"}' | in_herdr agent-pane cleanup; rm -f "$T/broken"
printf '{"session_id":"s2"}' | in_herdr agent-pane cleanup
[ -z "$(ls "$T/live")" ] && ok "前のセッションで閉じられなかった pane も次のセッションの片づけで閉じる" || ng "セッションをまたぐ片づけ: $(ls "$T/live")"
reset; start i1; start i2; start i3; printf '{"session_id":"s2","transcript_path":"%s/proj/s2.jsonl","cwd":"%s","agent_id":"i4"}' "$T" "$T" | in_herdr agent-pane start
[ "$(splits)" = 3 ] && ok "上限はメインの pane ごと（セッションが替わっても数える）" || ng "セッションをまたぐ上限: $(splits)"

# ---- cleanup はすべて閉じる
printf '{"session_id":"s1"}' | in_herdr agent-pane cleanup; [ -z "$(ls "$T/live")" ] && ok "cleanup はそのセッションの pane をすべて閉じる" || ng "cleanup: $(ls "$T/live")"

# ---- view
J="$T/v.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"調べます"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}' > "$J"
if command -v timeout >/dev/null 2>&1; then # macOS には無い
  out="$(timeout 2 agent-pane view "$J" 2>/dev/null)"
  [ "$out" = "調べます
→ Bash ls -la" ] && ok "view は文とツールの呼び出しを 1 行ずつ出す" || ng "view: $out"
fi

[ "$fail" = 0 ] && echo "acceptance agent-pane: ok"
[ "$fail" = 0 ]
