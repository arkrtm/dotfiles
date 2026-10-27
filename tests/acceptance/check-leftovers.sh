#!/bin/sh
# scripts/check の「一時ディレクトリの確かめ」の受け入れ検査: scripts/check を一時的な木に写し、tests/{static,install,acceptance}.sh を小さな偽物に置き換えて走らせる
# （本物の検査は走らせず、scripts/check の入れ子もない）。偽物は走ったら印を書き、MODE で何を残すかを変える。確かめること:
#   一時ディレクトリを作れない TMPDIR では、検査もプロセスの探索・停止も走らず失敗する
#   何も残さなければ出力なしで通る / ファイルを残せば失敗して出す
#   一時ディレクトリを環境に持つプロセスを残せば、失敗してそのプロセスを出して止める（Linux だけ）
#   環境が TMPDIR=<一時ディレクトリ>/sub のような別のプロセスは、止めない（部分一致で当てない。Linux だけ）
# 起こすプロセスはすべて自分の pid で管理し、名前では止めない
#   sh tests/acceptance/check-leftovers.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/check-leftovers.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
# 起こしたプロセスの後片づけ: 記録した pid のうち、コマンドラインがこの検査の sleep のものだけを止める（pid の使い回しで別のものに当てない）
cleanup() {
  [ -n "$T" ] || return 0
  for f in "$T"/pid.*; do
    [ -f "$f" ] || continue
    for p in $(cat "$f"); do
      case "$p" in ''|*[!0-9]*) continue ;; esac
      case "$(ps -o args= -p "$p" 2>/dev/null)" in *"sleep 599."*) kill "$p" 2>/dev/null ;; esac
    done
  done
  rm -rf "$T"
}
T=""; trap 'trap "" HUP INT TERM; cleanup' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
R="$T/r"; mkdir -p "$R/scripts" "$R/tests"
cp "$ROOT/scripts/check" "$R/scripts/check"
for t in static install acceptance; do
  cat > "$R/tests/$t.sh" <<'SH'
first=1; [ -e "$MARK" ] && first=""; echo ran >> "$MARK"
[ -n "$first" ] || exit 0 # 残すのは最初の 1 本だけ（pid の記録を 1 つにする）
case "${MODE:-}" in
  file) echo x > "$TMPDIR/left" ;;
  proc) sleep 599.7 >/dev/null 2>&1 </dev/null & echo $! >> "$PIDF" ;;
  tmuxonly) env -u TMPDIR sleep 599.9 >/dev/null 2>&1 </dev/null & echo $! >> "$PIDF" ;;
  sub) mkdir "$TMPDIR/sub"; env -u TMUX_TMPDIR TMPDIR="$TMPDIR/sub" sleep 599.8 >/dev/null 2>&1 </dev/null & echo $! >> "$PIDF"
    rmdir "$TMPDIR/sub" ;;
esac
SH
done
# run <MODE> [TMPDIR]: scripts/check の写しを走らせる。出力は $out、終了コードは $rc、偽の検査が走った印は $MARK
run() {
  n=$((n + 1)); PF="$T/pid.$1.$n"; rm -f "$MARK"; rc=0 # 実行ごとに別の pid の記録（失敗しても、起こした子を後片づけで止められる）
  out="$(MODE="$1" MARK="$MARK" PIDF="$PF" TMPDIR="${2:-${TMPDIR:-/tmp}}" sh "$R/scripts/check" 2>&1)" || rc=$?
}
MARK="$T/mark"; n=0
alive() { s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }
# 子を止めた後に消えるのを少し待つ
gone() { i=0; while alive "$1" && [ "$i" -lt 30 ]; do i=$((i + 1)); sleep 0.1; done; ! alive "$1"; }

run proc "$T/none" # 作れない TMPDIR（探索や停止が走るなら、proc の残りが出る）
if [ "$rc" = 1 ] && [ ! -e "$MARK" ] && [ ! -e "$PF" ] && printf '%s\n' "$out" | grep -q '^FAIL 一時ディレクトリを作れない'; then
  ok "一時ディレクトリを作れなければ、検査を走らせず失敗する"; else ng "作れない TMPDIR: rc=$rc 印=$([ -e "$MARK" ] && echo あり || echo なし) 出力=$out"; fi
ok=1; export ok; run proc "$T/none"; unset ok # 環境に ok=1 があっても、作れない TMPDIR では走らない
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "環境に ok=1 があっても、作れなければ検査を走らせず失敗する"; else ng "環境に ok=1 がある: rc=$rc 出力=$out"; fi
nl="$T/a$(printf '\nb')"; mkdir "$nl"; run proc "$nl" # 改行を含む TMPDIR（grep -F -e は改行でパターンを分けるので、別のプロセスに当たる）
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "TMPDIR に改行があっても、検査を走らせず失敗する"; else ng "改行を含む TMPDIR: rc=$rc 出力=$out"; fi
printf 'x' > "$T/notdir"; run proc "$T/notdir" # ディレクトリでない TMPDIR
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "TMPDIR がディレクトリでなくても、検査を走らせず失敗する"; else ng "ディレクトリでない TMPDIR: rc=$rc 出力=$out"; fi

run none
if [ "$rc" = 0 ] && [ -z "$out" ] && [ "$(wc -l < "$MARK" | tr -d ' ')" = 3 ]; then ok "何も残さなければ、3 本とも走って出力なしで通る"; else ng "何も残さない: rc=$rc 印=$(cat "$MARK" 2>/dev/null | wc -l) 出力=$out"; fi

run file
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL 検査が普通に終わった後に残っている' && printf '%s\n' "$out" | grep -q '/left$'; then
  ok "ファイルが残れば、失敗して残ったものを出す"; else ng "ファイルを残す: rc=$rc 出力=$out"; fi

if [ -d /proc/self ]; then
  run proc; p="$(cat "$PF" 2>/dev/null)"
  if [ "$rc" = 1 ] && [ -n "$p" ] && printf '%s\n' "$out" | grep -q "^ *$p sleep 599.7" && gone "$p"; then
    ok "環境に一時ディレクトリを持つプロセスが残れば、失敗してそのプロセスを出し、止める"; else ng "プロセスを残す: rc=$rc pid=$p 生きている=$(alive "${p:-0}" && echo はい || echo いいえ) 出力=$out"; fi
  run tmuxonly; p="$(cat "$PF" 2>/dev/null)" # 環境が TMUX_TMPDIR=<一時ディレクトリ> だけのプロセス
  if [ "$rc" = 1 ] && [ -n "$p" ] && printf '%s\n' "$out" | grep -q "^ *$p sleep 599.9" && gone "$p"; then
    ok "環境が TMUX_TMPDIR だけのプロセスが残っても、失敗してそのプロセスを出し、止める"; else ng "TMUX_TMPDIR だけのプロセス: rc=$rc pid=$p 出力=$out"; fi
  run sub; p="$(cat "$PF" 2>/dev/null)"
  if [ "$rc" = 0 ] && [ -z "$out" ] && [ -n "$p" ] && alive "$p"; then
    ok "環境が TMPDIR=<一時ディレクトリ>/sub のプロセスは、止めない（部分一致で当てない）"; else ng "別のプロセス: rc=$rc pid=$p 生きている=$(alive "${p:-0}" && echo はい || echo いいえ) 出力=$out"; fi
  [ -z "$p" ] || kill "$p" 2>/dev/null
fi

[ "$fail" = 0 ] && echo "acceptance check-leftovers: ok"
[ "$fail" = 0 ]
