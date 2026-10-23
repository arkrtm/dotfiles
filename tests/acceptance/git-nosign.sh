#!/bin/sh
# 業務サーバーの署名消しの受け入れ検査（ARK-85）: core.hooksPath を config/git/hooks-nosign に向けた一時リポジトリで、
# commit と merge のメッセージから AI の Co-Authored-By 行だけが消え、人の共同作者・件名・本文は残ること。
# 指さないリポジトリ（私用の端末）では署名が残ること。AGENTS.md に「署名を付けない」が無く、README に業務サーバーの手順があること
#   sh tests/acceptance/git-nosign.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/git-nosign.sh  通った項目も
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# 端末の ~/.gitconfig（業務サーバーの hooksPath など）に左右されないよう、空の設定で動かす
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

MSG='fix token check

Keeps the expiry check testable.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Co-authored-by: Codex <codex@openai.com>
Co-Authored-By: Taro <taro@example.com>'
ai() { grep -ciE '^co-authored-by:.*(claude|codex)' || true; }

# リポジトリを作り、最初のコミットを置く。$1 が空でなければ hooksPath を指す
repo() {
  git init -q -b main "$1"
  [ -z "$2" ] || git -C "$1" config core.hooksPath "$ROOT/config/git/hooks-nosign"
  git -C "$1" commit -q --allow-empty -m "$MSG"
}

repo "$T/work" hook
body="$(git -C "$T/work" log -1 --format=%B)"
[ "$(printf '%s\n' "$body" | ai)" = 0 ] && ok "commit: AI の署名の行が消える" || ng "commit: AI の署名の行が残る: $body"
case "$body" in *'Co-Authored-By: Taro <taro@example.com>'*) ok "commit: 人の共同作者は残る" ;; *) ng "commit: 人の共同作者が消えた: $body" ;; esac
case "$body" in 'fix token check'*'Keeps the expiry check testable.'*) ok "commit: 件名と本文は残る" ;; *) ng "commit: 件名か本文が変わった: $body" ;; esac

git -C "$T/work" switch -q -c feature/x
git -C "$T/work" commit -q --allow-empty -m 'add x'
git -C "$T/work" switch -q main
git -C "$T/work" merge -q --no-ff -m "$MSG" feature/x
body="$(git -C "$T/work" log -1 --format=%B)"
[ "$(git -C "$T/work" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] && ok "merge: merge コミットができる" || ng "merge: merge コミットができていない"
[ "$(printf '%s\n' "$body" | ai)" = 0 ] && ok "merge: AI の署名の行が消える" || ng "merge: AI の署名の行が残る: $body"

repo "$T/private" ""
[ "$(git -C "$T/private" log -1 --format=%B | ai)" = 2 ] && ok "hooksPath なし: 署名の行は残る" || ng "hooksPath なし: 署名の行が消えた"

grep -q '署名' "$ROOT/config/agents/AGENTS.md" && ng "AGENTS.md に署名の記述が残っている" || ok "AGENTS.md に「署名を付けない」が無い"
grep -q 'hooksPath = ~/.config/git/hooks-nosign' "$ROOT/README.md" && ok "README に業務サーバーの hooksPath の手順がある" || ng "README に業務サーバーの hooksPath の手順が無い"

exit $fail
