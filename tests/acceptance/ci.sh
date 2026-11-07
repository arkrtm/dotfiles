#!/bin/sh
# GitHub の CI の受け入れ検査: check.yml が pull_request と main への push で `sh scripts/check` を実行すること（成否は終了コード。
# 消すと検査が走らなくても CI が success になる配線）。全ワークフローの不変条件: uses は SHA で固定、permissions は contents: read、
# ジョブごとに timeout-minutes、pipx install は版を固定、失敗を握りつぶさない。GitHub 側の設定（main の保護）は gh api で別に確かめる
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
check "sh scripts/check を実行する（成否は終了コード）" grep -qE '^      - run: sh scripts/check$' "$W"

# ---- 全ワークフローの不変条件
loose_uses() { ! grep -E '^[[:space:]-]*uses:' "$1" | grep -vE '@[0-9a-f]{40}([[:space:]]|$)'; }
read_only() { grep -qx 'permissions:' "$1" && grep -qx '  contents: read' "$1"; }
job_timeouts() { j="$(grep -c '^    runs-on:' "$1")"; [ "$j" -ge 1 ] && [ "$j" = "$(grep -cE '^    timeout-minutes: [0-9]+$' "$1")" ]; }
pinned_pipx() { ! grep -oE 'pipx install [^ ]+' "$1" | grep -v '=='; }
no_swallow() { ! grep -qE 'continue-on-error|\|\| *true' "$1"; }
for W in "$ROOT"/.github/workflows/*.yml; do
  w="${W#"$ROOT"/}"
  check "$w: uses は 40 桁の SHA で固定する" loose_uses "$W"
  check "$w: permissions に contents: read がある" read_only "$W"
  check "$w: ジョブごとに timeout-minutes がある" job_timeouts "$W"
  check "$w: pipx install は版を固定する" pinned_pipx "$W"
  check "$w: 失敗を握りつぶさない（continue-on-error・|| true が無い）" no_swallow "$W"
done

# main の保護とマージ方法の値（新しいリポジトリで tests/README.md の gh api を実行する。値を誤ると強制 push や削除を許す）
R="$ROOT/tests/README.md"
check "tests/README.md に main の保護を入れる gh api がある" grep -qF 'gh api -X PUT repos/arkrtm/dotfiles/branches/main/protection' "$R"
check "tests/README.md の保護は強制 push と削除の禁止だけ（PR 必須・必須チェック・管理者への適用は無し）" \
  sh -c "grep -qF '\"required_status_checks\":null' '$R' && grep -qF '\"enforce_admins\":false' '$R' && grep -qF '\"required_pull_request_reviews\":null' '$R' && grep -qF '\"allow_force_pushes\":false' '$R' && grep -qF '\"allow_deletions\":false' '$R'"
check "tests/README.md にマージ方法（rebase だけ・ブランチ自動削除）を入れる gh api がある" \
  sh -c "grep -qF 'allow_squash_merge=false' '$R' && grep -qF 'allow_merge_commit=false' '$R' && grep -qF 'delete_branch_on_merge=true' '$R'"

exit $fail
