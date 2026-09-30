#!/bin/sh
# 作業ツリー全体（追跡・未追跡。.gitignore で無視されるものは除く）の git tree ID を出力する。
# /review が「レビューした版」として記録し、/review fix が `git diff <前回の版> <今の版>` で修正差分だけを見るために使う。
# 実 index と作業ツリーは変えない（index の複製に git add -A して write-tree）。書くのは git のオブジェクトだけ
# （どこからも参照されないので、git gc がいずれ消す）
# ponytail: 無視されていない未追跡ファイルはすべてオブジェクトに書く。大きなデータを ignore していないリポジトリでは
# 毎回そのぶん遅く、容量も食う（その時は .gitignore に足す）。読めない未追跡ファイルがあると失敗する
#   sh ~/.claude/skills/review/snapshot.sh
set -eu
top="$(git rev-parse --show-toplevel)" || { echo "snapshot: git の作業ツリーの中で実行する" >&2; exit 1; }
index="$(git -C "$top" rev-parse --path-format=absolute --git-path index)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if [ -f "$index" ]; then cp "$index" "$tmp"; else rm -f "$tmp"; fi # コミット前で index が無ければ空から
GIT_INDEX_FILE="$tmp" git -C "$top" add -A
GIT_INDEX_FILE="$tmp" git -C "$top" write-tree
