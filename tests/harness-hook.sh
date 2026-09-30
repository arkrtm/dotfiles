#!/bin/sh
# bin/harness-hook の検査。実際の git リポジトリを変更しつつ偽の hook 入力を流し、判定を確認する
#   sh tests/harness-hook.sh
set -eu
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bin/harness-hook"
export XDG_STATE_HOME="$(mktemp -d)"
REPO="$(mktemp -d)"
G="git -C $REPO -c user.name=t -c user.email=t@t"
$G init -q -b main
$G commit -q --allow-empty -m init
$G switch -q -c feat/x
SID="test-$$"
trap 'rm -rf "$XDG_STATE_HOME" "$REPO"' EXIT

fail=0
check() { # check <説明> <期待: block|pass> <実際の出力>
  case "$3" in *'"decision": "block"'*) got=block ;; *) got=pass ;; esac
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got): $3"; fail=1; fi
}
common() { printf '"session_id":"%s","cwd":"%s","transcript_path":"/dev/null"' "$SID" "$REPO"; }
turn() { printf '{%s,"hook_event_name":"UserPromptSubmit","prompt":"x"}' "$(common)" | "$HOOK" turn; }
edit() { printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(common)" "$1" | "$HOOK" edit; }
bash_() { printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"exit_code":%s}}' "$(common)" "$1" "${2:-0}" | "$HOOK" bash; }
review() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s"}' "$(common)" "$1" | "$HOOK" review-done; }
stop() { printf '{%s,"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"%s"}' "$(common)" "${2:-false}" "${1:-done}" | "$HOOK" stop; }
write() { mkdir -p "$(dirname "$REPO/$1")"; echo "$2" > "$REPO/$1"; }
clean() { $G reset -q --hard; $G clean -qfd; }

turn
check "変更なし・ツール未使用なら通す" pass "$(stop)"

turn; write README.md doc; edit "$REPO/README.md"
check "ドキュメントだけの変更は通す" pass "$(stop)"
clean

turn; write src/app.py code; edit "$REPO/src/app.py"
check "コード変更のみ → 差し戻す" block "$(stop)"
check "差し戻しの理由に TDD が含まれる" block "$(stop | grep -q TDD && stop)"
check "stop_hook_active なら二度目は通す（ループ防止）" pass "$(stop done true)"

# Edit ツールを使わず Bash（sed -i 等）で書き換えた場合も、git の状態から検出する
turn; write src/app.py code2; bash_ "sed -i s/a/b/ src/app.py"
check "Bash で編集しても（Edit hook が無くても）差し戻す" block "$(stop)"

turn; write tests/test_app.py t; edit "$REPO/tests/test_app.py"; bash_ "uv run pytest -q"
check "テスト・検証ありでもレビュー未実施 → 差し戻す" block "$(stop)"
review "general-purpose"
check "別種のサブエージェント終了ではレビュー扱いにしない" block "$(stop)"
review reviewer
check "テスト・検証・レビューがそろえば通す" pass "$(stop)"

turn; bash_ "echo unrelated"
check "変更が残っていても、その後のターンで手を加えなければ通す" pass "$(stop)"

turn; write src/app.py code3; bash_ "sed -i s/b/c/ src/app.py"
check "レビュー後に（Bash で）再編集 → 検証・レビューは無効になり差し戻す" block "$(stop)"
bash_ "cargo test"; review reviewer
check "再検証・再レビューすれば通す" pass "$(stop)"

turn; write src/app.py code4; bash_ "uv run pytest -q" 1
check "検証コマンドが失敗した場合は検証済みにしない" block "$(stop)"

turn; write src/app.py code5; bash_ "ls tests"
check "ls tests は検証コマンドとみなさない" block "$(stop)"

turn; bash_ "sed -i s/x/y/ src/app.py"
check "『検証不要:』などの宣言では通さない（逃げ道なし）" block "$(stop 'TDD不要: 設定値の変更のみ。検証不要: 同上。レビュー不要: 同上')"

# コミットの関門（PreToolUse Bash）: 証拠がそろうまで git commit を拒否する
gcommit() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(common)" "$1" | "$HOOK" guard-commit; }
checkc() { case "$3" in *'"permissionDecision": "deny"'*) got=deny ;; *) got=allow ;; esac
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got): $3"; fail=1; fi; }
checkc "証拠なしの git commit は拒否する" deny "$(gcommit "git add -A && git commit -m x")"
checkc "git commit 以外のコマンドは通す" allow "$(gcommit "git status && git diff")"
checkc "git log --grep commit のような閲覧は通す" allow "$(gcommit "git log --grep commit")"
checkc "git -C dir commit も拒否する" deny "$(gcommit "git -C . commit -m x")"
write tests/test_app.py t2; bash_ "uv run pytest -q"; review reviewer
checkc "テスト・検証・レビューがそろえば git commit を通す" allow "$(gcommit "git commit -am x")"
write src/app.py code6
checkc "コミット前に再編集すれば再び拒否する" deny "$(gcommit "git commit -am x")"
clean
write README.md doc2
checkc "ドキュメントだけの変更のコミットは通す" allow "$(gcommit "git commit -am docs")"
clean

# テストを先にコミットし、次のターンで実装するケース: ブランチ上の差分からテスト変更を認める
turn; write tests/test_y.py t; $G add -A; $G commit -q -m "test first"
turn; write src/y.py impl; bash_ "pytest"; review reviewer
check "コミット済みのテスト追加も TDD の証拠として認める" pass "$(stop)"
clean

# main 上の変更は Stop でも差し戻す（Edit 以外の経路の保険）
$G switch -q main; turn; write src/z.py impl; write tests/test_z.py t; bash_ "pytest"; review reviewer
check "main 上で変更していれば、証拠がそろっていても差し戻す" block "$(stop)"
clean; $G switch -q feat/x

# 作業別ブランチの強制（PreToolUse）
guard() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(common)" "$1" | "$HOOK" guard-branch; }
checkg() { case "$3" in *'"permissionDecision": "deny"'*) got=deny ;; *) got=allow ;; esac
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got): $3"; fail=1; fi; }
checkg "作業ブランチ上の編集は許可する" allow "$(guard "$REPO/src/app.py")"
checkg "git リポジトリ外の編集は許可する" allow "$(guard "$XDG_STATE_HOME/note.md")"
$G switch -q main
checkg "main 上の編集は拒否する（まだ無いディレクトリへの新規ファイルでも）" deny "$(guard "$REPO/src/new/app.py")"
$G switch -q -c master
checkg "master 上の編集も拒否する" deny "$(guard "$REPO/src/app.py")"
$G switch -q feat/x

[ -d "$XDG_STATE_HOME/harness/x" ] && { echo "FAIL 余計な状態ディレクトリを作っている"; fail=1; } || echo "ok   余計な状態ディレクトリを作らない"
grep -q "stop .*missing=" "$XDG_STATE_HOME/harness/log" && echo "ok   呼び出しログが残る" || { echo "FAIL 呼び出しログが無い"; fail=1; }

turn; printf 'not json' | "$HOOK" stop >/dev/null 2>&1; r=$?
[ "$r" = 0 ] && echo "ok   壊れた入力でも exit 0" || { echo "FAIL 壊れた入力で exit $r"; fail=1; }

exit $fail
