#!/bin/sh
# 検査の入口（scripts/check・tests/acceptance.sh）は、受け継いだ git の環境変数（GIT_DIR など。git rebase -x や git の hook が渡す）を外す。
# 外さないと、検査が一時ディレクトリで実行する git init・commit・config・push が、外のリポジトリに効く
#   sh tests/acceptance/git-env.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/git-env.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# 外のリポジトリ（git rebase -x の中にいる形: GIT_DIR と GIT_WORK_TREE がここを指す）
O="$T/outer"; git init -q "$O"
# 写し: 入口の 2 つと、git を一時ディレクトリで使う偽の検査（static・install・受け入れ検査を 1 本ずつ）
R="$T/r"; mkdir -p "$R/scripts" "$R/tests/acceptance"
cp "$ROOT/scripts/check" "$R/scripts/check"; cp "$ROOT/tests/acceptance.sh" "$R/tests/acceptance.sh"
# 偽の検査は、渡された場所（PROBE_D。一時ディレクトリの下）に git init して設定を書く。実行されたことは、その中の設定で確かめる
probe='git init -q "$PROBE_D/$1" && git -C "$PROBE_D/$1" config probe.leaked yes'
for f in static install; do printf '%s\n' "$probe" > "$R/tests/$f.sh"; done
printf '%s\n' "$probe" > "$R/tests/acceptance/probe.sh"
export PROBE_D="$T/probe"; mkdir "$PROBE_D"
leaked() { git --git-dir="$O/.git" config --get probe.leaked >/dev/null; }
ran() { git -C "$PROBE_D/$1" config --get probe.leaked >/dev/null 2>&1; }

GIT_DIR="$O/.git" GIT_WORK_TREE="$O" sh "$R/tests/acceptance.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && ran "" && ! leaked; then ok "tests/acceptance.sh は受け継いだ GIT_DIR を外す（中の検査は動き、外のリポジトリは変わらない）"
else ng "tests/acceptance.sh は受け継いだ GIT_DIR を外す: rc=$rc 中の検査が動いた=$(ran "" && echo yes || echo no) 外が変わった=$(leaked && echo yes || echo no)"; fi
rm -rf "${PROBE_D:?}/.git"
GIT_DIR="$O/.git" GIT_WORK_TREE="$O" sh "$R/scripts/check" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && ran "" && ! leaked; then ok "scripts/check は受け継いだ GIT_DIR を外す（中の検査は動き、外のリポジトリは変わらない）"
else ng "scripts/check は受け継いだ GIT_DIR を外す: rc=$rc 中の検査が動いた=$(ran "" && echo yes || echo no) 外が変わった=$(leaked && echo yes || echo no)"; fi

[ "$fail" = 0 ] && echo "acceptance git-env: ok"
[ "$fail" = 0 ]
