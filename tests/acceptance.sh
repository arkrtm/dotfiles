#!/bin/sh
# 受け入れ検査（issue の受け入れ条件を確かめる tests/acceptance/*.sh）をすべて実行する。
# 1 本でも失敗すれば exit 1。出力は失敗した検査の出力と、通った検査の省いた行（省いた …）と、要約 1 行だけ
#   sh tests/acceptance.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)/acceptance"
# 各検査の出力は一時ファイルに書く（子が残って出力のパイプを持ったままだと、$(…) で受ける形は戻らない）
T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
ok=0; ng=0; sk=0
for t in "$DIR"/*.sh; do
  [ -e "$t" ] || continue
  n="${t#"$DIR"/}"
  if sh "$t" > "$T/out" 2>&1; then
    ok=$((ok + 1)); grep '^省いた ' "$T/out" | sed "s|^省いた |省いた $n: |" # 環境の都合で走らせなかった検査は、通っても出す
  else ng=$((ng + 1)); printf 'FAIL %s\n' "$n"; cat "$T/out"; fi
  sk=$((sk + $(grep -c '^省いた ' "$T/out")))
done
echo "acceptance: ok $ok, FAIL $ng, 省いた $sk"
[ "$ng" = 0 ]
