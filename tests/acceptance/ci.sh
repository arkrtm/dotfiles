#!/bin/sh
# GitHub の CI と main の保護の受け入れ検査（ARK-96・ARK-98）: ワークフローが pull_request と main への push で、ubuntu の
# ジョブ check に `sh scripts/check` を実行すること（成否は終了コード）。tests/README.md に main の保護（強制 push と削除の禁止だけ。
# 直接 push するので PR 必須・必須チェックは無し）とマージ方法を入れる gh api のコマンドがあり、AGENTS.md の Git の節が
# integrate setup を書いていること。GitHub 側の設定は gh api で別に確かめる
#   sh tests/acceptance/ci.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/ci.sh  通った項目も
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
check() { m="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$m"; else ng "$m"; fi; }

W="$ROOT/.github/workflows/check.yml"
check "ワークフロー .github/workflows/check.yml がある" [ -f "$W" ]
check "pull_request で走る" grep -qE '^  pull_request:' "$W"
check "main への push で走る" grep -qE '^    branches: \[main\]$' "$W"
check "ジョブの名前は check（main の保護の必須チェック名）" grep -qE '^  check:$' "$W"
check "ubuntu で動く" grep -qE '^    runs-on: ubuntu-latest$' "$W"
check "sh scripts/check を実行する（成否は終了コード）" grep -qE '^      - run: sh scripts/check$' "$W"
check "失敗を握りつぶさない（continue-on-error・|| true が無い）" sh -c "! grep -qE 'continue-on-error|\|\| *true' '$W'"

R="$ROOT/tests/README.md"
check "tests/README.md に main の保護を入れる gh api がある" grep -qF 'gh api -X PUT repos/arkrtm/dotfiles/branches/main/protection' "$R"
check "tests/README.md の保護は強制 push と削除の禁止だけ（PR 必須・必須チェック・管理者への適用は無し）" \
  sh -c "grep -qF '\"required_status_checks\":null' '$R' && grep -qF '\"enforce_admins\":false' '$R' && grep -qF '\"required_pull_request_reviews\":null' '$R' && grep -qF '\"allow_force_pushes\":false' '$R' && grep -qF '\"allow_deletions\":false' '$R'"
check "tests/README.md にマージ方法（rebase だけ・ブランチ自動削除）を入れる gh api がある" \
  sh -c "grep -qF 'allow_squash_merge=false' '$R' && grep -qF 'allow_merge_commit=false' '$R' && grep -qF 'delete_branch_on_merge=true' '$R'"
check "AGENTS.md の Git の節が integrate setup を書いている" sh -c "sed -n '/^## Git/,/^## /p' '$ROOT/config/agents/AGENTS.md' | grep -qF 'integrate setup'"

exit $fail
