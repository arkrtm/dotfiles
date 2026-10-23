#!/bin/sh
# GitHub の CI と main の保護の受け入れ検査（ARK-96）: ワークフローが pull_request と main への push で、ubuntu の
# ジョブ check に `sh scripts/check` を実行すること（成否は終了コード）。README に main の保護とマージ方法を入れる
# gh api のコマンドがあり、AGENTS.md の Git の節が CI 必須の保護を書いていること。GitHub 側の設定は gh api で別に確かめる
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

R="$ROOT/README.md"
check "README に main の保護を入れる gh api がある" grep -qF 'gh api -X PUT repos/arkrtm/dotfiles/branches/main/protection' "$R"
check "README の保護は必須チェック check・管理者にも適用・直線の履歴" sh -c "grep -qF '\"contexts\":[\"check\"]' '$R' && grep -qF '\"enforce_admins\":true' '$R' && grep -qF '\"required_linear_history\":true' '$R'"
check "README にマージ方法（rebase だけ・ブランチ自動削除）を入れる gh api がある" \
  sh -c "grep -qF 'allow_squash_merge=false' '$R' && grep -qF 'allow_merge_commit=false' '$R' && grep -qF 'delete_branch_on_merge=true' '$R'"
check "AGENTS.md の Git の節が CI 必須の main の保護を書いている" grep -qF 'main は CI（`scripts/check`）必須で保護' "$ROOT/config/agents/AGENTS.md"

exit $fail
