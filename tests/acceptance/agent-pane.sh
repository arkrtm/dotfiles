#!/bin/sh
# agent-pane の受け入れ検査（ARK-90・ARK-100）: 偽の herdr で、herdr の中ではサブエージェントの開始で pane を分けて view を動かし
# （1 つ目はメインの上に 3 分の 1、2 つ目はその右。同時に 2 つまで。workflow のエージェントでは開かない。
# 同じエージェントの再通知・並行の開始でも上限を守る）、終了で閉じること。消えた pane・中断で finished のものは数えず閉じ、
# cleanup はすべて閉じること。herdr の外では何もしないこと。view は記録（jsonl）の文とツールの呼び出しを 1 行ずつ出すこと
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
trap 'kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
export XDG_STATE_HOME="$T/state"
mkdir -p "$T/bin" "$T/live" "$T/proj/s1/subagents"
LOG="$T/herdr.log"
# 偽の herdr: split は新しい pane（w1:p<連番>）を live に作り、get は live にあれば 0、close は live から消す
cat > "$T/bin/herdr" <<SH
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "pane run") [ -e "$T/run_fail" ] && exit 1 ;;
  "pane swap") [ -e "$T/swap_fail" ] && exit 1; echo "\$4" > "$T/focused" ;; # 本物と同じく source にフォーカスを移す
  "pane split") n=\$(( \$(ls "$T/live" | wc -l) + 10 )); touch "$T/live/w1:p\$n"; printf '{"result":{"pane":{"pane_id":"w1:p%s"}}}\n' "\$n" ;;
  "pane get"|"pane close")
    # $T/broken があれば通信の失敗（pane_not_found 以外のエラー）
    [ -e "$T/broken" ] && { echo '{"error":{"code":"server_unavailable"}}'; exit 1; }
    [ -e "$T/live/\$3" ] || { echo '{"error":{"code":"pane_not_found"}}'; exit 1; }
    [ "\$2" = close ] && rm -f "$T/live/\$3" ;;
esac
exit 0
SH
chmod +x "$T/bin/herdr"
# 偽の socket API（CLI に無い pane.current・pane.focus）: フォーカスは $T/focused
perl -MIO::Socket::UNIX -e '
  my ($sock, $log, $foc) = @ARGV;
  my $srv = IO::Socket::UNIX->new(Local => $sock, Listen => 5) or die $!;
  while (my $c = $srv->accept) {
    my $l = <$c>; my ($m) = $l =~ /"method":"([^"]+)"/; my ($p) = $l =~ /"pane_id":"([^"]+)"/;
    open my $lf, ">>", $log; print $lf "api $m", ($p ? " $p" : ""), "\n"; close $lf;
    if ($m eq "pane.current") { open my $f, "<", $foc; chomp(my $id = <$f> // ""); print $c qq({"id":"x","result":{"pane":{"pane_id":"$id"}}}\n) }
    else { open my $f, ">", $foc; print $f "$p\n"; close $f; print $c qq({"id":"x","result":{}}\n) }
    close $c;
  }' "$T/sock" "$LOG" "$T/focused" &
SRV=$!
while [ ! -S "$T/sock" ]; do sleep 0.1; done
export PATH="$ROOT/bin:$T/bin:$PATH"
in_herdr() { HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$T/sock" "$@"; }
ev() { printf '{"session_id":"s1","transcript_path":"%s/proj/s1.jsonl","cwd":"%s","agent_id":"%s","agent_type":"%s"}' "$T" "$T" "$1" "${2:-general-purpose}"; }
start() { ev "$@" | in_herdr agent-pane start; }
stop() { ev "$1" | in_herdr agent-pane stop; }
splits() { grep -c '^pane split' "$LOG" 2>/dev/null || true; }
reset() { rm -rf "$LOG" "$XDG_STATE_HOME" "$T/live"/*; echo w1:p1 > "$T/focused"; }
reset

# ---- herdr の外では何もしない
ev a1 | HERDR_SOCKET_PATH="$T/sock" agent-pane start; [ $? = 0 ] && [ ! -e "$LOG" ] && ok "herdr の外では何もしない" || ng "外で herdr を呼んだ"

# ---- 開始で pane を分けて view、上限 2
start a1; start a2
[ "$(splits)" = 2 ] && [ "$(grep -c '^pane run' "$LOG")" = 2 ] && ok "開始で pane を分けて view を動かす" || ng "開始: $(cat "$LOG")"
[ "$(grep '^pane ' "$LOG" | sed -n 1,2p | tr '\n' '|')" = "pane split --pane w1:p1 --direction down --ratio 0.333 --no-focus --cwd $T|pane swap --source-pane w1:p1 --target-pane w1:p10|" ] \
  && ok "1 つ目はメインを下に分けて入れ替える（新しい pane が上 3 分の 1、フォーカスは移さない）" || ng "1 つ目の分け方: $(cat "$LOG")"
grep -q "^pane split --pane w1:p10 --direction right --no-focus --cwd $T\$" "$LOG" && [ "$(grep -c '^pane swap' "$LOG")" = 1 ] \
  && ok "2 つ目は開いているサブの pane を右に分ける（入れ替えない）" || ng "2 つ目の分け方: $(cat "$LOG")"
grep -q "pane run w1:p10 agent-pane view '$T/proj/s1/subagents/agent-a1.jsonl'" "$LOG" && ok "view にサブエージェントの記録のパスを渡す" || ng "view の引数: $(grep 'pane run' "$LOG")"
start a3; [ "$(splits)" = 2 ] && ok "同時に 2 つを超えたら開かない（バックグラウンドのまま）" || ng "上限: $(splits)"
start a1; [ "$(splits)" = 2 ] && ok "同じエージェントの再通知では開かない" || ng "再通知で開いた"
stop a1; ! [ -e "$T/live/w1:p10" ] && grep -q '^pane close w1:p10' "$LOG" && ok "終了でその pane を閉じる" || ng "終了: $(cat "$LOG")"
start a4; [ "$(splits)" = 3 ] && ok "閉じた分だけまた開ける" || ng "閉じた後: $(splits)"
rm -f "$T/live/w1:p11"; start a2; [ "$(splits)" = 4 ] && ok "人が閉じた pane は、同じエージェントの再通知で開き直す" || ng "開き直し: $(splits)"

# ---- workflow のエージェントでは開かず、何も記録しない
reset; start w1 workflow-subagent
[ ! -e "$LOG" ] && [ -z "$(ls "$XDG_STATE_HOME/agent-pane/w1_p1" 2>/dev/null)" ] && ok "workflow のエージェントでは開かない" || ng "workflow: $(cat "$LOG" 2>/dev/null)"

# ---- 入れ替えでフォーカスを奪わない（別の pane で作業中なら、入れ替えの後に戻す）
reset; echo w1:p5 > "$T/focused"; start k1
grep -q '^pane swap' "$LOG" && [ "$(cat "$T/focused")" = w1:p5 ] && ok "入れ替えの後、元のフォーカスに戻す" || ng "フォーカス: $(cat "$T/focused") $(cat "$LOG")"
reset; start k2; ! grep -q '^api pane.focus' "$LOG" && ok "フォーカスがメインなら戻す呼び出しをしない" || ng "余計な pane.focus: $(cat "$LOG")"
# socket が無ければフォーカスを読めないので入れ替えない（サブはメインの下。フォーカスは --no-focus のまま）
reset; ev k3 | HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$T/none" agent-pane start
grep -q '^pane split --pane w1:p1 --direction down' "$LOG" && ! grep -q '^pane swap' "$LOG" && grep -q '^pane run' "$LOG" \
  && ok "socket が無ければ入れ替えずに開く" || ng "socket 無し: $(cat "$LOG")"

# ---- 終了は開始と同じロックを取る（開始が既存のサブの pane を分けている間に、その pane を閉じない）
if command -v flock >/dev/null 2>&1; then
  reset; start l1; D1="$XDG_STATE_HOME/agent-pane/w1_p1"
  ( exec 9>>"$D1.lock"; flock 9; sleep 1; echo released >> "$LOG" ) & sleep 0.3; stop l1; wait $!
  [ "$(grep -n 'released\|^pane close' "$LOG" | cut -d: -f2- | tr '\n' '|')" = "released|pane close w1:p10|" ] \
    && ok "終了はロックが外れるのを待ってから閉じる" || ng "終了のロック: $(cat "$LOG")"
fi

# ---- 入れ替えに失敗したら、開いた pane を閉じて記録を残さない
reset; touch "$T/swap_fail"; start s1; rm -f "$T/swap_fail"
[ -z "$(ls "$T/live")" ] && [ ! -e "$XDG_STATE_HOME/agent-pane/w1_p1/s1" ] && ! grep -q '^pane run' "$LOG" \
  && ok "入れ替えに失敗したら pane を閉じて記録を消す" || ng "入れ替えの失敗: $(cat "$LOG")"

# ---- 記録のパスに ' があっても view のコマンドが壊れない（シェルが解釈した結果がそのパス）
reset; Q="$T/it's"; mkdir -p "$Q/s1/subagents"
printf '{"session_id":"s1","transcript_path":"%s/s1.jsonl","cwd":"%s","agent_id":"q1"}' "$Q" "$T" | in_herdr agent-pane start
cmd="$(sed -n 's/^pane run w1:p[0-9]* //p' "$LOG")"
eval "set -- $cmd" 2>/dev/null && [ "${3:-}" = "$Q/s1/subagents/agent-q1.jsonl" ] && ok "パスの ' を正しくエスケープする" || ng "引用符: $cmd"

# ---- 消えた pane・中断（finished）は数えない
reset; start b1; start b2; rm -f "$T/live"/*; start b3
[ "$(splits)" = 3 ] && ok "消えた pane は数えない" || ng "消えた pane: $(splits)"
reset; start c1; start c2; echo '{"finished":true}' > "$T/proj/s1/subagents/agent-c1.meta.json"; start c3
[ "$(splits)" = 3 ] && grep -q '^pane close w1:p10' "$LOG" && ok "中断で finished のものは閉じて数えない" || ng "finished: $(cat "$LOG")"
rm -f "$T/proj/s1/subagents"/*.meta.json

# ---- herdr との通信が失敗したときは、覚えた pane を消さない（数えて、後で閉じられるように）
reset; start e1; touch "$T/broken"; stop e1
[ -e "$XDG_STATE_HOME/agent-pane/w1_p1/e1" ] && ok "close が通信の失敗なら覚えた pane を残す" || ng "通信の失敗で記録を消した"
start e2; rm -f "$T/broken"; start e3
[ "$(splits)" = 2 ] && ok "get が通信の失敗なら pane を数えたままにする" || ng "通信の失敗: splits=$(splits)"

# finished でも閉じられなかった（通信の失敗）pane は数える
reset; start f1; start f2; echo '{"finished":true}' > "$T/proj/s1/subagents/agent-f1.meta.json"; touch "$T/broken"; start f3; rm -f "$T/broken"
[ "$(splits)" = 2 ] && ok "finished でも閉じられなかった pane は数える" || ng "finished と close の失敗: splits=$(splits)"
rm -f "$T/proj/s1/subagents"/*.meta.json

# 表示を起動できなければ pane を閉じて記録も残さない
reset; touch "$T/run_fail"; start g1; rm -f "$T/run_fail"
[ -z "$(ls "$T/live")" ] && [ ! -e "$XDG_STATE_HOME/agent-pane/w1_p1/g1" ] && ok "表示の起動に失敗したら pane を閉じて記録を消す" || ng "起動の失敗: live=$(ls "$T/live")"
start g1; [ "$(splits)" = 2 ] && ok "起動に失敗した後の再通知で開き直す" || ng "再通知: $(splits)"

# ---- 並行の開始でも上限を守る
reset; pids=""; for a in d1 d2 d3 d4; do start "$a" & pids="$pids $!"; done; wait $pids
[ "$(splits)" = 2 ] && ok "4 つ同時に開始しても開くのは 2 つ" || ng "並行: $(splits)"

# ---- 片づけに失敗した pane は、次のセッション（clear の後）の片づけで閉じる（記録はメインの pane ごと）
reset; start h1; touch "$T/broken"; printf '{"session_id":"s1"}' | in_herdr agent-pane cleanup; rm -f "$T/broken"
printf '{"session_id":"s2"}' | in_herdr agent-pane cleanup
[ -z "$(ls "$T/live")" ] && ok "前のセッションで閉じられなかった pane も次のセッションの片づけで閉じる" || ng "セッションをまたぐ片づけ: $(ls "$T/live")"
reset; start i1; start i2; printf '{"session_id":"s2","transcript_path":"%s/proj/s2.jsonl","cwd":"%s","agent_id":"i3"}' "$T" "$T" | in_herdr agent-pane start
[ "$(splits)" = 2 ] && ok "上限はメインの pane ごと（セッションが替わっても数える）" || ng "セッションをまたぐ上限: $(splits)"

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
