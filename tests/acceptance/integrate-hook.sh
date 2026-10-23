#!/bin/sh
# integrate-hook の受け入れ検査（ARK-99）: 一時 HOME と一時的なリポジトリで、origin があって integrate setup の設定が無い
# リポジトリでは、pre-edit が編集を拒み（終了コード 2、理由に integrate setup）、session-start が案内を出すこと。
# 設定がある・origin が無い・git の外・空の入力・jq が無いときは何もしない（終了コード 0）
#   sh tests/acceptance/integrate-hook.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/integrate-hook.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }
# HOME を替えると mise の shim が設定を読めず失敗するので、替える前に本物の jq の場所を PATH の先頭に入れる
PATH="$(dirname "$(mise which jq 2>/dev/null || command -v jq)"):$PATH"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$T/out-of-git"
H="$ROOT/bin/integrate-hook"
export PATH="$ROOT/bin:$PATH"

git init -q --bare -b main "$T/r.git"
git init -q -b main "$T/w" && git -C "$T/w" remote add origin "$T/r.git" && mkdir -p "$T/w/sub" && echo x > "$T/w/sub/a.txt"
git init -q -b main "$T/local" # origin が無い

edit() { # edit <cwd> <file_path>: pre-edit の終了コードを返し、標準エラーを $T/err に
  printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" | sh "$H" pre-edit 2>"$T/err"
}
start() { printf '{"cwd":"%s","source":"startup"}' "$1" | sh "$H" session-start 2>/dev/null; }

# ---- pre-edit
edit "$T/w" "$T/w/sub/a.txt"; rc=$?
[ "$rc" = 2 ] && grep -q 'integrate setup' "$T/err" && ok "未設定のリポジトリの編集は 2 で拒み、integrate setup を促す" || ng "未設定の編集: rc=$rc $(cat "$T/err")"
edit "$T/out-of-git" "$T/w/new/dir/b.txt"; rc=$?
[ "$rc" = 2 ] && ok "まだ無いファイルは親のディレクトリで判定する（cwd でなくファイルのリポジトリ）" || ng "新規ファイル: rc=$rc"
edit "$T/w" "$T/out-of-git/c.txt"; [ $? = 0 ] && ok "git の外のファイルは止めない" || ng "git の外のファイルを止めた"
edit "$T/local" "$T/local/d.txt"; [ $? = 0 ] && ok "origin の無いリポジトリは止めない" || ng "origin の無いリポジトリを止めた"
printf '{"cwd":"%s","tool_name":"Write","tool_input":{}}' "$T/w" | sh "$H" pre-edit 2>/dev/null; [ $? = 2 ] \
  && ok "file_path が無ければ cwd で判定する" || ng "file_path が無いとき cwd で判定しない"
(cd "$T/w" && integrate setup --kind bare --base main --test true </dev/null >/dev/null 2>&1)
edit "$T/w" "$T/w/sub/a.txt"; [ $? = 0 ] && ok "設定があれば止めない" || ng "設定があるのに止めた: $(cat "$T/err")"

# ---- session-start
git init -q -b main "$T/w2" && git -C "$T/w2" remote add origin "$T/other.git"
out="$(start "$T/w2")"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'integrate setup' && ok "未設定なら会話の始まりに integrate setup を案内する" || ng "session-start の案内: rc=$rc out=$out"
out="$(start "$T/w")"; [ $? = 0 ] && [ -z "$out" ] && ok "設定済みなら何も出さない" || ng "設定済みで出力: $out"
out="$(start "$T/out-of-git")"; [ $? = 0 ] && [ -z "$out" ] && ok "git の外では何も出さない" || ng "git の外で出力: $out"

# ---- 壊れた入力・jq が無い
printf '' | sh "$H" pre-edit 2>/dev/null; [ $? = 0 ] && ok "空の入力は止めない" || ng "空の入力で止めた"
mkdir -p "$T/nojq"; for c in sh git cat dirname; do ln -s "$(command -v $c)" "$T/nojq/$c"; done
printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$T/w2" "$T/w2/x" | PATH="$T/nojq" "$T/nojq/sh" "$H" pre-edit 2>/dev/null
[ $? = 0 ] && ok "jq が無ければ止めない" || ng "jq が無いのに止めた"

[ "$fail" = 0 ] && echo "acceptance integrate-hook: ok"
[ "$fail" = 0 ]
