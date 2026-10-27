#!/bin/sh
# 受け入れ検査（issue の受け入れ条件を確かめる tests/acceptance/*.sh）をすべて実行する。
# 1 本でも失敗すれば exit 1。出力は失敗した検査の出力と、要約 1 行だけ
#   sh tests/acceptance.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)/acceptance"
# 各検査の出力は一時ファイルに書く（子が残って出力のパイプを持ったままだと、$(…) で受ける形は戻らない）
T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
ok=0; ng=0
for t in "$DIR"/*.sh; do
  [ -e "$t" ] || continue
  if sh "$t" > "$T/out" 2>&1; then ok=$((ok + 1)); else ng=$((ng + 1)); printf 'FAIL %s\n' "${t#"$DIR"/}"; cat "$T/out"; fi
done
echo "acceptance: ok $ok, FAIL $ng"
[ "$ng" = 0 ]
