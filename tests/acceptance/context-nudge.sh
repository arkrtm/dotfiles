#!/bin/sh
# context-nudge の受け入れ検査: ステータスラインが書いた文脈の使用率が 60% 以上なら、10% 刻みに 1 回だけ
# PostToolUse の additionalContext で handoff を促すこと。60% 未満・値が無い・数字でない・サブエージェント（agent_id）では何も出さない
#   sh tests/acceptance/context-nudge.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/context-nudge.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }
T=""; trap 'trap "" HUP INT TERM; wait; rm -rf ${T:+"$T"}' EXIT # 後ろで走らせた子（SIGINT を無視する）が終わってから消す（子が後から $T を作り直さないように）
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
export XDG_STATE_HOME="$T/state"
C="$XDG_STATE_HOME/claude-context"; mkdir -p "$C"
nudge() { printf '%s' "$1" | sh "$ROOT/bin/context-nudge"; }
main='{"session_id":"s1","hook_event_name":"PostToolUse"}'
at() { echo "$1" > "$C/s1"; out="$(nudge "$main")"; rc=$?; }

at 59; [ "$rc" = 0 ] && [ -z "$out" ] && ok "60% 未満では何も出さない" || ng "59%: rc=$rc $out"
at 61; [ "$rc" = 0 ] && [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" = PostToolUse ] \
  && printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '61%.*handoff' \
  && ok "60% 以上で additionalContext に使用率と handoff" || ng "61%: rc=$rc $out"
at 65; [ -z "$out" ] && ok "同じ 10% の刻みでは 2 回目を出さない" || ng "65%: $out"
at 72; printf '%s' "$out" | grep -q '72%' && ok "次の刻み（70%）でまた出す" || ng "72%: $out"
at 81; printf '%s' "$out" | grep -q '81%' && ok "80% でも出す" || ng "81%: $out"
at 30; [ -z "$out" ] && ok "compact などで下がったときは出さない" || ng "30%: $out"
at 63; printf '%s' "$out" | grep -q '63%' && ok "下がった後にまた 60% を超えたら出す" || ng "下がった後の 63%: $out"
# 並行する PostToolUse でも 1 回だけ
echo 64 > "$C/s1"; echo 50 > "$C/s1.nudged"; rm -f "$T/par"
for x in 1 2 3 4 5 6; do nudge "$main" >> "$T/par" & done; wait
[ "$(grep -c additionalContext "$T/par")" = 1 ] && ok "並行して呼ばれても 1 回だけ出す" || ng "並行: $(grep -c additionalContext "$T/par") 回"
rm -f "$C/s1" "$C/s1.nudged"; out="$(nudge "$main")"; [ $? = 0 ] && [ -z "$out" ] && ok "使用率のファイルが無ければ何も出さない" || ng "ファイルなし: $out"
at null; [ "$rc" = 0 ] && [ -z "$out" ] && ok "null では何も出さない" || ng "null: $out"
at abc; [ "$rc" = 0 ] && [ -z "$out" ] && ok "数字でなければ何も出さない" || ng "abc: $out"
echo 85 > "$C/s1"; rm -f "$C/s1.nudged"; out="$(nudge '{"session_id":"s1","agent_id":"agent-x"}')"
[ -z "$out" ] && [ ! -e "$C/s1.nudged" ] && ok "サブエージェント（agent_id）では出さず、刻みも進めない" || ng "agent_id: $out"
out="$(nudge '{"session_id":"../s1"}')"; [ -z "$out" ] && ok "session_id に / があれば何もしない" || ng "session_id の /: $out"
printf 'not json' | sh "$ROOT/bin/context-nudge" >/dev/null 2>&1; [ $? = 0 ] && ok "壊れた入力でも 0" || ng "壊れた入力で 0 でない"
XDG_STATE_HOME="$T/none" sh "$ROOT/bin/context-nudge" </dev/null >/dev/null 2>&1; printf '%s' "$main" | XDG_STATE_HOME="$T/none" sh "$ROOT/bin/context-nudge" >/dev/null 2>&1
[ $? = 0 ] && ok "状態の置き場がまだ無くても 0（Claude への警告にしない）" || ng "置き場が無いとき 0 でない"

[ "$fail" = 0 ] && echo "acceptance context-nudge: ok"
[ "$fail" = 0 ]
