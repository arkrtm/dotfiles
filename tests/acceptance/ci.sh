#!/bin/sh
# GitHub の CI の受け入れ検査: check.yml が pull_request と main への push で `sh scripts/check` を実行すること（成否は終了コード。
# 消すと検査が走らなくても CI が success になる配線）。GitHub 側の設定（main の保護）は gh api で別に確かめる
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

exit $fail
