#!/bin/sh
# agent-pane の受け入れ検査（ARK-90）: 偽の herdr で、herdr の中ではサブエージェントの開始で pane を分けて view を動かし（同時に 2 つまで。
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
trap 'rm -rf "$T"' EXIT
export XDG_STATE_HOME="$T/state"
mkdir -p "$T/bin" "$T/live" "$T/proj/s1/subagents"
LOG="$T/herdr.log"
# 偽の herdr: split は新しい pane（w1:p<連番>）を live に作り、get は live にあれば 0、close は live から消す
cat > "$T/bin/herdr" <<SH
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "pane split") n=\$(( \$(ls "$T/live" | wc -l) + 10 )); touch "$T/live/w1:p\$n"; printf '{"result":{"pane":{"pane_id":"w1:p%s"}}}\n' "\$n" ;;
  "pane get") [ -e "$T/live/\$3" ] || exit 1 ;;
  "pane close") rm -f "$T/live/\$3" ;;
esac
exit 0
SH
chmod +x "$T/bin/herdr"
export PATH="$ROOT/bin:$T/bin:$PATH"
in_herdr() { HERDR_ENV=1 HERDR_PANE_ID=w1:p1 "$@"; }
ev() { printf '{"session_id":"s1","transcript_path":"%s/proj/s1.jsonl","cwd":"%s","agent_id":"%s"}' "$T" "$T" "$1"; }
start() { ev "$1" | in_herdr agent-pane start; }
stop() { ev "$1" | in_herdr agent-pane stop; }
splits() { grep -c '^pane split' "$LOG" 2>/dev/null || true; }
reset() { rm -rf "$LOG" "$XDG_STATE_HOME" "$T/live"/*; }

# ---- herdr の外では何もしない
ev a1 | agent-pane start; [ $? = 0 ] && [ ! -e "$LOG" ] && ok "herdr の外では何もしない" || ng "外で herdr を呼んだ"

# ---- 開始で pane を分けて view、上限 2
start a1; start a2
[ "$(splits)" = 2 ] && [ "$(grep -c '^pane run' "$LOG")" = 2 ] && grep -q "^pane split --pane w1:p1 --direction right --no-focus" "$LOG" \
  && ok "開始でメインの pane を分け（フォーカスは移さない）view を動かす" || ng "開始: $(cat "$LOG")"
grep -q "pane run w1:p10 agent-pane view '$T/proj/s1/subagents/agent-a1.jsonl'" "$LOG" && ok "view にサブエージェントの記録のパスを渡す" || ng "view の引数: $(grep 'pane run' "$LOG")"
start a3; [ "$(splits)" = 2 ] && ok "同時に 2 つを超えたら開かない（バックグラウンドのまま）" || ng "上限: $(splits)"
start a1; [ "$(splits)" = 2 ] && ok "同じエージェントの再通知では開かない" || ng "再通知で開いた"
stop a1; ! [ -e "$T/live/w1:p10" ] && grep -q '^pane close w1:p10' "$LOG" && ok "終了でその pane を閉じる" || ng "終了: $(cat "$LOG")"
start a4; [ "$(splits)" = 3 ] && ok "閉じた分だけまた開ける" || ng "閉じた後: $(splits)"

# ---- 消えた pane・中断（finished）は数えない
reset; start b1; start b2; rm -f "$T/live"/*; start b3
[ "$(splits)" = 3 ] && ok "消えた pane は数えない" || ng "消えた pane: $(splits)"
reset; start c1; start c2; echo '{"finished":true}' > "$T/proj/s1/subagents/agent-c1.meta.json"; start c3
[ "$(splits)" = 3 ] && grep -q '^pane close w1:p10' "$LOG" && ok "中断で finished のものは閉じて数えない" || ng "finished: $(cat "$LOG")"
rm -f "$T/proj/s1/subagents"/*.meta.json

# ---- 並行の開始でも上限を守る
reset; for a in d1 d2 d3 d4; do start "$a" & done; wait
[ "$(splits)" = 2 ] && ok "4 つ同時に開始しても開くのは 2 つ" || ng "並行: $(splits)"

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
