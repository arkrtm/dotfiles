#!/bin/sh
# agent-status の受け入れ検査（ARK-68 I2）: 私設ソケットの本物の tmux で、ペインの状態の集約（waiting > working > done、全 idle で消える）と、
# 状態の読みと書きが 1 回の tmux 呼び出しであること（同時に 2 本走っても通知が二重にならない根拠）を確かめる
#   sh tests/acceptance/agent-status.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/agent-status.sh  通った項目も
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v tmux >/dev/null 2>&1 || { echo "FAIL tmux が無い（mise で入る）"; exit 1; }
S="dotfiles-agent-$$"; H="$(mktemp -d)"
trap 'tmux -L "$S" kill-server 2>/dev/null; rm -rf "$H"' EXIT
tmux -L "$S" -f /dev/null new-session -d -x 80 -y 24 sleep 600
tmux -L "$S" split-window -d sleep 600
# agent-status の tmux は $TMUX のソケットを使う（本物の hook と同じ条件）
export TMUX="$(tmux -L "$S" display -p '#{socket_path}'),0,0"
set -- $(tmux -L "$S" list-panes -F '#{pane_id}'); p1=$1; p2=$2
agg() { tmux -L "$S" show -w -v @agent 2>/dev/null || true; }
st() { TMUX_PANE="$1" sh "$ROOT/bin/agent-status" "$2" </dev/null; }

st "$p1" working; [ "$(agg)" = working ] && ok "1 ペインが working → ウィンドウは working" || ng "working が集約されない: $(agg)"
st "$p2" waiting; [ "$(agg)" = waiting ] && ok "waiting は working より優先" || ng "waiting が優先されない: $(agg)"
st "$p2" done; [ "$(agg)" = working ] && ok "working は done より優先" || ng "done の集約が違う: $(agg)"
st "$p1" idle; [ "$(agg)" = done ] && ok "idle のペインは数えない" || ng "idle の後の集約が違う: $(agg)"
st "$p2" idle; [ -z "$(agg)" ] && ok "全ペインが idle なら @agent が消える" || ng "@agent が残る: $(agg)"

# 読みと書きが 1 回の tmux 呼び出し: tmux を記録するラッパーを PATH の先頭に置く（; で連ねた 1 コマンドなら、同時に 2 本走っても交錯しない）
mkdir -p "$H/bin"
printf '#!/bin/sh\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$H/tmux-calls" "$(command -v tmux)" > "$H/bin/tmux"; chmod +x "$H/bin/tmux"
PATH="$H/bin:$PATH" st "$p1" waiting
grep -q "display -p -t $p1 #{@agent_pane} ; set -p -t $p1 @agent_pane waiting" "$H/tmux-calls" \
  && ok "状態の読み（display -p）と書き（set -p）が 1 回の tmux 呼び出し" || ng "読みと書きが別の呼び出し: $(tr '\n' '|' < "$H/tmux-calls")"
: > "$H/tmux-calls"; PATH="$H/bin:$PATH" st "$p1" idle
grep -q "display -p -t $p1 #{@agent_pane} ; set -p -t $p1 -u @agent_pane" "$H/tmux-calls" \
  && ok "idle も 1 回の呼び出し" || ng "idle の読みと書きが別の呼び出し: $(tr '\n' '|' < "$H/tmux-calls")"

[ "$fail" = 0 ] && echo "acceptance agent-status: ok"
[ "$fail" = 0 ]
