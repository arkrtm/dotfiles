#!/bin/sh
# 受け入れ検査（issue の受け入れ条件を確かめる tests/acceptance/*.sh）をすべて実行する。
# 1 本でも失敗すれば exit 1。出力は失敗した検査の出力と、通った検査の省いた行（省いた …）と、要約 1 行だけ
#   sh tests/acceptance.sh
# INT を使う検査（SERIAL）は前で順に、ほかは後ろで同時に走らせる（非対話の sh が後ろで走らせた子は INT を無視して始まるので、
# INT を送る検査を後ろで走らせると中身を省いてしまう）。INT を使う検査を足したら SERIAL に入れる
set -u
DIR="$(cd "$(dirname "$0")" && pwd)/acceptance"
SERIAL="stop-cleanup.sh check-leftovers.sh"
# 各検査の出力は一時ファイルに書く（子が残って出力のパイプを持ったままだと、$(…) で受ける形は戻らない）
# 止められたら、後ろの検査（INT を無視して走っている）に TERM を送り、終わるのを待ってから消す
T=""; pids=""; trap 'trap "" HUP INT TERM; [ -z "$pids" ] || { kill $pids 2>/dev/null; wait; }; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
[ -n "$T" ] && [ -d "$T" ] || { echo "FAIL 一時ディレクトリを作れない（結果: ${T:-なし}）"; exit 1; }
started="" # 後ろで起こした検査の <名前>:<pid> の並び（pid は記録のファイルでなく、ここに持つ）
for t in "$DIR"/*.sh; do # SERIAL 以外を後ろで同時に起こす
  [ -e "$t" ] || continue
  n="${t#"$DIR"/}"
  case " $SERIAL " in *" $n "*) continue ;; esac
  sh "$t" > "$T/$n.out" 2>&1 & started="$started $n:$!"; pids="$pids $!"
done
for n in $SERIAL; do # INT を使う検査は前で順に
  [ -e "$DIR/$n" ] || continue
  sh "$DIR/$n" > "$T/$n.out" 2>&1; echo "$?" > "$T/$n.rc"
done
for e in $started; do
  wait "${e#*:}"; echo "$?" > "$T/${e%%:*}.rc"
done
pids="" # 全部を回収した。止められたときに、使い回された pid へ送らない
# 対象のすべての検査について結果（終了コード）を見る。記録を読めなかったもの（書けなかった）は、成功にせず失敗に数える
ok=0; ng=0; sk=0
for t in "$DIR"/*.sh; do
  [ -e "$t" ] || continue
  n="${t#"$DIR"/}"; rc="$(cat "$T/$n.rc" 2>/dev/null)"
  if [ "$rc" = 0 ]; then
    ok=$((ok + 1)); grep '^省いた ' "$T/$n.out" | sed "s|^省いた |省いた $n: |" # 環境の都合で走らせなかった検査は、通っても出す
  else ng=$((ng + 1)); printf 'FAIL %s\n' "$n"; [ -n "$rc" ] || echo "結果を記録できなかった"; cat "$T/$n.out" 2>/dev/null; fi
  sk=$((sk + $(grep -c '^省いた ' "$T/$n.out" 2>/dev/null)))
done
[ "$ok$ng" != 00 ] || { echo "FAIL 受け入れ検査が見つからない"; exit 1; }
echo "acceptance: ok $ok, FAIL $ng, 省いた $sk"
[ "$ng" = 0 ]
