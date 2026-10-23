#!/bin/sh
# Git の運用の受け入れ検査（ARK-88）: config/git/config をグローバル設定にした一時リポジトリで、
# rebase 中心の pull（履歴が分かれても merge コミットを作らず、未コミットの変更が残る。衝突は diff3 の形）、
# 新しい bare が早送りでない push と削除を拒むこと、config/git/ignore が .worktrees/ を除外すること
#   sh tests/acceptance/git-workflow.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/git-workflow.sh  通った項目も
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
C="$ROOT/config/git/config"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# 端末の ~/.gitconfig に左右されず、dotfiles の設定だけで動かす
export GIT_CONFIG_GLOBAL="$C" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# ---- AC1: 設定の値
for kv in pull.rebase=true rebase.autostash=true push.autosetupremote=true fetch.prune=true rerere.enabled=true \
  merge.conflictstyle=diff3 receive.denynonfastforwards=true receive.denydeletes=true; do
  [ "$(git config -f "$C" --get "${kv%%=*}" || true)" = "${kv#*=}" ] && ok "設定 $kv" || ng "設定 $kv が無い"
done

# ---- AC2: 新しい bare は早送りの push だけを受け付ける
git init -q --bare "$T/r.git"
git clone -q "$T/r.git" "$T/a" 2>/dev/null
cd "$T/a"
echo 1 > f; echo clean > d; git add f d; git commit -qm one
git push -q origin HEAD:main 2>/dev/null && ok "bare: 早送りの push は通る" || ng "bare: 早送りの push が拒否された"
git commit -q --amend -m one-amended
# 一時的な bare に対してだけ、拒否されることを確かめるために強制 push を試す（ARK-88 で了承済み）
git push -q origin +HEAD:main 2>/dev/null && ng "bare: 早送りでない push が通った" || ok "bare: 早送りでない push は拒否される"
git reset -q --hard origin/main
git push -q origin HEAD:x 2>/dev/null
git push -q origin :x 2>/dev/null && ng "bare: ブランチの削除が通った" || ok "bare: ブランチの削除は拒否される"

# ---- AC3: pull は rebase。未コミットの変更（追跡済みのファイル d）は残る
git clone -q "$T/r.git" "$T/b" 2>/dev/null
up() { (cd "$T/b" && git pull -q && echo "$2" > "$1" && git add "$1" && git commit -qm "up $1" && git push -q); }
# 履歴が分かれた場合
up g up1
echo mine > h; git add h; git commit -qm mine
echo dirty > d
if git pull -q 2>/dev/null; then
  [ -z "$(git rev-list --merges HEAD)" ] && ok "pull（分かれた履歴）: merge コミットを作らない" || ng "pull（分かれた履歴）: merge コミットができた"
  [ "$(cat d)" = dirty ] && ok "pull（分かれた履歴）: 未コミットの変更が残る" || ng "pull（分かれた履歴）: 未コミットの変更が消えた"
else ng "pull（分かれた履歴）が失敗した"; fi
git push -q origin HEAD:main
# 早送りの場合（別のファイルの未コミットの変更）
up g up2
if git pull -q 2>/dev/null && [ "$(cat g)" = up2 ] && [ "$(cat d)" = dirty ]; then ok "pull（早送り）: 取り込み、未コミットの変更が残る"
else ng "pull（早送り）: 取り込めないか、未コミットの変更が消えた"; fi
git checkout -q d
# 衝突は diff3 の形（共通の祖先の行が入る）
up f theirs
echo ours > f; git commit -qam ours
git pull -q >/dev/null 2>&1 && ng "pull（衝突）: 衝突しなかった" || {
  grep -q '^|||||||' f && ok "pull（衝突）: マーカーが diff3 の形" || ng "pull（衝突）: diff3 のマーカーが無い: $(cat f)"
  git rebase --abort
}

# ---- AC4: .worktrees/ はグローバルの除外
git -c core.excludesFile="$ROOT/config/git/ignore" check-ignore -q .worktrees/x \
  && ok "ignore: .worktrees/ を除外する" || ng "ignore: .worktrees/ を除外しない"

exit $fail
