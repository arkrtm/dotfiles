#!/bin/sh
# 止めたときの片づけの受け入れ検査（代表 1 つ）: 本物の tests/acceptance/agent-status.sh を、隔離した TMPDIR・TMUX_TMPDIR と setsid の新しいプロセスグループで
# 走らせ、tmux のソケットが一時ディレクトリにできた時点（秒数でなく、その出来事を待つ）でグループ全体に INT を送る（Ctrl-C と同じ形）。
# 確かめること: INT を送れた・終了コード 1・隔離した TMPDIR の中が空・そこを環境に持つプロセス（tmux のサーバ）とグループのプロセスが残らない。
# 止める前に終わった・ソケットを待つ上限（10 秒）を超えた場合は、確かめになっていないので失敗にする。
# setsid か /proc が無い環境（mac）、または INT を無視して起動された（後ろで走らせた）場合は、省いたと出す。止めるのは自分が起こしたグループだけ
#   sh tests/acceptance/stop-cleanup.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/stop-cleanup.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
skip() { [ -n "${V:-}" ] && echo "省いた $1"; return 0; }
# 環境の 1 項目が TMPDIR=$1 か TMUX_TMPDIR=$1 と完全に同じプロセスの pid（部分一致で別のものに当てない）
envpids() { [ -n "$1" ] || return 0; for e in /proc/[0-9]*/environ; do
    cat "$e" 2>/dev/null | tr '\0' '\n' | grep -qxF -e "TMPDIR=$1" -e "TMUX_TMPDIR=$1" && { p="${e#/proc/}"; echo "${p%/environ}"; }
  done; }
# 後片づけ: 起こしたグループと、一時ディレクトリを環境に持つプロセス（止められなかったときだけ残る）を止めてから消す
cleanup() {
  [ -n "$T" ] || return 0
  P="$(cat "$T/pid" 2>/dev/null)"; case "$P" in ''|*[!0-9]*) ;; *) kill -KILL -"$P" 2>/dev/null ;; esac
  for p in $(envpids "$T/tmp"); do [ "$p" = "$$" ] || kill "$p" 2>/dev/null; done
  rm -rf "$T"
}
T=""; trap 'trap "" HUP INT TERM; cleanup' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"

ign="$(sed -n 's/^SigIgn:[[:space:]]*//p' /proc/$$/status 2>/dev/null)"
if ! command -v setsid >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1 || [ -z "$ign" ]; then
  skip "agent-status.sh を止めて片づけを見る（setsid・tmux か /proc が無い）"
elif [ $((0x$ign & 2)) != 0 ]; then
  skip "agent-status.sh を止めて片づけを見る（INT を無視して起動された）"
else
  mkdir "$T/tmp"
  # 見張り: pid とソケットが揃ったらグループに INT を送る（上限 10 秒。来なければ note を書いて送らない）
  ( i=0; until [ -s "$T/pid" ] && [ -n "$(find "$T/tmp" -type s 2>/dev/null)" ]; do
      i=$((i + 1)); [ "$i" -lt 1000 ] || { echo "ソケットができない（10 秒待った）" > "$T/note"; exit 0; }; sleep 0.01; done
    P="$(cat "$T/pid")"; kill -INT -"$P" 2>/dev/null && echo INT > "$T/sent" ) &
  w=$!
  TMPDIR="$T/tmp" TMUX_TMPDIR="$T/tmp" setsid -w sh -c 'echo $$ > "$1"; exec sh "$2"' _ "$T/pid" "$ROOT/tests/acceptance/agent-status.sh" >/dev/null 2>&1; rc=$?
  wait "$w"; sleep 1 # tmux のサーバが終わるのを少し待つ
  P="$(cat "$T/pid" 2>/dev/null)"; left="$(find "$T/tmp" -mindepth 1 2>/dev/null | tr '\n' ' ')"
  procs="$(envpids "$T/tmp"; case "$P" in ''|*[!0-9]*) ;; *) pgrep -g "$P" 2>/dev/null ;; esac)"; procs="$(echo $procs)" # pgrep -g 0 は自分のグループ
  if [ -s "$T/note" ]; then ng "止める前の待ちが終わらない: $(cat "$T/note")"
  elif [ ! -s "$T/sent" ]; then ng "止める前に終わった（確かめになっていない）: rc=$rc"
  elif [ "$rc" != 1 ]; then ng "止めたが終了コードが 1 でない（後片づけの trap を通っていない）: rc=$rc"
  elif [ -n "$left" ] || [ -n "$procs" ]; then ng "止めた後に残っている: ファイル=[${left}] プロセス=[${procs}]"
  else ok "INT で止めても、ソケット・一時ディレクトリ・tmux のサーバが残らない（agent-status.sh）"; fi
fi

[ "$fail" = 0 ] && echo "acceptance stop-cleanup: ok"
[ "$fail" = 0 ]
