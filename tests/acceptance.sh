#!/bin/sh
# 受け入れ検査（/accept の acceptor が tests/acceptance/ に残したもの）をすべて実行する。
# 1 本でも失敗すれば exit 1。出力は失敗した検査の出力と、要約 1 行だけ
#   sh tests/acceptance.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)/acceptance"
ok=0; ng=0
for t in "$DIR"/*.sh; do
  [ -e "$t" ] || continue
  if out="$(sh "$t" 2>&1)"; then ok=$((ok + 1)); else ng=$((ng + 1)); printf 'FAIL %s\n%s\n' "${t#"$DIR"/}" "$out"; fi
done
echo "acceptance: ok $ok, FAIL $ng"
[ "$ng" = 0 ]
