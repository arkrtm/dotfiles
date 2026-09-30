#!/bin/sh
# bin/harness-hook と config/git/hooks/run-hook の検査。
# 隔離した HOME と一時リポジトリで、実際の git と、実物と同じ形の hook 入力を使って判定を確認する
#   sh tests/harness-hook.sh      失敗した項目と要約 1 行だけを出す（実行のたびにコンテキストを食わないように）
#   sh tests/harness-hook.sh -v   通った項目も出す
set -eu
VERBOSE=; [ "${1:-}" != -v ] || VERBOSE=1
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DOTFILES/bin/harness-hook"
HOOKS="$DOTFILES/config/git/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# hook は $HOME/.local/libexec/uv で動く。隔離した HOME では mise の shim が使えないので、先に uv の実体を控える
UV="$HOME/.local/libexec/uv"; [ -x "$UV" ] || UV="$(mise which uv 2>/dev/null || true)"
[ -x "$UV" ] || { echo "FAIL uv の実体が見つからない（dotfiles の install.sh を実行すること）"; exit 1; }
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}" # uv 管理の Python も元の HOME のものを使う（毎回ダウンロードしない）
export XDG_STATE_HOME="$TMP/state"
export HOME="$TMP/home"                       # 利用者のグローバル git 設定・インストール済み hook から隔離する
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM 2>/dev/null || true
export CLAUDECODE=1                           # Claude Code から実行されたコミットとして扱わせる
mkdir -p "$HOME/.local/bin"; ln -s "$HOOK" "$HOME/.local/bin/harness-hook"   # run-hook が呼ぶ実体をテスト対象にする
mkdir -p "$HOME/.local/libexec"; ln -s "$UV" "$HOME/.local/libexec/uv"
REPO="$TMP/repo"; mkdir -p "$REPO/tests" "$REPO/src"
G="git -C $REPO -c user.name=t -c user.email=t@t"
GH="$G -c core.hooksPath=$HOOKS"              # 共通 hooks 経由（本番は ~/.config/git/config の設定で有効になる）
$G init -q -b main
echo base > "$REPO/tests/test_base.py"; echo lib > "$REPO/src/lib.py"; printf '#!/bin/sh\necho tool\n' > "$REPO/tool"
$G add -A; $G commit -q -m init
$G switch -q -c feat/x
SID="test-$$"

passed=0; fail=0
ok() { passed=$((passed + 1)); [ -z "$VERBOSE" ] || echo "ok   $1"; }
ng() { fail=$((fail + 1)); echo "FAIL $1"; }
EXPECTED_ERRORS=0   # hook が例外で終わることを意図したテストの数（最後に突き合わせる）
judge() { # judge <説明> <期待> <肯定側の印> <肯定名> <否定名> <実際の出力>
  case "$6" in *"$3"*) got=$4 ;; *) got=$5 ;; esac
  if [ "$got" = "$2" ]; then ok "$1"; else ng "$1 (expected $2, got $got): $6"; fi
}
check() { judge "$1" "$2" '"decision": "block"' block pass "$3"; }             # Stop: block|pass
checkd() { judge "$1" "$2" '"permissionDecision": "deny"' deny allow "$3"; }  # PreToolUse: deny|allow
checkx() { # checkx <説明> <期待する終了コード 0|1> <コマンド…>
  desc=$1; want=$2; shift 2
  if "$@" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (expected exit $want, got $got)"; fi
}
expect() { # expect <説明> <test の条件…>
  desc=$1; shift
  if "$@"; then ok "$desc"; else ng "$desc"; fi
}
# hook 入力（実物と同じ形: Bash の tool_response に exit_code は無い）
common() { printf '"session_id":"%s","cwd":"%s","transcript_path":"%s"' "$SID" "${CWD:-$REPO}" "${TRANSCRIPT:-/dev/null}"; }
turn() { printf '{%s,"hook_event_name":"UserPromptSubmit","prompt":"x"}' "$(common)" | "$HOOK" turn; }
bash_() { # bash_ <command> [tool_input への追加 JSON] [interrupted]
  printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"%s},"tool_response":{"stdout":"","stderr":"","interrupted":%s}}' "$(common)" "$1" "${2:-}" "${3:-false}" | "$HOOK" bash; }
OK3='## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'   # reviewer の出力（3 軸とも承認）。\n は JSON の改行
review() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s","last_assistant_message":"%s"}' "$(common)" "$1" "${2-$OK3}" | "$HOOK" review-done; }
review_handback() { # 報告をツール呼び出し（SubagentHandback）で返す環境: 最後のテキストに判定文は無く、サブエージェントの記録にある
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SubagentHandback","input":{"message":"%s"}}]}}\n{"message":{"role":"assistant","content":[{"type":"text","text":"報告を返しました"}]}}\n' "$1" > "$TMP/agent.jsonl"
  printf '{%s,"hook_event_name":"SubagentStop","agent_type":"reviewer","last_assistant_message":"報告を返しました","agent_transcript_path":"%s"}' "$(common)" "$TMP/agent.jsonl" | "$HOOK" review-done; }
review_from() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"reviewer","last_assistant_message":"","agent_transcript_path":"%s"}' "$(common)" "$1" | "$HOOK" review-done; }  # 判定は記録からだけ読める
log_count() { grep -c "$1" "$XDG_STATE_HOME/harness/log" || true; }
stop() { printf '{%s,"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"%s"}' "$(common)" "${2:-false}" "${1:-done}" | "$HOOK" stop; }
guardb() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(common)" "$1" | "$HOOK" guard-bash; }
guarde() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(common)" "$1" | "$HOOK" guard-branch; }
precommit() { (cd "$REPO" && "$HOOK" pre-commit); }
write() { mkdir -p "$(dirname "$REPO/$1")"; echo "$2" > "$REPO/$1"; }
fresh() { $G reset -q --hard; $G clean -qfd; turn; }                 # きれいな作業ツリーで新しいターンを始める
ready() { write src/app.py "$1"; write tests/test_app.py "$1"; bash_ "uv run pytest -q"; review reviewer; }  # 証拠がそろった状態

# ---- Stop（完了の差し戻し）----
fresh
check "変更なしなら通す" pass "$(stop)"
fresh; write README.md doc
check "ドキュメントだけの変更は通す" pass "$(stop)"
fresh; write notes doc
check "拡張子も shebang も無いファイルはコード扱いしない" pass "$(stop)"
fresh; printf '#!/bin/sh\necho hi\n' > "$REPO/bin-tool"
check "拡張子の無い shebang 付きスクリプトはコード変更として扱う" block "$(stop)"
fresh; write "src/日本語.py" code
check "非 ASCII のパスでもコード変更として検出する" block "$(stop)"
fresh; write newpkg/sub/mod.py code
check "新しいディレクトリ配下の新規コードも検出する" block "$(stop)"
fresh; rm "$REPO/tool"
check "拡張子の無いスクリプトの削除もコード変更として検出する" block "$(stop)"
$G add -A
checkx "同じく、削除をステージしたコミットにも証拠が要る" 1 precommit
fresh; echo "no shebang now" > "$REPO/tool"
check "shebang を消す書き換えもコード変更として検出する" block "$(stop)"
fresh; write src/APP.PY code
check "大文字の拡張子でもコードとして検出する" block "$(stop)"
fresh; ready fx; write tests/data/x.json '{}'
check "証拠を取った後にテスト資材（コード以外）を変えても、証拠は無効になる" block "$(stop)"

fresh; write src/app.py code
check "コード変更のみ → 差し戻す" block "$(stop)"
check "差し戻しの理由に、足りない証拠（/verify と /review）が含まれる" block "$(stop | grep /verify | grep /review)"
check "差し戻しの理由に、ユーザーの判断を待つならその旨を書いて終えてよいことが含まれる" block "$(stop | grep 'ユーザーの判断を待つ')"
check "stop_hook_active なら二度目は通す（ループ防止）" pass "$(stop done true)"
check "『検証不要:』などの宣言では通さない" block "$(stop 'TDD不要: x。検証不要: x。レビュー不要: x')"
$G add -A
expect "（前提）同じ変更をステージすると pre-commit は理由を出して拒否する" [ -n "$(precommit 2>&1 | grep 'コミットできない' || true)" ]
expect "pre-commit の拒否文には、ターンを終えてよいという一文を含めない（Stop の差し戻しだけ）" [ -z "$(precommit 2>&1 | grep 'ユーザーの判断を待つ' || true)" ]

fresh; write src/app.py old; turn; bash_ "ls"
check "以前からの未コミット変更があっても、このターンで変えていなければ差し戻さない" pass "$(stop)"
write README.md doc; $G add README.md; $G commit -q -m docs
check "そのターンでドキュメントだけコミットしても（HEAD が動いても）差し戻さない" pass "$(stop)"
if [ "$(id -u)" != 0 ]; then   # root は chmod 000 のファイルも読めるので、この検査は成り立たない
  fresh; write src/app.py c; write tests/test_app.py t; write src/locked.py x; chmod 000 "$REPO/src/locked.py"; bash_ "uv run pytest -q"; review reviewer
  check "読めないファイルがあって指紋を作れないときは、証拠を記録せず差し戻す" block "$(stop)"
  EXPECTED_ERRORS=$((EXPECTED_ERRORS + 2))   # 上の bash と review-done は指紋を作れず例外で終わる（だから証拠が記録されない）
  chmod 644 "$REPO/src/locked.py"
fi

fresh; write src/app.py code; write tests/test_app.py t; bash_ "uv run pytest -q"
check "テスト・検証ありでもレビュー未実施 → 差し戻す" block "$(stop)"
review general-purpose
check "別種のサブエージェント終了ではレビュー扱いにしない" block "$(stop)"
review reviewer '仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
check "仕様適合が『修正が必要』ならレビュー済みにしない" block "$(stop)"
review reviewer '仕様適合: 承認\nテスト: 修正が必要\n品質・保守性: 承認'
check "テスト（TDD）が『修正が必要』ならレビュー済みにしない" block "$(stop)"
review reviewer '仕様適合: 承認\n品質・保守性: 承認'
check "判定行が 3 軸そろっていなければレビュー済みにしない" block "$(stop)"
review reviewer ""
check "reviewer の出力が空（中断・異常終了）ならレビュー済みにしない" block "$(stop)"
review reviewer "レビュー対象の変更がない"
check "判定行の無い出力ではレビュー済みにしない" block "$(stop)"
review reviewer '仕様適合: 承認できない（差分を読めず）\nテスト: 承認\n品質・保守性: 承認'
check "『承認できない』は承認ではない" block "$(stop)"
review reviewer '仕様適合: 承認 | 修正が必要\nテスト: 承認 | 修正が必要\n品質・保守性: 承認 | 修正が必要'
check "出力形式のひな型行をそのまま出しても承認ではない" block "$(stop)"
review reviewer '- [中] 先の報告では 仕様適合: 承認 と書いたが誤り\n仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
check "指摘文の中で判定行を引用していても、判定行が『修正が必要』なら承認ではない" block "$(stop)"
review reviewer '作業中の差分\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認\nブランチ全体\n仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
check "判定のブロックが複数あり、1 つでも『修正が必要』なら承認ではない" block "$(stop)"
review reviewer '前回の判定:\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認\n今回の判定:\n仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
check "以前の判定を行単位で引用していても、今回の判定が『修正が必要』なら承認ではない" block "$(stop)"
review reviewer '## 指摘\n- [軽] 将来は修正が必要かもしれない\n## 判定\n- 仕様適合: **承認**\nテスト: 承認\n品質・保守性: 承認'
check "3 軸とも承認なら、指摘文に『修正が必要』の語があってもレビュー済みにする（箇条書き・強調も可）" pass "$(stop)"
# /review fix（範囲限定の再レビュー）の出力形式。reviewer.md は根拠の行を軸名で始めることを禁じている（判定と読まれるため）
write src/app.py code1n; bash_ "uv run pytest -q"
review reviewer 'レビューした版: 4b825dc\n\n## 指摘ごとの判定\n- [R1-2] 直った — 根拠 src/app.py:3\n- テスト: sh tests/x.sh 成功\n\n## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
check "根拠の行を軸名で始めると判定と読まれ、承認にならない" block "$(stop)"
review reviewer 'レビューした版: 4b825dc\n\n## 指摘ごとの判定\n- [R1-2] 直った — 根拠 src/app.py:3\n- [R1-3] 直っていない — のちに修正が必要 src/app.py:9\n\n## 修正による新しい問題\n- [R2-1] [軽] [テスト] tests/test_app.py:12 — 名前が曖昧\n\n## ユーザー判断で見送り\n- [R1-3] 裁定: 対象外の環境なので見送り\n\n## 範囲外\n- src/other.py:5 — 修正が必要になりそうな箇所\n\n未解決: なし\n\n## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
check "範囲限定の再レビューの出力形式（見送り・範囲外の節つき）は、3 軸とも承認なら承認として読む" pass "$(stop)"
write src/app.py code1b; bash_ "uv run pytest -q"
check "（再編集後）レビューが無効になっている" block "$(stop)"
review_handback '## 判定\n仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
check "報告がハンドバック経由で『修正が必要』ならレビュー済みにしない" block "$(stop)"
review_handback '## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
check "報告がハンドバック経由（最後のテキストに判定文が無い）でも、記録から判定を読んでレビュー済みにする" pass "$(stop)"
write src/app.py code1c; bash_ "uv run pytest -q"
# 再開された reviewer: 前回は承認、今回の依頼の後は判定を出さずに終わった（想定外の形の行も混ぜる）
resumed() { # resumed <新しい依頼の行（空なら入れない）>
  { printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認"}]}}'
    [ -z "$1" ] || printf '%s\n' "$1"
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"x"}}]}}' \
      '{"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}' \
      '[1,2]' '{"message":{"role":"assistant","content":["中断"]}}' \
      '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SubagentHandback","input":"壊れた入力"}]}}'
  } > "$TMP/resumed.jsonl"; review_from "$TMP/resumed.jsonl"; }
before=$(log_count "review-done .*approved=False")
resumed '{"message":{"role":"user","content":"もう一度レビューして"}}'
check "記録に以前の承認があっても、今回の依頼の後に判定が無ければレビュー済みにしない" block "$(stop)"
expect "そのときも review-done のログが 1 行残る（記録に想定外の行があっても落ちない）" [ "$(log_count "review-done .*approved=False")" = "$((before + 1))" ]
resumed '{"message":{"role":"user","content":[{"type":"text","text":"もう一度レビューして"}]}}'
check "新しい依頼がブロック形式（content がリスト）でも同じ" block "$(stop)"
resumed ''
check "（前提）同じ記録でも、新しい依頼の行が無ければ承認として読める" pass "$(stop)"
write src/app.py code1d; bash_ "uv run pytest -q"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"cat <<E\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認\nE"}}]}}' > "$TMP/quoted.jsonl"; review_from "$TMP/quoted.jsonl"
check "reviewer が途中で実行したコマンドの中の判定行は、報告として読まない" block "$(stop)"
review reviewer
check "テスト・検証・レビュー承認がそろえば通す" pass "$(stop)"
expect "review-done は承認の可否を 1 行でログに残す" grep -q "review-done .*approved=True" "$XDG_STATE_HOME/harness/log"
write src/app.py code2
check "その後に再編集すれば検証・レビューは無効になり差し戻す" block "$(stop)"
bash_ "cargo test"; review reviewer
check "再検証・再レビューすれば通す" pass "$(stop)"
# reviewer の報告は承認・不承認に関わらず <git-dir>/harness-last-review に保存する（次の /review fix で前回の報告として読む）
review reviewer '仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
expect "review-done は reviewer の報告を .git/harness-last-review に保存する（不承認でも）" grep -q "仕様適合: 修正が必要" "$REPO/.git/harness-last-review"
review reviewer
expect "次の review-done で上書きされる" [ "$(cat "$REPO/.git/harness-last-review")" = "$(printf "$OK3")" ]

# 検証として認める／認めないコマンドの形
# 証拠は内容の指紋で持つので、ケースごとに内容を変える（同じ内容だと前のケースの「検証済み」が一致してしまう）
n=0
reviewed_only() { n=$((n + 1)); fresh; write src/app.py "v$n"; write tests/test_app.py "v$n"; review reviewer; }
for c in "uv run pytest -q" "time uv run pytest -q" "cd $REPO && uv run pytest -q" "just test" "./gradlew test" "mvn -q test" "sh tests/run.sh" "npm run lint" \
  "uv run python -m pytest" "uv run --extra dev pytest -q" "timeout 60 pytest" "make -C sub test" "./tests/run.sh" "sh -x tests/run.sh" "node --test" "pytest -q 2>&1" \
  "bundle exec rspec" "mix test" "python3.12 -m pytest" "pnpm lint" "uvx ruff check ."; do
  reviewed_only; bash_ "$c"
  check "検証として認める: $c" pass "$(stop)"
done
for c in "uv run pytest -q 2>&1 | tail -3" "pytest -q || echo done" "pytest -q; echo done" "pytest --co" "pytest --version" \
  "pytest -q >/dev/null" "nvim --headless +q" "sh -n src/app.py" "ls tests" "cd $REPO\\nuv run pytest -q" \
  "pytest -q &" "echo time pytest" "grep -rn pytest ." "ruff format ." "cat tests/test_app.py" "sh -n tests/run.sh" "OUT=tests/out.txt ls"; do
  reviewed_only; bash_ "$c"
  check "検証として認めない: $(printf '%s' "$c" | tr '\\' ' ')" block "$(stop)"
done
reviewed_only; bash_ "uv run pytest -q" ',"run_in_background":true'
check "バックグラウンド実行は検証として認めない" block "$(stop)"
reviewed_only; printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"uv run pytest -q"},"tool_response":{"stdout":"","stderr":"","interrupted":false,"backgroundTaskId":"b1"}}' "$(common)" | "$HOOK" bash
check "実行中にバックグラウンドへ回された（終了前の）実行も検証として認めない" block "$(stop)"
reviewed_only; bash_ "uv run pytest -q" "" true
check "中断された実行は検証として認めない" block "$(stop)"
reviewed_only; printf '{%s,"agent_id":"a1","agent_type":"implementer","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"uv run pytest -q"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}' "$(common)" | "$HOOK" bash
check "サブエージェント内（agent_id あり）の検証の成功は記録しない" block "$(stop)"
reviewed_only; bash_ "uv run pytest -q"; n_same=$n; fresh; write src/app.py "v$n_same"; write tests/test_app.py "v$n_same"
check "同じ内容に戻せば、以前の検証・レビューがそのまま有効（指紋は内容で決まる）" pass "$(stop)"

# 検証コマンドの失敗（PostToolUseFailure）は、その作業ツリーの「検証済み」を消す
bash_fail() { printf '{%s,"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"%s"},"error":"Exit code 1","is_interrupt":false}' "$(common)" "$1" | "$HOOK" bash-failed; }
fresh; ready vf1; bash_fail "ls nothing"
check "検証コマンドでないコマンドの失敗では、検証済みは消えない" pass "$(stop)"
bash_fail "uv run pytest -q 2>&1 | tail -3"
check "同じ内容で検証コマンドが失敗すれば（パイプ付きの形でも）、検証済みが消えて差し戻す" block "$(stop)"
$G add -A
checkx "同じく、pre-commit も失敗する" 1 precommit

# 宣言した検証コマンド（リポジトリのトップの .harness-verify）: 書かれたコマンドがすべて同じ内容で成功したときだけ検証済み
fresh; printf '# 宣言した検証コマンド\nsh tests/run.sh\n\n./ci.sh\n' > "$REPO/.harness-verify"; write src/app.py hv1; review reviewer
bash_ "uv run pytest -q"
check "宣言があれば、宣言に無い検証コマンドの成功は証拠にならない" block "$(stop)"
bash_ "sh tests/run.sh"
check "宣言した 2 つのうち 1 つだけの成功では差し戻す" block "$(stop)"
bash_ "cd $REPO && ./ci.sh"
check "もう 1 つも成功すれば通す（先頭の cd … && を除いて比べる。検証コマンドの形でなくてよい）" pass "$(stop)"
write src/app.py hv2; review reviewer; bash_ "./ci.sh"
check "その後に内容を変えると、両方やり直しになる" block "$(stop)"
bash_ "sh tests/run.sh"
check "（前提）両方をやり直せば通す" pass "$(stop)"
$G add -A
checkx "同じく、宣言したコマンドがすべて成功した内容をステージすればコミットできる" 0 precommit
bash_fail "./ci.sh"
check "宣言したコマンドの失敗でも、検証済みは消える" block "$(stop)"

# テストが十分か（TDD）は reviewer が判定する。hook はテストファイルの有無を見ない
fresh; write src/app.py refactor-only; bash_ "uv run pytest -q"; review reviewer
check "コードだけの変更（リファクタ等）でも、検証と 3 軸の承認があれば通す" pass "$(stop)"
$G add -A
checkx "同じく、コードだけの変更でもコミットできる" 0 precommit
# テストだけの変更は対象外
for t in tests/test_x.py Tests/FooTests/FooTests.swift Foo.Tests/BarTests.cs src/test/java/FooTest.java pkg/foo_test.go; do
  fresh; write "$t" t
  check "テストだけの変更は差し戻さない: $t" pass "$(stop)"
done
fresh; write src/latest.js c
check "名前が test で終わるだけのコード（latest.js）はテスト扱いしない" block "$(stop)"
# 既存のテストの変更・削除はテストを弱めうるので、テスト以外のコードの変更が無くても証拠を求める（テストの追加だけなら対象外）
fresh; echo weakened > "$REPO/tests/test_base.py"
check "既存のテストの変更は差し戻す" block "$(stop)"
bash_ "uv run pytest -q"; review reviewer
check "（前提）証拠がそろえば通す" pass "$(stop)"
fresh; rm "$REPO/tests/test_base.py"
check "既存のテストの削除は差し戻す" block "$(stop)"
$G add -A
checkx "同じく、既存のテストの削除をステージしたコミットにも証拠が要る" 1 precommit
fresh; write tests/test_added.py t; $G add -A
checkx "新しいテストの追加だけなら、コミットに証拠は要らない" 0 precommit

# 設定ファイル・ビルド定義もコード
for f in pyproject.toml package.json compose.yaml .github/workflows/ci.yml tox.ini setup.cfg src/m.mts src/m.cts run.bash \
  Dockerfile sub/Makefile justfile; do
  fresh; write "$f" x
  check "設定ファイル・ビルド定義だけの変更も差し戻す: $f" block "$(stop)"
done
# リポジトリのトップの .harness-code（1 行 1 パターン、fnmatch の * は / にも当たる）に当たるパスもコード
fresh; printf '# 関門の対象に加えるパス\nconfig/claude/*\n\n' > "$REPO/.harness-code"
check ".harness-code 自体の追加も差し戻す" block "$(stop)"
$G add .harness-code; $G commit -q -m harness-code
fresh; write config/claude/skills/x/SKILL.md doc
check ".harness-code のパターンに当たる Markdown は差し戻す（* は / にも当たる）" block "$(stop)"
$G add -A
checkx "同じく、ステージしたコミットにも証拠が要る" 1 precommit
fresh; write docs/x.md doc
check ".harness-code のパターンに当たらない Markdown は通す" pass "$(stop)"
fresh; printf '# 空にする\n' > "$REPO/.harness-code"
check ".harness-code 自体の変更（関門を弱める変更）も差し戻す" block "$(stop)"
fresh; write .harness-verify "make test"
check ".harness-verify 自体の変更も差し戻す" block "$(stop)"
$G rm -q .harness-code; $G commit -q -m rm-harness-code

# cwd がサブディレクトリでも、判定はリポジトリのトップレベルで行う
fresh; mkdir -p "$REPO/src"; CWD="$REPO/src"; turn; write src/deep.py c; write tests/test_deep.py t; bash_ "pytest"; review reviewer
check "cwd がサブディレクトリでも証拠を正しく突き合わせる" pass "$(stop)"
write src/deep.py c2
check "サブディレクトリ cwd で未追跡コードを書き換えると証拠は無効になる" block "$(stop)"
CWD=""

# ---- コミットの関門（pre-commit。判定対象はステージ済みの内容）----
fresh; write src/app.py c; $G add -A
checkx "証拠なしの pre-commit は失敗する" 1 precommit
checkx "人の手動コミット（CLAUDECODE なし）は対象外" 0 env -u CLAUDECODE sh -c "cd '$REPO' && '$HOOK' pre-commit"
for ref in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  $G rev-parse HEAD > "$REPO/.git/$ref"
  checkx "競合解消の締めのコミット（$ref あり）は対象外" 0 precommit
  rm "$REPO/.git/$ref"
done
checkx "（前提）上の ref が無ければ失敗する" 1 precommit
OTHER="$TMP/other"; git init -q -b feat "$OTHER"; echo c > "$OTHER/app.py"; git -C "$OTHER" add -A
checkx "Claude が作業していないリポジトリ（テストが作る一時リポジトリ等）は対象外" 0 sh -c "cd '$OTHER' && '$HOOK' pre-commit"
CWD="$OTHER"; bash_ "ls"; CWD=""
checkx "ターンの途中で cd した先のリポジトリも、そこでコマンドを実行した時点から対象になる" 1 sh -c "cd '$OTHER' && '$HOOK' pre-commit"
CWD="$OTHER"; bash_ "uv run pytest -q"; review reviewer; CWD=""
checkx "そのリポジトリを cwd にして検証・レビューすれば、コミットできる" 0 sh -c "cd '$OTHER' && '$HOOK' pre-commit"
BROKEN="$TMP/broken"; git init -q -b feat "$BROKEN"; CWD="$BROKEN"; turn; CWD=""; echo junk > "$BROKEN/.git/index"
checkx "判定できないとき（git が失敗する等）はコミットを止める" 1 sh -c "cd '$BROKEN' && '$HOOK' pre-commit"
fresh; ready h1; write README.md doc-first; $G add README.md; $G commit -q -m docs; $G add -A
checkx "ドキュメントを先にコミットして HEAD が動いても、コードの証拠は有効なまま" 0 precommit
fresh; mv "$REPO/src/lib.py" "$REPO/src/lib2.py"; write tests/test_app.py r; bash_ "uv run pytest -q"; review reviewer; $G add -A
checkx "ファイルを mv した変更も、証拠がそろっていればコミットできる（rename 検出でずれない）" 0 precommit
fresh; ready c7; $G add -A
checkx "証拠がそろっていれば、ステージしても指紋は変わらず成功する" 0 precommit
write src/app.py c8
checkx "検証後に作業ツリーを再編集しても、ステージ済みの（検証した）内容ならコミットできる" 0 precommit
$G add -A
checkx "再編集した内容をステージすれば失敗する" 1 precommit
fresh; write src/app.py c; write README.md doc; $G add README.md
checkx "未ステージのコード変更があっても、ドキュメントだけのコミットは通す" 0 precommit
fresh; ready c9; $G add src/app.py
checkx "レビューした内容の一部（コードだけ）をステージしたコミットはできない" 1 precommit
$G add tests/test_app.py
checkx "レビューした内容をすべてステージすれば通す" 0 precommit
fresh; printf '#!/bin/sh\necho hi\n' > "$REPO/tool"; $G add tool; rm "$REPO/tool"
checkx "ステージ後に作業ツリーから消しても、拡張子なしスクリプトはコードとして判定する" 1 precommit
fresh; write src/app.py c; write tests/test_app.py t; ln -s app.py "$REPO/src/alias.py"; ln -s src/app.py "$REPO/runme"; bash_ "pytest"; review reviewer; $G add -A
checkx "シンボリックリンクを含む変更も、証拠がそろっていればコミットできる" 0 precommit
fresh; $G config core.autocrlf true; printf 'a\r\nb\r\n' > "$REPO/src.py"; write tests/test_app.py t; bash_ "pytest"; review reviewer; $G add -A 2>/dev/null
checkx "改行変換（core.autocrlf）があっても指紋が一致する" 0 precommit
$G config --unset core.autocrlf
# テスト実行が作る生成物（.gitignore の無い Python リポジトリの __pycache__）。検証の時点で既にある
fresh; mkdir -p "$REPO/__pycache__" "$REPO/tests/__pycache__"; echo bin > "$REPO/__pycache__/test_app.cpython-311.pyc"; echo bin > "$REPO/tests/__pycache__/cache"; echo bin > "$REPO/test_old.pyo"
ready c10; $G add src/app.py tests/test_app.py
checkx "未追跡の __pycache__ / .pyc / .pyo があっても、レビューしたコードとテストをステージすればコミットできる" 0 precommit

# ---- git 本体から（共通 hooks 経由）: どんな呼び方でも git が必ず通す ----
fresh; write src/app.py g; $G add -A; before=$($G rev-list --count HEAD)
checkx "git commit は証拠なしで失敗する" 1 $GH commit -q -m x
checkx "sh -c / サブシェル / 環境変数の前置 経由でも同じ" 1 sh -c "cd '$REPO' && ( GIT_AUTHOR_DATE=2026-01-01T00:00:00 $GH commit -q -m x )"
expect "上の 2 件でコミットは作られていない" [ "$($G rev-list --count HEAD)" = "$before" ]
fresh; ready g2; $G add -A
checkx "証拠がそろえば git commit は成功する" 0 $GH commit -q -m "test+impl"
turn; write src/app.py g3; $G add -A
checkx "コミット後の新しいコード変更には、改めて証拠が要る" 1 $GH commit -q -m x
FAKE="$TMP/fakehome"; mkdir -p "$FAKE/.local/bin"; printf '#!/bin/sh\nexit 1\n' > "$FAKE/.local/bin/harness-hook"; chmod +x "$FAKE/.local/bin/harness-hook"
checkx "（前提）関門の実体が常に失敗する端末では、Claude からのコミットは止まる" 1 env HOME="$FAKE" $GH commit -q -m x
checkx "その端末でも、人の手動コミットでは関門の実体を起動しない（run-hook が CLAUDECODE を見る）" 0 env -u CLAUDECODE HOME="$FAKE" $GH commit -q -m human
WT="$TMP/wt"; $G worktree add -q -b feat/wt "$WT"; mkdir -p "$WT/src"; echo c > "$WT/src/w.py"; git -C "$WT" add -A
GW="git -C $WT -c user.name=t -c user.email=t@t -c core.hooksPath=$HOOKS"
checkx "セッションを開いたリポジトリから後で作った worktree でも、関門が効く" 1 $GW commit -q -m x
CWD="$WT"; turn; write_wt() { echo "$2" > "$WT/$1"; }; write_wt src/w.py c2; bash_ "uv run pytest -q"; review reviewer; CWD=""
git -C "$WT" add -A
checkx "worktree でも、証拠がそろえばコミットできる" 0 $GW commit -q -m "wt"
echo d > "$WT/README.md"; git -C "$WT" add README.md
mkdir -p "$REPO/.git/hooks"; printf '#!/bin/sh\nexit 1\n' > "$REPO/.git/hooks/pre-commit"; chmod +x "$REPO/.git/hooks/pre-commit"
checkx "worktree からでも、本体リポジトリの .git/hooks に委譲される" 1 $GW commit -q -m docs
rm "$REPO/.git/hooks/pre-commit"

# ---- リポジトリ自身の hook への委譲（run-hook）----
fresh; write README.md d1; $G add -A
HK="$REPO/.git/hooks"; mkdir -p "$HK"
printf '#!/bin/sh\nexit 1\n' > "$HK/pre-commit"; chmod +x "$HK/pre-commit"
checkx "リポジトリ自身の pre-commit が失敗すればコミットは失敗する" 1 $GH commit -q -m docs
printf '#!/bin/sh\ntouch "%s/ran-pre-commit"\n' "$TMP" > "$HK/pre-commit"
printf '#!/bin/sh\ncp "$1" "%s/commit-msg-arg"\n' "$TMP" > "$HK/commit-msg"; chmod +x "$HK/commit-msg"
checkx "委譲先が成功すればコミットは成功する" 0 $GH commit -q -m "docs message"
expect "リポジトリ自身の pre-commit が実行された" [ -e "$TMP/ran-pre-commit" ]
expect "commit-msg に引数（メッセージファイル）が渡る" grep -q "docs message" "$TMP/commit-msg-arg"
git init -q --bare "$TMP/remote.git"; $G remote add origin "$TMP/remote.git"
printf '#!/bin/sh\ncat > "%s/pre-push-stdin"\n' "$TMP" > "$HK/pre-push"; chmod +x "$HK/pre-push"
printf '#!/bin/sh\ncat > "%s/post-receive-stdin"\n' "$TMP" > "$TMP/remote.git/hooks/post-receive"; chmod +x "$TMP/remote.git/hooks/post-receive"
checkx "push が成功する" 0 $GH push -q origin feat/x
expect "pre-push に標準入力（push する ref）が渡る" grep -q refs/heads/feat/x "$TMP/pre-push-stdin"
expect "サーバー側の post-receive にも委譲される" grep -q refs/heads/feat/x "$TMP/post-receive-stdin"
rm -f "$HK/pre-commit" "$HK/commit-msg" "$HK/pre-push"
for h in pre-commit commit-msg prepare-commit-msg pre-push post-checkout post-merge pre-rebase pre-receive update post-receive post-update; do
  expect "hook 名 $h は run-hook へのリンク" [ "$(readlink "$HOOKS/$h")" = run-hook ]
done
expect "git init / clone で雑音を出さない" [ -z "$(git -c core.hooksPath="$HOOKS" clone -q "$REPO" "$TMP/clone" 2>&1; git -c core.hooksPath="$HOOKS" init -q "$TMP/newrepo" 2>&1)" ]
fresh; write src/app.py nogate; $G add -A
if env HOME="$TMP/nohome" $GH commit -q -m code > "$TMP/nohome.out" 2>&1; then ok "harness-hook が未インストールの端末では、コード変更のコミットも止めない"; else ng "未インストールの端末でコミットが止まった"; fi
expect "その場合は警告を出す" grep -q "関門を通さずに続行" "$TMP/nohome.out"

# ---- Bash の迂回防止（代表的な語を部分文字列で拒否。網羅はできない）----
for c in "git commit --no-verify -m x" "git commit --no-veri -m x" "git commit -n -m x" "git commit -anm x" \
  "git -c core.hooksPath=/dev/null commit -m x" "git -c core.hookspath=/dev/null commit -m x" "env -u CLAUDECODE git commit -m x" \
  "GIT_CONFIG_GLOBAL=/dev/null git commit -m x" "git commit-tree abc" "cp ~/.local/state/harness/repo/x/verified ~/.local/state/harness/repo/x/reviewed"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
for c in "git add -A && git commit -m x" "git log --oneline -n 5" "git status"; do
  checkd "通す: $c" allow "$(guardb "$c")"
done
expect "拒否の理由に、一致した語を含める" [ -n "$(guardb "git commit --no-verify" | grep -- "--no-v")" ]

# ---- 作業別ブランチの強制 ----
checkd "作業ブランチ上の編集は許可する" allow "$(guarde "$REPO/src/app.py")"
checkd "git リポジトリ外の編集は許可する" allow "$(guarde "$TMP/note.md")"
U="$TMP/unborn"; git init -q -b main "$U"
checkd "git init 直後（最初のコミット前）は main でも編集できる" allow "$(guarde "$U/app.py")"
CWD="$U"; turn; echo c > "$U/app.py"; bash_ "uv run pytest -q"; review reviewer; git -C "$U" add -A
checkx "最初のコミットは main に置ける（証拠がそろっていれば）" 0 sh -c "cd '$U' && '$HOOK' pre-commit"
check "最初のコミット前の main では、Stop も『ブランチを切れ』と差し戻さない" pass "$(stop)"
CWD=""
ln -s "$REPO/src/lib.py" "$TMP/outside-link.py"
fresh; $G switch -q main
checkd "main 上の編集は拒否する（まだ無いディレクトリへの新規ファイルでも）" deny "$(guarde "$REPO/src/new/app.py")"
checkd "リポジトリ外のシンボリックリンク経由でも、実体が main 上なら拒否する" deny "$(guarde "$TMP/outside-link.py")"
checkd "NotebookEdit（notebook_path）も同じく拒否する" deny "$(printf '{%s,"hook_event_name":"PreToolUse","tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s"}}' "$(common)" "$REPO/nb.ipynb" | "$HOOK" guard-branch)"
turn; ready m; $G add -A
checkx "main 上では証拠がそろっていても pre-commit は失敗する" 1 precommit
check "main 上の変更は Stop でも差し戻す" block "$(stop)"
$G reset -q --hard; $G clean -qfd; $G switch -q -c master
checkd "master 上の編集も拒否する" deny "$(guarde "$REPO/src/app.py")"
$G switch -q feat/x

# ---- 区切りでの remember（前回の tinymemory への session の保存から、コンテキストが溜まったら保存させる）----
# 使用量は transcript の最後の assistant の usage（input + cache_read + cache_creation）。ウィンドウは既定 100 万
TRANSCRIPT="$TMP/transcript.jsonl"; SID_MAIN=$SID; SID="memo-$$"
used() { printf '{"type":"assistant","isSidechain":false,"message":{"model":"m","usage":{"input_tokens":2,"cache_read_input_tokens":%s,"cache_creation_input_tokens":8,"output_tokens":99}}}\n' "$(($1 - 10))" >> "$TRANSCRIPT"; }
commit_doc() { write README.md "memo$($G rev-list --count HEAD)"; $G add README.md; $G commit -q -m memo; }   # $(…) の中からも呼ぶので、内容はコミット数で変える
milestone() { turn; used "$1"; commit_doc; stop; }   # このターンでコミットし、使用量が $1 のときの Stop
save_session() { bash_ 'tinymemory save --type session --title t <<E\nx\nE'; }
memo() { judge "$1" "$2" '/tinymemory:remember' remember pass "$3"; }
fresh
memo "区切り（コミット）でも、前回の保存から 30% 未満なら通す" pass "$(milestone 290000)"
r=$(milestone 310000)
memo "区切りで 30% 以上溜まっていれば remember させる" remember "$r"
memo "remember の理由に、M/L を締めるところなら /wrap-up を使うことが含まれる" remember "$(printf '%s' "$r" | grep /wrap-up)"
memo "remember の理由に、保存するのは session だけ（振り分けは /wrap-up）が含まれる" remember "$(printf '%s' "$r" | grep 'session だけを保存')"
memo "remember の理由に、前に保存した session を archive することが含まれる" remember "$(printf '%s' "$r" | grep 'tinymemory archive')"
memo "remember の理由に、起点の issue へ状態をコメントすることが含まれる（tinymemory は端末ごと）" remember "$(printf '%s' "$r" | grep 'issue' | grep '端末ごと')"
check "stop_hook_active なら二度目は通す" pass "$(stop done true)"
turn; used 320000; save_session
memo "tinymemory に session を保存したら、そこから数え直す" pass "$(milestone 600000)"   # 32 万 → 60 万 = 28%
turn; used 610000; bash_ 'tinymemory save --type fact --title t <<E\nx\nE'
memo "fact の保存は session の保存として数えない" remember "$(milestone 630000)"      # 32 万から 31%
turn; used 700000
memo "区切りでなければ 30% 以上でも通す" pass "$(stop)"
turn; used 930000
memo "区切りでなくても 60% 以上溜まっていれば remember させる" remember "$(stop)"
turn; used 940000
memo "60% の知らせは、同じ起点からは 1 回だけ" pass "$(stop)"
turn; used 100000; stop >/dev/null   # compact で縮んだ
memo "compact で縮んだら、縮んだ値から数え直す" remember "$(milestone 420000)"          # 10 万から 32%（32 万からなら 10%）
turn; used 450000; save_session; turn; used 500000; commit_doc
printf '%s\n' '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":990000}}}' >> "$TRANSCRIPT"
memo "サブエージェントの分は使用量に数えない" pass "$(stop)"                         # 数えると 45 万から 54%
turn; used 800000; commit_doc
printf '%s\n' '{"type":"assistant","isSidechain":false,"message":{"model":"<synthetic>","usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' >> "$TRANSCRIPT"
memo "最後が usage 0 の合成メッセージ（中断・API エラー）でも、その前の使用量で判定する" remember "$(stop)"   # 45 万から 35%
export HARNESS_CONTEXT_WINDOW=200000
memo "ウィンドウの大きさは HARNESS_CONTEXT_WINDOW で変えられる" remember "$(milestone 530000)"   # 45 万から 8 万 = 40%
unset HARNESS_CONTEXT_WINDOW
turn; write src/app.py memo; used 990000; r=$(stop)
check "証拠が足りない差し戻しがあれば、そちらを優先する" block "$r"
memo "（そのときは remember の指示を出さない）" pass "$r"
SID="memo-nogit-$$"; CWD="$TMP/nogit"; mkdir -p "$CWD"; turn; used 700000
memo "git リポジトリの外でも 60% の知らせは出る" remember "$(stop)"
CWD=""; TRANSCRIPT=""; SID=$SID_MAIN; $G reset -q --hard; $G clean -qfd

# ---- その他 ----
S="$XDG_STATE_HOME/harness/session"; mkdir -p "$S/old" "$S/old-nostart"; touch -t 202001010000 "$S/old/start" "$S/old-nostart"
touch -t 202001010000 "$S/$SID"   # 今のセッションのディレクトリ自体は古くても、start が新しければ消さない
turn
expect "7 日より古いセッションの状態は消える" [ ! -e "$S/old" ]
expect "start が無い古いセッションも消える" [ ! -e "$S/old-nostart" ]
expect "今のセッションの状態は消えない" [ -e "$S/$SID/start" ]
expect "呼び出しログが残る" grep -q "stop .*missing=" "$XDG_STATE_HOME/harness/log"
bash_ 'true\nuv run pytest'
expect "ログは 1 呼び出し 1 行（コマンド中の改行を含めない）" [ "$(grep -c '^uv run pytest' "$XDG_STATE_HOME/harness/log")" = 0 ]
expect "（前提）そのコマンドはログに残っている" grep -q "true uv run pytest" "$XDG_STATE_HOME/harness/log"
printf 'not json' | "$HOOK" stop >/dev/null 2>&1; r=$?
expect "壊れた入力でも exit 0" [ "$r" = 0 ]
errors=$(log_count " error=")
printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":"想定外の形"}' "$(common)" | "$HOOK" bash >/dev/null 2>&1; r=$?
expect "hook が例外で終わっても exit 0" [ "$r" = 0 ]
expect "そのとき原因をセッション付きでログに 1 行残す" [ "$(log_count "$(printf %.8s "$SID") bash .* error=AttributeError")" = 1 ]
[ "$errors" = "$EXPECTED_ERRORS" ] || grep " error=" "$XDG_STATE_HOME/harness/log" || true
expect "ここまでのテストで、意図せず例外で終わった hook は無い（あると pass / allow 側に見えてしまう）" [ "$errors" = "$EXPECTED_ERRORS" ]

echo "harness-hook: ok $passed, FAIL $fail"
[ "$fail" = 0 ]
