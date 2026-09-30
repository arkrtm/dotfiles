#!/bin/sh
# config/claude/skills/review/snapshot.sh の検査。範囲限定の再レビュー（/review fix）が「前回のレビューが見た版」との
# 差分を取るためのスナップショット: 作業ツリー全体（未追跡を含む、無視は除く）の tree ID を、実 index を変えずに出す
#   sh tests/review-snapshot.sh
set -eu
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="$DOTFILES/config/claude/skills/review/snapshot.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"                        # 利用者のグローバル git 設定（core.excludesFile 等）から隔離する
mkdir -p "$HOME"
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE 2>/dev/null || true
fail=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1（期待: $3 / 実際: $2）"; fi; }
snap() { (cd "$1" && sh "$SNAP"); }
# 実 index の内容（モード・blob・パス）と作業ツリーの状態。スナップショットの前後で変わらないこと
# （stat 情報は比べない。git status 自身が racy-git 対策で書き換えるため）
state() { git -C "$1" ls-files -s; git -C "$1" status --porcelain --untracked-files=all --ignored; }

# git の外では失敗する
mkdir "$TMP/nogit"
if snap "$TMP/nogit" >/dev/null 2>&1; then ng "git の外では失敗する"; else ok "git の外では失敗する"; fi

# コミット前のリポジトリ（index ファイルが無い）でも動く
P="$TMP/fresh"; git init -q "$P"; echo a > "$P/a.txt"
s="$(snap "$P" 2>&1 || true)"
check "コミット前のリポジトリでも tree を出す" "$(git -C "$P" cat-file -t "$s" 2>/dev/null || echo "$s")" tree
check "（コミット前）未追跡のファイルを含む" "$(git -C "$P" ls-tree --name-only "$s" 2>/dev/null)" a.txt

# 追跡・未追跡・無視・削除・シンボリックリンク・強制追加した無視ファイル
R="$TMP/repo"; g="git -C $R -c user.name=t -c user.email=t@t"
git init -q -b main "$R"
printf '*.log\n' > "$R/.gitignore"
echo v1 > "$R/tracked.txt"; echo gone > "$R/del.txt"; echo f1 > "$R/forced.log"
$g add .gitignore tracked.txt del.txt; $g add -f forced.log; $g commit -q -m init
echo v2 > "$R/tracked.txt"; rm "$R/del.txt"; echo f2 > "$R/forced.log"
echo new > "$R/new.txt"; echo junk > "$R/ignored.log"; ln -s tracked.txt "$R/link"
mkdir "$R/sub"
before="$(state "$R")"
s1="$(snap "$R")"
check "実 index と作業ツリーを変えない（作業ツリーに一時ファイルも残さない）" "$(state "$R")" "$before"
names="$(git -C "$R" ls-tree -r --name-only "$s1" | tr '\n' ' ')"
check "追跡・未追跡・強制追加の無視ファイル・リンクを含み、削除と無視は含まない" "$names" ".gitignore forced.log link new.txt tracked.txt "
check "変更後の内容を記録する" "$(git -C "$R" show "$s1:tracked.txt")" v2
check "強制追加した無視ファイルの変更も記録する" "$(git -C "$R" show "$s1:forced.log")" f2
check "シンボリックリンクはリンクとして記録する" "$(git -C "$R" ls-tree "$s1" link | cut -c1-6)" 120000
check "同じ内容なら同じ ID" "$(snap "$R")" "$s1"
check "サブディレクトリから実行しても同じ ID" "$(snap "$R/sub")" "$s1"
echo fixed > "$R/new.txt"
s2="$(snap "$R")"
check "2 つの版の差分は、その間の変更だけ" "$(git -C "$R" diff --name-only "$s1" "$s2")" new.txt

# worktree（.git がファイル）でも、その worktree の作業ツリーを記録する
$g worktree add -q "$TMP/wt" -b wtb
echo w > "$TMP/wt/w.txt"
before="$(state "$TMP/wt")"
w="$(snap "$TMP/wt")"
check "worktree の未追跡ファイルを含み、本体の未追跡は含まない" "$(git -C "$R" ls-tree --name-only "$w" | tr '\n' ' ')" ".gitignore del.txt forced.log tracked.txt w.txt "
check "worktree でも実 index と作業ツリーを変えない" "$(state "$TMP/wt")" "$before"

exit "$fail"
