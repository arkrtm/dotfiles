#!/bin/sh
# bin/harness-hook の検査。偽の hook 入力 JSON を流して、Stop の判定を確認する
#   sh tests/harness-hook.sh
set -eu
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bin/harness-hook"
export XDG_STATE_HOME="$(mktemp -d)"
REPO="$(mktemp -d)"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
SID="test-$$"
trap 'rm -rf "$XDG_STATE_HOME" "$REPO"' EXIT

fail=0
check() { # check <説明> <期待: block|pass> <実際の出力>
  case "$3" in
    *'"decision": "block"'*) got=block ;;
    *) got=pass ;;
  esac
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got): $3"; fail=1; fi
}
common() { printf '"session_id":"%s","cwd":"%s","transcript_path":"/dev/null"' "$SID" "$REPO"; }
turn() { printf '{%s,"hook_event_name":"UserPromptSubmit","prompt":"x"}' "$(common)" | "$HOOK" turn; }
edit() { printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(common)" "$1" | "$HOOK" edit; }
bash_() { printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(common)" "$1" | "$HOOK" bash; }
review() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s"}' "$(common)" "$1" | "$HOOK" review-done; }
stop() { printf '{%s,"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"%s"}' "$(common)" "${2:-false}" "${1:-done}" | "$HOOK" stop; }

turn
check "変更なしなら通す" pass "$(stop)"

turn; edit "$REPO/README.md"
check "ドキュメントだけの変更は通す" pass "$(stop)"

turn; edit "$REPO/src/app.py"
check "コード変更のみ → 差し戻す" block "$(stop)"
check "差し戻しの理由に TDD・検証・レビューが含まれる" block "$(stop | grep -c 'テスト.*検証.*レビュー\|TDD' >/dev/null && stop)"
check "stop_hook_active なら二度目は通す（ループ防止）" pass "$(stop done true)"

turn; edit "$REPO/src/app.py"; edit "$REPO/tests/test_app.py"; bash_ "uv run pytest -q"
check "テスト・検証ありでもレビュー未実施 → 差し戻す" block "$(stop)"
review "general-purpose"
check "別種のサブエージェント終了ではレビュー扱いにしない" block "$(stop)"
review "reviewer"
check "テスト・検証・レビューがそろえば通す" pass "$(stop)"

turn; edit "$REPO/src/app.py"; bash_ "cargo test"; review reviewer; edit "$REPO/src/app.py"
check "レビュー後に再編集 → 検証・レビューは無効になり差し戻す" block "$(stop)"

turn; edit "$REPO/src/app.py"; bash_ "ls tests"
check "ls tests は検証コマンドとみなさない" block "$(stop)"

turn; edit "$REPO/src/app.py"
check "『検証不要:』『レビュー不要:』『TDD不要:』を宣言すれば通す" pass "$(stop 'TDD不要: 設定値の変更のみ。検証不要: 同上。レビュー不要: 同上')"

# 前ターンにテストを書き、次ターンで実装するケース（TDD の証拠はセッション内で持ち越す）
turn; edit "$REPO/tests/test_x.py"
turn; edit "$REPO/src/x.py"; bash_ "pytest"; review reviewer
check "前ターンのテスト追加を TDD の証拠として認める" pass "$(stop)"

# git 上でテストファイルが変更されていれば、hook で見ていなくても TDD の証拠にする
turn; mkdir -p "$REPO/tests"; echo x > "$REPO/tests/test_git.py"; edit "$REPO/src/y.py"; bash_ "pytest"; review reviewer
check "git status のテストファイルも TDD の証拠として認める" pass "$(stop)"

# 作業別ブランチの強制（PreToolUse）
guard() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(common)" "$1" | "$HOOK" guard-branch; }
checkg() { case "$3" in *'"permissionDecision": "deny"'*) got=deny ;; *) got=allow ;; esac
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got): $3"; fail=1; fi; }
checkg "main 上の編集は拒否する（まだ無いディレクトリへの新規ファイルでも）" deny "$(guard "$REPO/src/new/app.py")"
checkg "git リポジトリ外の編集は許可する" allow "$(guard "$XDG_STATE_HOME/note.md")"
git -C "$REPO" switch -q -c feat/x
checkg "作業ブランチ上の編集は許可する" allow "$(guard "$REPO/src/app.py")"
git -C "$REPO" switch -q -c master
checkg "master 上の編集も拒否する" deny "$(guard "$REPO/src/app.py")"
git -C "$REPO" switch -q feat/x

[ -d "$XDG_STATE_HOME/harness/x" ] && { echo "FAIL prune が x ディレクトリを作っている"; fail=1; } || echo "ok   余計な状態ディレクトリを作らない"
grep -q "stop .*missing=" "$XDG_STATE_HOME/harness/log" && echo "ok   呼び出しログが残る" || { echo "FAIL 呼び出しログが無い"; fail=1; }

turn; printf 'not json' | "$HOOK" stop >/dev/null 2>&1; r=$?
[ "$r" = 0 ] && echo "ok   壊れた入力でも exit 0" || { echo "FAIL 壊れた入力で exit $r"; fail=1; }

exit $fail
