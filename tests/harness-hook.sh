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
echo 'uv run pytest -q' > "$REPO/.harness-verify"   # 検証コマンドの宣言（関門は、宣言したコマンドの成功だけを検証の証拠にする）
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
OKA='## 条件ごとの結果\n- [AC1] 合格 — 確かめ方 → 観測値\n- [AC2] 合格 — 確かめ方 → 観測値\n## 判定\n受け入れ: 合格'   # acceptor の出力（条件と判定がすべて合格）
SNAP="$DOTFILES/config/claude/skills/review/snapshot.sh"
ver() { (cd "${CWD:-$REPO}" && sh "$SNAP" 2>/dev/null) || true; }   # 今の作業ツリー全体の版（reviewer・acceptor が報告の先頭に書くもの）
versioned() { # versioned <agent_type> <報告>: 報告に版の行が無ければ今の版の行を先頭に足す（@VER@ は今の版に置き換える）
  case "$2" in
    *した版:*) printf '%s' "$2" | sed "s/@VER@/$(ver)/g" ;;
    *) if [ "$1" = acceptor ]; then label=受け入れ検証した版; else label=レビューした版; fi; printf '%s: %s\\n%s' "$label" "$(ver)" "$2" ;;
  esac; }
raw_review() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s","last_assistant_message":"%s"}' "$(common)" "$1" "$2" | "$HOOK" review-done; }
review() { raw_review "$1" "$(versioned "$1" "${2-$OK3}")"; }
accept() { review acceptor "${1-$OKA}"; }
review_handback() { # review_handback <報告> [agent_type（既定 reviewer）]。報告をツール呼び出し（SubagentHandback）で返す環境: 最後のテキストに判定文は無く、サブエージェントの記録にある
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SubagentHandback","input":{"message":"%s"}}]}}\n{"message":{"role":"assistant","content":[{"type":"text","text":"報告を返しました"}]}}\n' "$(versioned "${2:-reviewer}" "$1")" > "$TMP/agent.jsonl"
  printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s","last_assistant_message":"報告を返しました","agent_transcript_path":"%s"}' "$(common)" "${2:-reviewer}" "$TMP/agent.jsonl" | "$HOOK" review-done; }
review_from() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"reviewer","last_assistant_message":"","agent_transcript_path":"%s"}' "$(common)" "$1" | "$HOOK" review-done; }  # 判定は記録からだけ読める
log_count() { grep -c "$1" "$XDG_STATE_HOME/harness/log" || true; }
stop() { printf '{%s,"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"%s"}' "$(common)" "${2:-false}" "${1:-done}" | "$HOOK" stop; }
guardb() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(common)" "$1" | "$HOOK" guard-bash; }
guarde() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(common)" "$1" | "$HOOK" guard-branch; }
precommit() { (cd "$REPO" && "$HOOK" pre-commit); }
write() { mkdir -p "$(dirname "$REPO/$1")"; echo "$2" > "$REPO/$1"; }
fresh() { $G reset -q --hard; $G clean -qfd; reqs; turn; }           # きれいな作業ツリーで、要件の写しを保存して新しいターンを始める
reqs() { printf '%b\n' "${1:-AC1: 要件と受け入れ条件}" | (cd "${CWD:-$REPO}" && "$HOOK" requirements-save) >/dev/null; }  # 承認済みの要件の写しを保存する（今のブランチ。\n は改行）
has() { printf '%s' "$1" | grep -qF -- "$2"; }   # has <文字列> <部分文字列>
ready() { reqs; write src/app.py "$1"; write tests/test_app.py "$1"; bash_ "uv run pytest -q"; accept; review reviewer; }  # 証拠がそろった状態
reqs   # feat/x の要件の写し（関門は、コードを変えたら承認済みの要件の写しを求める）

# ---- Stop（完了の差し戻し）----
fresh
check "変更なしなら通す" pass "$(stop)"
fresh; write README.md doc
check "ドキュメントだけの変更は通す" pass "$(stop)"
fresh; write notes doc
check "拡張子の無いファイルは、文書の名前でなければコード変更として扱う" block "$(stop)"
fresh; write LICENSE doc
check "拡張子の無い文書の名前（LICENSE など）は通す" pass "$(stop)"
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
check "バックグラウンドのサブエージェントの完了を待つときも、その旨を書いて終えてよいことが含まれる" block "$(stop | grep 'バックグラウンドのサブエージェントの完了を待つ')"
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
  fresh; write src/app.py c; write tests/test_app.py t; write src/locked.py x; chmod 000 "$REPO/src/locked.py"; bash_ "uv run pytest -q"; accept; review reviewer
  check "読めないファイルがあって指紋を作れないときは、証拠を記録せず差し戻す" block "$(stop)"
  EXPECTED_ERRORS=$((EXPECTED_ERRORS + 1))   # 上の bash は指紋を作れず例外で終わる（2 つの review-done は版を求められないので、例外の前に記録しないで終わる）
  chmod 644 "$REPO/src/locked.py"
fi

fresh; write src/app.py code; write tests/test_app.py t; bash_ "uv run pytest -q"; accept
check "テスト・検証・受け入れありでもレビュー未実施 → 差し戻す" block "$(stop)"
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
write src/app.py code1n; bash_ "uv run pytest -q"; accept
review reviewer 'レビューした版: @VER@\n\n## 指摘ごとの判定\n- [R1-2] 直った — 根拠 src/app.py:3\n- テスト: sh tests/x.sh 成功\n\n## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
check "根拠の行を軸名で始めると判定と読まれ、承認にならない" block "$(stop)"
review reviewer 'レビューした版: @VER@\n\n## 指摘ごとの判定\n- [R1-2] 直った — 根拠 src/app.py:3\n- [R1-3] 直っていない — のちに修正が必要 src/app.py:9\n\n## 修正による新しい問題\n- [R2-1] [軽] [テスト] tests/test_app.py:12 — 名前が曖昧\n\n## ユーザー判断で見送り\n- [R1-3] 裁定: 対象外の環境なので見送り\n\n## 範囲外\n- src/other.py:5 — 修正が必要になりそうな箇所\n\n未解決: なし\n\n## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
check "範囲限定の再レビューの出力形式（見送り・範囲外の節つき）は、3 軸とも承認なら承認として読む" pass "$(stop)"
write src/app.py code1b; bash_ "uv run pytest -q"; accept
check "（再編集後）レビューが無効になっている" block "$(stop)"
review_handback '## 判定\n仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
check "報告がハンドバック経由で『修正が必要』ならレビュー済みにしない" block "$(stop)"
review_handback '## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
check "報告がハンドバック経由（最後のテキストに判定文が無い）でも、記録から判定を読んでレビュー済みにする" pass "$(stop)"
write src/app.py code1c; bash_ "uv run pytest -q"; accept
# 再開された reviewer: 前回は承認、今回の依頼の後は判定を出さずに終わった（想定外の形の行も混ぜる）
resumed() { # resumed <新しい依頼の行（空なら入れない）>
  { printf '{"message":{"role":"assistant","content":[{"type":"text","text":"レビューした版: %s\\n仕様適合: 承認\\nテスト: 承認\\n品質・保守性: 承認"}]}}\n' "$(ver)"
    [ -z "$1" ] || printf '%s\n' "$1"
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"x"}}]}}' \
      '{"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}' \
      '[1,2]' '{"message":{"role":"assistant","content":["中断"]}}' \
      '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SubagentHandback","input":"壊れた入力"}]}}'
  } > "$TMP/resumed.jsonl"; review_from "$TMP/resumed.jsonl"; }
before=$(log_count "review-done .*reviewed=False")
resumed '{"message":{"role":"user","content":"もう一度レビューして"}}'
check "記録に以前の承認があっても、今回の依頼の後に判定が無ければレビュー済みにしない" block "$(stop)"
expect "そのときも review-done のログが 1 行残る（記録に想定外の行があっても落ちない）" [ "$(log_count "review-done .*reviewed=False")" = "$((before + 1))" ]
resumed '{"message":{"role":"user","content":[{"type":"text","text":"もう一度レビューして"}]}}'
check "新しい依頼がブロック形式（content がリスト）でも同じ" block "$(stop)"
resumed ''
check "（前提）同じ記録でも、新しい依頼の行が無ければ承認として読める" pass "$(stop)"
write src/app.py code1d; bash_ "uv run pytest -q"; accept
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"cat <<E\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認\nE"}}]}}' > "$TMP/quoted.jsonl"; review_from "$TMP/quoted.jsonl"
check "reviewer が途中で実行したコマンドの中の判定行は、報告として読まない" block "$(stop)"
review reviewer
check "テスト・検証・受け入れ・レビュー承認がそろえば通す" pass "$(stop)"
expect "review-done は承認の可否を 1 行でログに残す" grep -q "review-done .*reviewed=True" "$XDG_STATE_HOME/harness/log"
write src/app.py code2
check "その後に再編集すれば検証・受け入れ・レビューは無効になり差し戻す" block "$(stop)"
bash_ "uv run pytest -q"; accept; review reviewer
check "再検証・再受け入れ・再レビューすれば通す" pass "$(stop)"
# reviewer の報告は承認・不承認に関わらず <git-dir>/harness-last-review に保存する（次の /review fix で前回の報告として読む）
review reviewer '仕様適合: 修正が必要\nテスト: 承認\n品質・保守性: 承認'
expect "review-done は reviewer の報告を .git/harness-last-review に保存する（不承認でも）" grep -q "仕様適合: 修正が必要" "$REPO/.git/harness-last-review"
review reviewer
expect "次の review-done で上書きされる" [ "$(cat "$REPO/.git/harness-last-review")" = "$(printf "$(versioned reviewer "$OK3")")" ]
# 証拠は、報告の版（レビューした版・受け入れ検証した版）が SubagentStop の時点の作業ツリー全体の版と一致するときだけ記録する
# （レビュー・受け入れ検証の後に編集した内容には付かない）
fresh; write src/app.py vm1; bash_ "uv run pytest -q"; accept; old=$(ver); write src/app.py vm2; bash_ "uv run pytest -q"; accept
review reviewer "レビューした版: $old\n$OK3"
check "レビューの後に編集した内容には、承認を記録しない（報告の版が今の版と違う）" block "$(stop)"
expect "そのとき review-done のログに版の食い違いが残る" grep -q "review-done .*version-mismatch" "$XDG_STATE_HOME/harness/log"
raw_review reviewer "$OK3"
check "報告に版の行が無ければ、承認を記録しない" block "$(stop)"
review reviewer
check "（前提）今の版の報告なら記録する" pass "$(stop)"
# 報告の版と今の版の差が、証拠に関わらないファイル（テスト実行の生成物・文書）だけなら同じとみなす
old=$(ver); write src/app.py vm4; bash_ "uv run pytest -q"; accept; old=$(ver)
mkdir -p "$REPO/src/__pycache__"; echo bin > "$REPO/src/__pycache__/app.cpython-311.pyc"; write README.md "notes after review"
review reviewer "レビューした版: $old\n$OK3"
check "報告の後に生成物と文書だけが増えても、承認を記録する" pass "$(stop)"
old=$(ver); write src/app.py vm3; bash_ "uv run pytest -q"; review reviewer; accept "受け入れ検証した版: $old\n$OKA"
check "受け入れ検証の後に編集した内容にも、合格を記録しない" block "$(stop | grep /accept)"

# 受け入れ（acceptor の報告）: 条件の行「[AC<n>] <状態>」と判定行「受け入れ: <値>」がそれぞれ 1 行以上あり、すべて「合格」のときだけ受け入れ済み
fresh; write src/app.py ac1; write tests/test_app.py ac1; bash_ "uv run pytest -q"; review reviewer
check "検証とレビューがあっても、受け入れが無ければ差し戻す" block "$(stop)"
check "差し戻しの理由に、足りない証拠（/accept）が含まれる" block "$(stop | grep /accept)"
$G add -A
expect "同じ内容をステージすると、pre-commit も /accept を理由に拒否する" [ -n "$(precommit 2>&1 | grep /accept || true)" ]
review acceptor
check "reviewer の報告の形で acceptor が終わっても受け入れ済みにしない" block "$(stop)"
C='## 条件ごとの結果\n'   # 条件の行は、この節の中だけを読む
accept "受け入れ検証した版: @VER@\n$C- [AC1] 合格 — x → y\n## 判定\n受け入れ: 不合格"
check "判定行が『不合格』なら受け入れ済みにしない" block "$(stop)"
accept "$C- [AC1] 合格 — x → y\n- [AC2] 不合格 — 期待 / 実際\n受け入れ: 合格"
check "判定行が合格でも、条件の行に『不合格』があれば受け入れ済みにしない" block "$(stop)"
accept "$C- [AC1] 合格 — x → y\n- [AC2] 未確認 — 理由\n受け入れ: 合格"
check "判定行が合格でも、条件の行に『未確認』があれば受け入れ済みにしない" block "$(stop)"
accept "受け入れ検証した版: @VER@\n$C- [AC1] 合格 — x → y"
check "判定行が無ければ受け入れ済みにしない（『受け入れ検証した版:』は判定行ではない）" block "$(stop)"
accept "$C## 判定\n受け入れ: 合格"
check "条件の行が無ければ受け入れ済みにしない" block "$(stop)"
accept '- [AC1] 合格 — x → y\n## 判定\n受け入れ: 合格'
check "条件の行が『条件ごとの結果』の節の外にしか無ければ受け入れ済みにしない" block "$(stop)"
accept "$C- [AC1] 合格 — x\n### 補足\n- [AC2] 不合格 — a\n## 判定\n受け入れ: 合格"
check "節の中の小見出しの下にある『不合格』も数える（小見出しで節を終えない）" block "$(stop)"
accept "$C- [AC1] 合格 — x\n## 検査スクリプト\n- s\n$C- [AC2] 不合格 — a\n## 判定\n受け入れ: 合格"
check "『条件ごとの結果』の節が 2 つあれば、2 つ目の『不合格』も数える" block "$(stop)"
accept "$C- [AC1] 合格 — x → y\n受け入れ: 合格\n受け入れ: 不合格"
check "判定行が複数あり、1 つでも『不合格』なら受け入れ済みにしない" block "$(stop)"
expect "review-done は acceptor の報告を .git/harness-last-accept に保存する（不合格でも）" grep -q "受け入れ: 不合格" "$REPO/.git/harness-last-accept"
review_handback "$OKA" acceptor
check "報告がハンドバック経由でも、記録から判定を読んで受け入れ済みにする" pass "$(stop)"
expect "review-done は受け入れの可否を 1 行でログに残す" grep -q "review-done .*accepted=True" "$XDG_STATE_HOME/harness/log"
expect "harness-last-accept は次の報告で上書きされる" [ "$(cat "$REPO/.git/harness-last-accept")" = "$(printf "$(versioned acceptor "$OKA")")" ]
$G add -A
checkx "検証・受け入れ・レビューがそろった内容をステージすればコミットできる" 0 precommit
write src/app.py ac2; bash_ "uv run pytest -q"; review reviewer
check "受け入れの後に内容を変えると、受け入れは無効になり差し戻す" block "$(stop)"
accept "$C- **[AC1]** **合格** — x → y\n- [AC2] 合格\n- **受け入れ**: **合格**"
check "条件と判定がすべて合格なら受け入れ済みにする（箇条書き・強調も可）" pass "$(stop)"
write src/app.py ac2b; bash_ "uv run pytest -q"; review reviewer
accept "$C- [AC1] 合格 - 半角のハイフン\n- [AC2] 合格 – 別のダッシュ\n- [AC3] 合格—空白なし\n- [AC4] 合格―水平線\n- [AC5] 合格−マイナス\n- [AC6] 合格‐ハイフン\n## 検査スクリプト\n- [AC2] の検査は tests/acceptance/x.sh\n## 判定\n受け入れ: 合格"
check "条件の状態はダッシュの種類に依らず読み、節の外の [AC で始まる行は条件として数えない" pass "$(stop)"
write src/app.py ac3; bash_ "uv run pytest -q"; accept; review reviewer "$OKA"
check "acceptor の報告の形で reviewer が終わってもレビュー済みにしない" block "$(stop)"
review reviewer
check "（前提）reviewer の報告なら通す" pass "$(stop)"
# 受け入れは要件の写しの受け入れ条件の番号（行頭か箇条書きの後の「AC<n>:」）と突き合わせる: 写しの番号がすべて、節の中に「合格」で出ていること
reqs '要件\nAC1: 振る舞い\n- AC2: 境界\n- **AC3**: 出力'; write src/app.py ac4; bash_ "uv run pytest -q"; review reviewer
accept "$C- [AC1] 合格 — x\n- [AC2] 合格 — y\n## 判定\n受け入れ: 合格"
check "写しの受け入れ条件（AC3）が報告に無ければ受け入れ済みにしない" block "$(stop)"
expect "review-done は、報告に合格で出ていない写しの番号をログに残す" grep -q "review-done .*accepted=False.*AC3" "$XDG_STATE_HOME/harness/log"
accept "$C- [AC1] 合格 — x\n- [AC2] 合格 — y\n## 検査スクリプト\n- [AC3] 合格 — z\n## 判定\n受け入れ: 合格"
check "写しの番号が節の外にしか無ければ受け入れ済みにしない" block "$(stop)"
accept "$C- [AC1] 合格 — x\n- [AC2] 合格 — y\n- [AC3] 合格 — z\n- [AC4] 合格 — 写しに無い番号\n## 判定\n受け入れ: 合格"
check "写しの番号（行頭・箇条書き・強調の AC<n>:）がすべて合格なら受け入れ済みにする（写しに無い番号が報告にあるのは構わない）" pass "$(stop)"
reqs '要件と受け入れ条件\n- 番号の無い条件（AC1 の形でない）'; write src/app.py ac5; bash_ "uv run pytest -q"; review reviewer; accept; r=$(stop)
check "写しに AC 番号が 1 つも無ければ受け入れ済みにしない" block "$r"
expect "理由に、受け入れ条件に番号を付けることが含まれる" [ -n "$(printf '%s' "$r" | grep -F '受け入れ条件に AC1, AC2 … の番号を付ける')" ]
$G add -A
expect "同じく、pre-commit の理由にも含まれる" [ -n "$(precommit 2>&1 | grep -F '受け入れ条件に AC1, AC2 … の番号を付ける' || true)" ]
reqs

# 検証として認める／認めないコマンドの形: 証拠になるのは、宣言したコマンド（ここでは .harness-verify の uv run pytest -q）の成功だけ
# 証拠は内容の指紋で持つので、ケースごとに内容を変える（同じ内容だと前のケースの「検証済み」が一致してしまう）
n=0
unverified() { n=$((n + 1)); fresh; write src/app.py "v$n"; write tests/test_app.py "v$n"; accept; review reviewer; }  # 検証だけが足りない状態
for c in "uv run pytest -q" "cd $REPO && uv run pytest -q" "cd $REPO/ && uv run pytest -q"; do
  unverified; bash_ "$c"
  check "検証として認める（宣言したコマンドを、リポジトリのトップで。先頭の cd <トップ> && は除いて比べる）: $c" pass "$(stop)"
done
# 宣言した検証を並列に実行しても（hook が同時に動いても）、すべての成功が記録される（記録の読み書きが競合しない）
for round in 1 2 3; do
  fresh; printf 'sh tests/p1.sh\nsh tests/p2.sh\nsh tests/p3.sh\nsh tests/p4.sh\nsh tests/p5.sh\n' > "$REPO/.harness-verify"
  write src/app.py "par$round"; accept; review reviewer
  for i in 1 2 3 4 5; do bash_ "sh tests/p$i.sh" & done; wait
  check "並列に実行した宣言の検証 5 本がすべて記録される（$round 回目）" pass "$(stop)"
done
# 下位のディレクトリで実行した検証は、全体の検証ではない（pytest・go test などは下位しか走らない）
unverified; bash_ "cd src && uv run pytest -q"
check "検証として認めない（cd で下位に移って実行した）" block "$(stop)"
unverified; mkdir -p "$REPO/src"; CWD="$REPO/src"; bash_ "uv run pytest -q"; CWD=""
check "検証として認めない（cwd が下位のまま実行した）" block "$(stop)"
for c in "pytest -q" "uv run pytest -q tests/test_app.py" "cargo test" "sh tests/run.sh" "uv run ruff check ." "npm run lint" "uvx ruff check ." \
  "uv run pytest -q 2>&1" "uv run pytest -q 2>&1 | tail -3" "uv run pytest -q || echo done" "uv run pytest -q; echo done" "uv run pytest -q &" \
  "uv run pytest -q >/dev/null" "time uv run pytest -q" "cd $REPO\\nuv run pytest -q" "echo uv run pytest -q"; do
  unverified; bash_ "$c"
  check "検証として認めない（宣言に無い・絞った・lint だけ・宣言にパイプ等を足した形）: $(printf '%s' "$c" | tr '\\' ' ')" block "$(stop)"
done
unverified; bash_ "uv run pytest -q" ',"run_in_background":true'
check "バックグラウンド実行は検証として認めない" block "$(stop)"
unverified; printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"uv run pytest -q"},"tool_response":{"stdout":"","stderr":"","interrupted":false,"backgroundTaskId":"b1"}}' "$(common)" | "$HOOK" bash
check "実行中にバックグラウンドへ回された（終了前の）実行も検証として認めない" block "$(stop)"
unverified; bash_ "uv run pytest -q" "" true
check "中断された実行は検証として認めない" block "$(stop)"
unverified; printf '{%s,"agent_id":"a1","agent_type":"implementer","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"uv run pytest -q"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}' "$(common)" | "$HOOK" bash
check "サブエージェント内（agent_id あり）の検証の成功は記録しない" block "$(stop)"
unverified; bash_ "uv run pytest -q"; n_same=$n; fresh; write src/app.py "v$n_same"; write tests/test_app.py "v$n_same"
check "同じ内容に戻せば、以前の検証・レビューがそのまま有効（指紋は内容で決まる）" pass "$(stop)"

# 検証コマンドの失敗（PostToolUseFailure）は、その作業ツリーの「検証済み」を消す
bash_fail() { # bash_fail <command> [error（既定 Exit code 1）] [入力への追加 JSON]
  printf '{%s%s,"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"%s"},"error":"%s","is_interrupt":false}' "$(common)" "${3:-}" "$1" "${2:-Exit code 1}" | "$HOOK" bash-failed; }
fresh; ready vf1; bash_fail "ls nothing"
check "検証コマンドでないコマンドの失敗では、検証済みは消えない" pass "$(stop)"
bash_fail "uv run pytest -q 2>&1 | tail -3"
check "同じ内容で検証コマンドが失敗すれば（パイプ付きの形でも）、検証済みが消えて差し戻す" block "$(stop)"
$G add -A
checkx "同じく、pre-commit も失敗する" 1 precommit

# 検証コマンドの失敗は、出力の先頭 15 行を <git-dir>/harness-red-log に残す（RED を観測できるように。サブエージェント内も）
RED="$REPO/.git/harness-red-log"
fresh; rm -f "$RED"; write src/app.py red1; bash_fail "ls nothing" "ls-output"
expect "検証コマンドでないコマンドの失敗は記録しない" [ ! -e "$RED" ]
bash_fail "uv run pytest -q" 'Exit code 1\nE   assert 1 == 2'
expect "検証コマンドの失敗は、コマンドと出力を記録する" grep -qx '  E   assert 1 == 2' "$RED"
fp=$(sed -n 's/.* tree=\([0-9a-f]*\).*/\1/p' "$RED" | tail -1); bash_ "uv run pytest -q"
expect "記録の指紋は、その時点の内容の指紋（同じ内容で検証が成功したときと同じ）" grep -rqx "${fp:-none}" "$XDG_STATE_HOME/harness/repo"
bash_fail "uv run pytest -q" 'E   sub failure' ',"agent_id":"a1","agent_type":"implementer"'
expect "サブエージェント内の失敗も、agent_type とともに記録する" sh -c "tail -3 '$RED' | grep 'agent=implementer' >/dev/null && tail -1 '$RED' | grep -qx '  E   sub failure'"
bash_fail "uv run pytest -q" "$(i=1; while [ $i -le 20 ]; do printf 'L%s\\n' $i; i=$((i + 1)); done)"
expect "出力は先頭 15 行まで" sh -c "grep -qx '  L15' '$RED' && ! grep -qx '  L16' '$RED'"
printf '{%s,"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"uv run pytest -q"},"tool_response":{"stdout":"resp-out","stderr":"resp-err"}}' "$(common)" | "$HOOK" bash-failed
expect "error が無ければ tool_response の中身を記録する" sh -c "grep -qx '  resp-out' '$RED' && grep -qx '  resp-err' '$RED'"
i=0; while [ $i -lt 60 ]; do printf '2026-01-01 00:00:00 tree=old\n  $ old %s\n' $i; i=$((i + 1)); done > "$RED"
bash_fail "uv run pytest -q" "new-entry"
expect "記録は直近 50 件に切り詰める" [ "$(grep -c '^[^ ]' "$RED")" = 50 ]
expect "（切り詰めるのは古い側）" sh -c "grep -qx '  new-entry' '$RED' && grep -qx '  \$ old 11' '$RED' && ! grep -qx '  \$ old 10' '$RED'"
{ printf '2026-01-01 00:00:00 tree=old\n  '; head -c 200000 /dev/zero | tr '\0' x; echo; } > "$RED"
bash_fail "uv run pytest -q" "new-entry"
expect "100KB を超える分も古い側から切り詰める" sh -c "[ \$(wc -c < '$RED') -le 100000 ] && grep -qx '  new-entry' '$RED'"
for c in "deno test" "mocha" "npx mocha" "playwright test" "npx playwright test" "rake test" "rake spec" "bundle exec rake" "bats tests" "ctest"; do
  bash_fail "$c 2>&1 | tail -3" "red: $c"
  expect "テストランナーの失敗も RED として記録する: $c" grep -qx "  red: $c" "$RED"
done
# テストを走らせるコマンド（test・tests/・spec を含む）の失敗も記録する。ただし「検証済み」は消さない。読むだけのコマンドの失敗は記録しない
for c in "python manage.py test" "bin/rails test" "xcodebuild test -scheme App" "bazel test //..." "node tests/x.test.js" \
  "uv run python tests/x.py" "stack test"; do
  bash_fail "$c" "red: $c"
  expect "テストを走らせるコマンドの失敗も RED として記録する: $c" grep -qx "  red: $c" "$RED"
done
for c in "grep -rn test src" "find tests -name x" "git log -- tests"; do
  bash_fail "$c" "noise: $c"
  expect "読むだけのコマンドの失敗は記録しない: $c" sh -c "! grep -qx '  noise: $c' '$RED'"
done
fresh; write src/app.py red2; bash_ "uv run pytest -q"; accept; review reviewer; bash_fail "python manage.py test" "x"
check "宣言に無いテストのコマンドの失敗では、検証済みは消えない" pass "$(stop)"

# 宣言した検証コマンド（リポジトリのトップの .harness-verify）: 書かれたコマンドがすべて同じ内容で成功したときだけ検証済み
fresh; printf '# 宣言した検証コマンド\nsh tests/run.sh\n\n./ci.sh\n' > "$REPO/.harness-verify"; write src/app.py hv1; accept; review reviewer
bash_ "uv run pytest -q"
check "宣言があれば、宣言に無い検証コマンドの成功は証拠にならない" block "$(stop)"
bash_ "sh tests/run.sh"
check "宣言した 2 つのうち 1 つだけの成功では差し戻す" block "$(stop)"
bash_ "cd $REPO && ./ci.sh"
check "もう 1 つも成功すれば通す（先頭の cd … && を除いて比べる。検証コマンドの形でなくてよい）" pass "$(stop)"
write src/app.py hv2; accept; review reviewer; bash_ "./ci.sh"
check "その後に内容を変えると、両方やり直しになる" block "$(stop)"
bash_ "sh tests/run.sh"
check "（前提）両方をやり直せば通す" pass "$(stop)"
$G add -A
checkx "同じく、宣言したコマンドがすべて成功した内容をステージすればコミットできる" 0 precommit
bash_fail "./ci.sh"
check "宣言したコマンドの失敗でも、検証済みは消える" block "$(stop)"
expect "宣言したコマンド（検証コマンドの形でなくても）の失敗も RED として記録する" grep -qx '  $ ./ci.sh' "$RED"
# 自分だけの宣言（<git-common-dir>/harness-verify）もあれば、共有の宣言と合わせた行がすべて要る
fresh; echo 'sh tests/run.sh' > "$REPO/.git/harness-verify"; write src/app.py hv3; accept; review reviewer
bash_ "uv run pytest -q"
check "共有と自分だけの宣言が両方あれば、共有の行だけの成功では差し戻す" block "$(stop)"
bash_ "sh tests/run.sh"
check "（前提）両方の行が成功すれば通す" pass "$(stop)"
# 自分だけの宣言も、要件の写しと同じく指紋に入る（リポジトリの外なので、作業ツリーとインデックスで同じ値）
printf '# 書き換えた\nsh tests/run.sh\n' > "$REPO/.git/harness-verify"
check "自分だけの宣言を書き換えると（宣言した行が同じでも）、検証・受け入れ・レビューの証拠はすべて無効になる" block "$(stop | grep /verify | grep /accept | grep /review)"
$G add -A
checkx "同じく、ステージ済みの内容でも pre-commit は拒否する" 1 precommit
echo 'sh tests/run.sh' > "$REPO/.git/harness-verify"
checkx "宣言を元に戻せば、以前の証拠が有効（作業ツリーとインデックスで同じ指紋）" 0 precommit
rm "$REPO/.git/harness-verify"

# 承認済みの要件の写し（<git-dir>/harness-requirements/<ブランチ名>.md）の置き場所
REQ="$(cd "$REPO/src" && "$HOOK" requirements-path)"
expect "requirements-path は、cwd のリポジトリの要件の写しの置き場所を出す（ブランチ名の / は _）" [ "$REQ" = "$(cd "$REPO" && pwd -P)/.git/harness-requirements/feat_x.md" ]
expect "置き場所のディレクトリは作る" [ -d "$(cd "$REPO" && pwd -P)/.git/harness-requirements" ]
$G switch -q --detach; P="$(cd "$REPO" && "$HOOK" requirements-path)"; $G switch -q feat/x
expect "detached HEAD では HEAD.md" [ "$P" = "$(cd "$REPO" && pwd -P)/.git/harness-requirements/HEAD.md" ]
expect "ファイルは作らない" [ ! -e "$P" ]
# .git の下は Claude Code の Write ツールでは書けない（保護される）ので、標準入力から保存する口を持つ
printf '承認済みの要件\n- AC1 x\n' | (cd "$REPO/src" && "$HOOK" requirements-save) > "$TMP/saved-path"
expect "requirements-save は、標準入力を要件の写しとして保存し、そのパスを出す" [ "$(cat "$TMP/saved-path")" = "$REQ" ]
expect "（同じく）内容がそのまま書かれる" [ "$(cat "$REQ")" = "$(printf '承認済みの要件\n- AC1 x')" ]
checkx "空の入力では保存せず失敗する（写しを空で上書きしない）" 1 sh -c "printf '' | (cd '$REPO' && '$HOOK' requirements-save)"
expect "（同じく）前の内容が残る" [ "$(cat "$REQ")" = "$(printf '承認済みの要件\n- AC1 x')" ]
# 写しはブランチごとなので、ブランチを切った後に保存する（main・master の上では保存しない）
$G switch -q main
if out=$(printf 'AC1: x\n' | (cd "$REPO" && "$HOOK" requirements-save) 2>&1); then code=0; else code=1; fi
expect "main の上では requirements-save は保存せず失敗する" [ "$code" != 0 ]
expect "理由に、先に作業ブランチを切ることが出る" has "$out" "作業ブランチを切ってから"
expect "main の写しは作られない" [ ! -e "$(cd "$REPO" && pwd -P)/.git/harness-requirements/main.md" ]
$G switch -q feat/x
# 承認済みの要件の写しが無い・空なら差し戻す。書き換えれば、検証・受け入れ・レビューの証拠はすべて無効になる
fresh; rm "$REQ"; write src/app.py rq1; bash_ "uv run pytest -q"; accept; review reviewer; r=$(stop)
check "要件の写しが無ければ、ほかの証拠がそろっていても差し戻す" block "$r"
expect "理由に、要件の写しの保存のしかた・場所と /issue が含まれる" [ -n "$(printf '%s' "$r" | grep -F "承認済みの要件と受け入れ条件の写しを \`harness-hook requirements-save\` に標準入力で渡して保存する（場所: $REQ。S は依頼の原文と受け入れ条件 1 行）→ /issue")" ]
expect "（前提）足りないのは要件と、その受け入れ条件の番号だけ（/verify・/review は理由に無い。受け入れは写しの番号と突き合わせる）" [ -z "$(printf '%s' "$r" | grep -e /verify -e /review)" ]
$G add -A
checkx "同じく、pre-commit も拒否する" 1 precommit
: > "$REQ"; bash_ "uv run pytest -q"; accept; review reviewer
check "要件の写しが空でも差し戻す" block "$(stop | grep -F "場所: $REQ")"
reqs; bash_ "uv run pytest -q"; accept; review reviewer
check "（前提）要件の写しを書いて証拠をそろえれば通す" pass "$(stop)"
reqs "AC1: 書き換えた要件"
check "要件の写しを書き換えると、検証・受け入れ・レビューの証拠はすべて無効になる" block "$(stop | grep /verify | grep /accept | grep /review)"
checkx "同じく、ステージ済みの内容でも pre-commit は拒否する" 1 precommit
reqs
check "要件を元に戻せば、以前の証拠が有効（指紋は内容で決まる）" pass "$(stop)"
checkx "同じく、コミットできる（要件の写しは、作業ツリーとインデックスで同じ指紋に入る）" 0 precommit
# そのブランチで最初に写しを保存したターンの開始時に既にあった未追跡のファイル（利用者の手元のファイル）は、変えていなければ
# 作業ツリーの指紋から除く（部分コミットを止めない）。コミットに含めるなら証拠が要る
$G switch -q -c feat/bl main; write scratch.py mine; turn; reqs
write src/app.py bl1; write tests/test_app.py bl1; bash_ "uv run pytest -q"; accept; review reviewer
check "前からあった未追跡のコードがあっても、証拠をそろえた変更は通す" pass "$(stop)"
$G add src/app.py tests/test_app.py
checkx "（同じく）前からあったファイルを除いた部分コミットができる" 0 precommit
$G add scratch.py
checkx "前からあったファイルをコミットに含めるなら、証拠が要る" 1 precommit
$G reset -q scratch.py; reqs
check "写しを保存し直しても、前からあったファイルは除いたまま（最初の保存の時点で決まる）" pass "$(stop)"
write scratch.py changed
check "前からあったファイルでも、その後に変えたら証拠が要る" block "$(stop)"
write scratch.py mine; $G add -A; bash_ "uv run pytest -q"; accept; review reviewer
checkx "前からあったファイルも、ステージして証拠をそろえればコミットできる" 0 precommit
rm "$REPO/scratch.py"; $G reset -q --hard; $G switch -q feat/x
# 写しは、保存した後に HEAD が進んだら（コミット等）古い。次のコード変更には保存し直しが要る（同じ依頼の続きなら同じ内容でよい）
fresh; ready st1; $G add -A; $GH commit -q -m st1
write src/app.py st2; write tests/test_app.py st2; bash_ "uv run pytest -q"; accept; review reviewer; r=$(stop)
check "保存した後にコミットがあった写しは古いので、ほかの証拠がそろっていても差し戻す" block "$r"
expect "理由に、写しを保存し直すことが出る" has "$r" "保存し直す"
$G add -A
checkx "（同じく）pre-commit も拒否する" 1 precommit
reqs
check "同じ内容で保存し直せば、以前の証拠のまま通す" pass "$(stop)"
checkx "（同じく）pre-commit も通す" 0 precommit

# テストが十分か（TDD）は reviewer が判定する。hook はテストファイルの有無を見ない
fresh; write src/app.py refactor-only; bash_ "uv run pytest -q"; accept; review reviewer
check "コードだけの変更（リファクタ等）でも、検証・受け入れと 3 軸の承認があれば通す" pass "$(stop)"
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
bash_ "uv run pytest -q"; accept; review reviewer
check "（前提）証拠がそろえば通す" pass "$(stop)"
fresh; rm "$REPO/tests/test_base.py"
check "既存のテストの削除は差し戻す" block "$(stop)"
$G add -A
checkx "同じく、既存のテストの削除をステージしたコミットにも証拠が要る" 1 precommit
fresh; write tests/test_added.py t; $G add -A
checkx "新しいテストの追加だけなら、コミットに証拠は要らない" 0 precommit
# テストの集め方を変えうるファイル（conftest.py・__init__.py・*.config.*・pytest.ini）は、テストのディレクトリにあっても追加に証拠が要る
for f in tests/conftest.py tests/sub/__init__.py tests/jest.config.js tests/pytest.ini; do
  fresh; write "$f" x; $G add -A
  checkx "テストのディレクトリの $f の追加にも、コミットに証拠が要る" 1 precommit
done

# 設定ファイル・ビルド定義もコード
for f in pyproject.toml package.json compose.yaml .github/workflows/ci.yml tox.ini setup.cfg src/m.mts src/m.cts run.bash \
  Dockerfile sub/Makefile justfile; do
  fresh; write "$f" x
  check "設定ファイル・ビルド定義だけの変更も差し戻す: $f" block "$(stop)"
done
# マークアップ・スタイル・IaC・R なども対象（拡張子の大文字小文字は区別しない）。Markdown・.txt・画像は対象外のまま
for f in pom.xml main.tf style.css analysis.R build.gradle.kts; do
  fresh; write "$f" x
  check "コードとして差し戻す: $f" block "$(stop)"
done
for f in README.md notes.txt logo.png; do
  fresh; write "$f" x
  check "文書・画像だけの変更は通す: $f" pass "$(stop)"
done
# 文書・画像など以外はすべて対象（依存の定義・lockfile・環境・テンプレート・スキーマなど、振る舞いを変えうるもの）
for f in requirements.txt requirements-dev.txt requirements/base.txt CMakeLists.txt go.mod uv.lock Cargo.lock Gemfile .env app/views/x.erb templates/x.j2 \
  prisma/schema.prisma tsconfig.jsonc BUILD.bazel Procfile data/seed.csv; do
  fresh; write "$f" x
  check "文書・画像以外は差し戻す: $f" block "$(stop)"
done
for f in docs/guide.rst CHANGELOG LICENSE.md assets/icon.svg docs/spec.pdf src/.DS_Store; do
  fresh; write "$f" x
  check "文書・画像だけの変更は通す: $f" pass "$(stop)"
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
fresh; mkdir -p "$REPO/src"; CWD="$REPO/src"; turn; write src/deep.py c; write tests/test_deep.py t; bash_ "cd $REPO && uv run pytest -q"; accept; review reviewer
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
  checkx "マージ・cherry-pick・revert の途中（$ref あり）でも、自動の結果と違うコードの変更には証拠が要る" 1 precommit
  rm "$REPO/.git/$ref"
done
OTHER="$TMP/other"; git init -q -b feat "$OTHER"; echo c > "$OTHER/app.py"; git -C "$OTHER" add -A
checkx "Claude が作業していないリポジトリ（テストが作る一時リポジトリ等）は対象外" 0 sh -c "cd '$OTHER' && '$HOOK' pre-commit"
OUTSIDE="$TMP/outside"; git init -q -b feat "$OUTSIDE"; echo c > "$OUTSIDE/app.py"; git -C "$OUTSIDE" add -A; mkdir -p "$TMP/elsewhere"
checkx "未登録でも、一時ディレクトリ（TMPDIR）の外のリポジトリには関門を掛ける（親ディレクトリから git -C でコミットした場合など）" 1 \
  env TMPDIR="$TMP/elsewhere" sh -c "cd '$OUTSIDE' && '$HOOK' pre-commit"
checkx "（同じリポジトリでも）一時ディレクトリの中にあれば、未登録なら対象外" 0 env TMPDIR="$TMP" sh -c "cd '$OUTSIDE' && '$HOOK' pre-commit"
CWD="$OTHER"; bash_ "ls"; CWD=""
checkx "ターンの途中で cd した先のリポジトリも、そこでコマンドを実行した時点から対象になる" 1 sh -c "cd '$OTHER' && '$HOOK' pre-commit"
# 検証コマンドの宣言（.harness-verify か <git-common-dir>/harness-verify）が無いリポジトリでは、何を成功させても検証の証拠にならない
CWD="$OTHER"; reqs; bash_ "uv run pytest -q"; accept; review reviewer; r=$(stop); CWD=""
DECL="全体の検証コマンドを .harness-verify（共有）か $(cd "$OTHER" && pwd -P)/.git/harness-verify（自分だけ）に 1 行 1 つ書く"
check "宣言が無ければ、検証・受け入れ・レビューがそろっても差し戻す" block "$r"
expect "差し戻しの理由に、宣言の置き場所（共有・自分だけ）が出る" [ -n "$(printf '%s' "$r" | grep -F "$DECL")" ]
expect "pre-commit も拒否し、理由に宣言の置き場所が出る" [ -n "$(cd "$OTHER" && "$HOOK" pre-commit 2>&1 | grep -F "$DECL" || true)" ]
echo 'uv run pytest -q' > "$OTHER/.git/harness-verify"   # 自分だけの宣言（リポジトリに置けないとき）
CWD="$OTHER"; bash_ "uv run pytest -q"; accept; review reviewer; CWD=""   # 自分だけの宣言は指紋に入るので、書いた後に取り直す
checkx "自分だけの宣言でも、そのリポジトリを cwd にして宣言したコマンドを成功させ、受け入れ・レビューすればコミットできる" 0 sh -c "cd '$OTHER' && '$HOOK' pre-commit"
BROKEN="$TMP/broken"; git init -q -b feat "$BROKEN"; CWD="$BROKEN"; turn; CWD=""; echo junk > "$BROKEN/.git/index"
checkx "判定できないとき（git が失敗する等）はコミットを止める" 1 sh -c "cd '$BROKEN' && '$HOOK' pre-commit"
fresh; ready h1; write README.md doc-first; $G add README.md; $G commit -q -m docs; $G add -A
checkx "ドキュメントを先にコミットして HEAD が動いても、コードの証拠は有効なまま" 0 precommit
fresh; mv "$REPO/src/lib.py" "$REPO/src/lib2.py"; write tests/test_app.py r; bash_ "uv run pytest -q"; accept; review reviewer; $G add -A
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
fresh; write src/app.py c; write tests/test_app.py t; ln -s app.py "$REPO/src/alias.py"; ln -s src/app.py "$REPO/runme"; bash_ "uv run pytest -q"; accept; review reviewer; $G add -A
checkx "シンボリックリンクを含む変更も、証拠がそろっていればコミットできる" 0 precommit
fresh; $G config core.autocrlf true; printf 'a\r\nb\r\n' > "$REPO/src.py"; write tests/test_app.py t; bash_ "uv run pytest -q"; accept; review reviewer; $G add -A 2>/dev/null
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
CWD="$WT"; turn; reqs; write_wt() { echo "$2" > "$WT/$1"; }; write_wt src/w.py c2; bash_ "uv run pytest -q"; accept; review reviewer; CWD=""
git -C "$WT" add -A
checkx "worktree でも、証拠がそろえばコミットできる" 0 $GW commit -q -m "wt"
echo d > "$WT/README.md"; git -C "$WT" add README.md
mkdir -p "$REPO/.git/hooks"; printf '#!/bin/sh\nexit 1\n' > "$REPO/.git/hooks/pre-commit"; chmod +x "$REPO/.git/hooks/pre-commit"
checkx "worktree からでも、本体リポジトリの .git/hooks に委譲される" 1 $GW commit -q -m docs
rm "$REPO/.git/hooks/pre-commit"

# ---- 関門（pre-commit）を通らなかったコミットを Stop で見つける（git の hook に依らない事後の確認）----
fresh; write src/app.py ug1; $G add -A; $G commit -q -m unguarded   # hook を通らないコミット（$G は共通 hooks を使わない）
r=$(stop)
check "このターンに pre-commit を通らずにコードをコミットしたら、Stop が差し戻す" block "$r"
expect "理由に、そのコミットと戻し方（git reset --soft）が出る" sh -c "printf '%s' \"\$1\" | grep -q '$($G rev-parse --short HEAD)' && printf '%s' \"\$1\" | grep -q 'reset --soft'" _ "$r"
fresh; ready ug2; $G add -A; $GH commit -q -m gated
check "pre-commit を通ったコミットでは差し戻さない" pass "$(stop)"
# リポジトリ自身の pre-commit（lint-staged の整形など）が関門の後でインデックスを書き換えても、関門を通ったコミットとして扱う
mkdir -p "$REPO/.git/hooks"; printf '#!/bin/sh\necho formatted >> src/app.py && git add src/app.py\n' > "$REPO/.git/hooks/pre-commit"; chmod +x "$REPO/.git/hooks/pre-commit"
fresh; ready ug4; $G add -A; $GH commit -q -m gated-then-formatted
rm "$REPO/.git/hooks/pre-commit"
expect "（前提）リポジトリの hook が整形した内容がコミットされている" grep -q formatted "$REPO/src/app.py"
check "関門の後でリポジトリの hook がインデックスを書き換えても、関門を通ったコミットでは差し戻さない" pass "$(stop)"
fresh; write src/app.py ug5; $G add -A; $GH commit -q -n -m skipped   # -n で pre-commit を飛ばす（post-commit は呼ばれる）
check "pre-commit を飛ばしたコミットは、post-commit が呼ばれても関門を通ったことにならない" block "$(stop)"
write src/app.py ug3; $G add -A; $G commit -q -m before; turn
check "ターンより前のコミットでは差し戻さない" pass "$(stop)"
# マージの途中のコミット: 自動の結果（git merge-tree）との差（競合の解消・--no-commit の後に足したもの）だけに証拠を求める
side() { # side <ブランチ名> <パス> <内容>: feat/x から分かれたブランチに 1 コミット作って feat/x に戻る（ターンの前に）
  $G switch -q -c "$1"; write "$2" "$3"; $G add -A; $G commit -q -m "$1"; $G switch -q feat/x; }
fresh; side m1 src/side1.py s1; turn
$G merge -q --no-commit --no-ff m1 >/dev/null 2>&1; write src/evil.py e; $G add -A
checkx "マージの途中に足したコードは、証拠なしではコミットできない" 1 precommit
check "そのまま Stop しても差し戻す" block "$(stop)"
$G rm -q --cached src/evil.py; rm "$REPO/src/evil.py"
checkx "自動のマージの結果のままなら、証拠は要らない" 0 precommit
check "（同じく）Stop も通す" pass "$(stop)"
$G commit -q -m "merge m1"
fresh; side m2 src/side2.py s2; turn
$G merge -q --no-commit --no-ff m2 >/dev/null 2>&1; write src/evil2.py e; $G add -A; $G commit -q -m "merge m2 with extra"   # 関門を通らないマージコミット
check "自動の結果と違うマージコミットを関門を通らずに作れば、Stop が差し戻す" block "$(stop)"
fresh; side m3 src/side3.py s3; turn; $G merge -q --no-ff -m "merge m3" m3
check "自動の結果のままのマージコミットでは、Stop は差し戻さない" pass "$(stop)"
# 競合の解消: 解消した内容に証拠を求める（取り込む側の変更全体には求めない）
fresh; side m4 src/lib.py theirs; write src/lib.py ours; $G add -A; $G commit -q -m ours; reqs; turn
$G merge -q m4 >/dev/null 2>&1 || true; write src/lib.py resolved; $G add -A
checkx "競合を解消した内容は、証拠なしではコミットできない" 1 precommit
bash_ "uv run pytest -q"; accept; review reviewer
checkx "解消した内容に証拠をそろえればコミットできる" 0 precommit
$G commit -q -m "merge m4"
# 実際の git で: リポジトリ側の core.hooksPath（husky 等）があると、共通 hooks の pre-commit は呼ばれない
HUSKY="$TMP/husky"; git init -q -b main "$HUSKY"; echo 'uv run pytest -q' > "$HUSKY/.harness-verify"
git -C "$HUSKY" add -A; git -C "$HUSKY" -c user.name=t -c user.email=t@t commit -q -m init; git -C "$HUSKY" switch -q -c feat/h
printf '[core]\n\thooksPath = %s\n[user]\n\tname = t\n\temail = t@t\n' "$HOOKS" > "$TMP/global.gitconfig"
CWD="$HUSKY"; turn; echo c1 > "$HUSKY/app.py"; git -C "$HUSKY" add -A
checkx "（前提）リポジトリ側の設定が無ければ、共通 hooks の pre-commit が証拠なしのコミットを止める" 1 env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" commit -q -m gated
mkdir -p "$HUSKY/.husky"; git -C "$HUSKY" config core.hooksPath .husky
checkx "（前提）リポジトリ側の core.hooksPath があると pre-commit は呼ばれず、証拠なしでコミットできてしまう" 0 env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" commit -q -m nohook
check "その証拠なしのコミットを、Stop が差し戻す" block "$(stop)"
git -C "$HUSKY" reset -q --soft HEAD~1   # 差し戻しの手順どおりに戻す（以下はそのコミットが無い状態で）
# 共通の pre-commit が呼ばれないリポジトリでは、Bash の git commit の前（PreToolUse）に関門の判定をする
turn; echo c2 > "$HUSKY/app.py"
checkd "リポジトリ側の core.hooksPath があれば、証拠なしの git commit は Bash の前に拒否する" deny "$(guardb "git add -A && git commit -m x")"
expect "理由に、足りない証拠が出る" has "$(guardb "git commit -am x")" "/accept"
CWD="$TMP"; checkd "git -C で指しても同じ" deny "$(guardb "git -C $HUSKY commit -am x")"; CWD="$HUSKY"
reqs; mkdir -p "$HUSKY/tests"; bash_ "uv run pytest -q"; accept; review reviewer
checkd "証拠がそろえば、git commit を通す" allow "$(guardb "git add -A && git commit -m x")"
# 判定を通したコミット（git add と git commit だけのコマンド）は、実行の後に関門を通ったコミットとして記録する
env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" add -A
env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" commit -q -m judged
bash_ "git add -A && git commit -m x"
check "判定を通したコミットは、Stop で関門を通っていないとみなさない" pass "$(stop)"
checkd "（同じく）push も拒否しない" allow "$(guardb "git push origin feat/h")"
# メッセージをヒアドキュメントで渡す形・読むだけの git を挟んだ形でも、判定を通したコミットとして記録する
turn; echo c3 > "$HUSKY/app.py"; reqs; bash_ "uv run pytest -q"; accept; review reviewer
c="git add -A && git status && git commit -q -F - <<'EOF'\\nmsg\\nEOF"
checkd "（前提）証拠がそろえば、ヒアドキュメントの形の git commit も通す" allow "$(guardb "$c")"
env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" add -A
printf 'msg\n' | env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" commit -q -F -; bash_ "$c"
check "ヒアドキュメントの形でも、判定を通したコミットは Stop で差し戻さない" pass "$(stop)"
# ただし記録するのは、コミットした内容が証拠の付いた内容と同じときだけ（ステージだけ違う内容・一部だけのコミットは記録しない）
turn; echo BAD > "$HUSKY/app.py"; git -C "$HUSKY" add app.py; echo GOOD > "$HUSKY/app.py"; reqs; bash_ "uv run pytest -q"; accept; review reviewer
checkd "（前提）作業ツリーには証拠があるので、判定は通す" allow "$(guardb "git commit -m sneaky")"
env GIT_CONFIG_GLOBAL="$TMP/global.gitconfig" git -C "$HUSKY" commit -q -m sneaky; bash_ "git commit -m sneaky"
git -C "$HUSKY" checkout -q -- app.py   # 作業ツリーをコミットした内容にそろえる（事後の確認だけで判断させる）
r=$(stop)
check "証拠の付いた内容と違うものをコミットしたら、Stop が差し戻す" block "$r"
expect "（そのとき）理由は、関門を通っていないコミット" has "$r" "関門（pre-commit）を通っていない"
git -C "$HUSKY" reset -q --hard HEAD~1
CWD=""
checkd "（前提）リポジトリ側の設定が無ければ、Bash の前には判定しない（pre-commit が判定する）" allow "$(guardb "git commit -m x")"
# git push の前: このターンに作った、関門を通っていないコード変更のコミットがあれば拒否する
fresh; write src/app.py p1; $G add -A; $G commit -q -m ungated
checkd "このターンに関門を通っていないコミットがあれば、git push を拒否する" deny "$(guardb "git push origin feat/x")"
stop >/dev/null; turn
checkd "前のターンに Stop が見つけた、関門を通っていないコミットも、リモートに無ければ push を拒否する" deny "$(guardb "git push origin feat/x")"
$G switch -q main
checkd "別のブランチに移っても、ローカルのブランチに残っていれば push を拒否する" deny "$(guardb "git push origin feat/x")"
$G switch -q feat/x
git init -q --bare "$TMP/pushed.git"; $G remote add pushed "$TMP/pushed.git"; $G push -q pushed HEAD:refs/heads/feat/x
checkd "（前提）リモートに出た後は、push を止めない（ほかに残っていなければ）" allow "$(guardb "git push origin feat/x")"
$G remote remove pushed
# 自動の結果を求められないマージ（無関係な履歴。merge-tree が失敗する）に足したコードも、関門を通らなければ Stop が差し戻す
fresh; $G switch -q --orphan un1; write src/un.py u; $G add src/un.py; $G commit -q -m un1; $G switch -q feat/x; turn
$G merge -q --no-commit --allow-unrelated-histories un1 >/dev/null 2>&1; write src/extra.py e; $G add -A; $G commit -q -m "merge unrelated"
r=$(stop)
check "自動の結果を求められないマージに足したコードを関門を通らずにコミットすれば、Stop が差し戻す" block "$r"
expect "（そのとき）理由は、関門を通っていないコミット" has "$r" "関門（pre-commit）を通っていない"
$G reset -q --hard HEAD~1
# 3 つ以上の親のマージ: 手を加えたもの（--no-commit の後に足したもの）は、関門を通らなければ Stop が差し戻す
fresh; side o1 src/o1.py a; side o2 src/o2.py b; turn
$G merge -q --no-ff --no-commit o1 o2 >/dev/null 2>&1; write src/octo.py y; $G add -A; $G commit -q -m octopus
expect "（前提）3 つの親のマージコミットができている" [ "$($G rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 4 ]
check "手を加えた 3 つの親のマージコミットを関門を通らずに作れば、Stop が差し戻す" block "$(stop)"

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
for c in "git commit --no-verify -m x" "git commit --no-veri -m x" "git commit --no-verif -m x" "git commit -n -m x" "git commit -anm x" \
  "git -c core.hooksPath=/dev/null commit -m x" "git -c core.hookspath=/dev/null commit -m x" "env -u CLAUDECODE git commit -m x" \
  "unset CLAUDECODE && git commit -m x" "CLAUDECODE= git commit -m x" "export -n CLAUDECODE" \
  "GIT_CONFIG_GLOBAL=/dev/null git commit -m x" "GIT_CONFIG=/dev/null git commit -m x" "export GIT_CONFIG_GLOBAL=/dev/null" \
  "env GIT_CONFIG_GLOBAL=/dev/null git commit -m x" "git commit-tree abc" "cp ~/.local/state/harness/repo/x/verified ~/.local/state/harness/repo/x/reviewed"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
# メッセージの値を除くのは -n の検出だけ。値の外の -n、sh -c・bash -c・eval の引数、ヒアドキュメントの本文、コマンド置換は検査する
# （JSON に入れるので、" は \" と書く。\n は改行）
for c in 'git commit -m \"x\" --no-verify' 'git commit --no-verify -m \"x\"' 'git commit -m \"x\" -n' "git commit -m 'x' -n" "git commit -Cm -n" \
  'sh -c \"git commit --no-verify\"' 'sh -c \"git commit -n -m x\"' 'git commit -m \"$(git commit -n -m y)\"' 'sh <<E\ngit commit -n -m x\nE' \
  "git -C /tmp commit-tree abc" "bash -c 'git --no-pager commit-tree abc'" "eval 'commit-tree abc'" "true && commit-tree abc" \
  '$(git --exec-path)/git-commit-tree abc' "git config alias.ct commit-tree" \
  "git config core.hooksPath /tmp/h" "git config --global --unset core.hooksPath" "git --config-env=core.hooksPath=H commit -m x" \
  "sed -i '' '/hooksPath/d' ~/.config/git/config" "sed -i.bak 's/x/y/' ~/.gitconfig" "echo x >> .git/config" "tee -a ~/.gitconfig" \
  "perl -pi -e 's/x//' ~/.config/git/config" \
  "grep -v hooksPath ~/.config/git/config > /tmp/c && mv /tmp/c ~/.config/git/config" "cp /tmp/c ~/.gitconfig" \
  "install -m 644 /tmp/c .git/config" "ln -sf /tmp/c ~/.config/git/config" \
  'git commit --author \"a -m\" -n \"x\"' "git commit --author 'a -m' -n 'x'" "git -c alias.c=commit c -n"; do
  checkd "拒否する: $(printf '%s' "$c" | tr '\\' ' ')" deny "$(guardb "$c")"
done
# コマンドの区切りはクォートの外の ; & | 改行だけ（>& のリダイレクト、コマンド置換の中、ヒアドキュメントの本文でも読み違えない）。
# sh -c・bash -c・eval の引数も 1 つのコマンド行として同じく見る
for c in 'git commit -m \"a; b\" -n' "git commit -m 'a && b' -n" 'git commit -m \"a | b\" -n' "git commit -m x 2>&1 -n" \
  'git commit -m \"\" -n' 'git commit -m x \\\n -n' 'git commit -m \"$(printf \"a; b\")\" -n' \
  "git commit -m \\\"\$(cat <<'EOF'\\nIt's a fix\\nEOF\\n)\\\" -n" "cat <<'E'\\ndon't\\nE\\ngit commit -n -m x\\ncat <<'E'\\nit's\\nE" \
  "git commit -m \$'\\\\'' -n ''" "bash -c 'git commit -m x -n'" "eval 'git commit -n -m x'" 'zsh -c \"git commit -anm x\"' \
  "bash -c 'cp /tmp/c ~/.gitconfig'" "cp /tmp/config ~/.config/git/" "mv /tmp/config ~/.config/git" "cp config .git/" \
  "cp -t ~/.config/git /tmp/config" "cp --target-directory=.git config" "cp /tmp/.gitconfig ~/" "cp /tmp/x ~/.config/git/hooks/pre-commit" \
  "(rm -rf ~/.config/git/hooks)" "(mv /tmp/c .git/config)" 'echo $(cp /tmp/c ~/.gitconfig)'; do
  checkd "拒否する: $(printf '%s' "$c" | tr '\\' ' ')" deny "$(guardb "$c")"
done
# git の字句はクォートを外して見る: サブコマンドの commit-tree、-c・--config-env・git config での core.hooksPath の設定、
# 迂回になる alias の定義（値を git のコマンドとして見る。! のシェルの alias も）
for c in 'git \"commit-tree\" abc' "git 'commit-tree' abc" 'git -c core.\"hooksPath\"=/x commit -m x' 'git -c \"core.hooksPath\"=/x commit -m x' \
  'git --config-env=\"core.hooksPath\"=H commit -m x' "git config core.'hooksPath' /x" "git config alias.c 'commit -n'" \
  'git config --global alias.c \"commit -n\"' "git -c alias.c='commit -n' c -m x" 'git -c \"alias.c=commit -n\" c -m x' \
  "git config alias.t '!git commit-tree x'" "git config alias.t commit-tree" "git -c alias.c='!git commit -n' c" \
  "git config alias.c '!sh -c \\\"git commit --no-verify\\\"'"; do
  checkd "拒否する: $(printf '%s' "$c" | tr '\\' ' ')" deny "$(guardb "$c")"
done
# 証拠を記録する hook のサブコマンドを Bash から直接呼ぶ形は拒否する（偽の入力で証拠を作れる）。写しの保存と場所は通す
for c in "harness-hook review-done <<'E'\\n{}\\nE" "~/.local/bin/harness-hook bash < /tmp/forged.json" "echo '{}' | harness-hook review-done" \
  "uv run --script bin/harness-hook stop" "harness-hook post-commit" "/usr/bin/env harness-hook review-done < /tmp/x.json"; do
  checkd "拒否する: $(printf '%s' "$c" | tr '\\' ' ')" deny "$(guardb "$c")"
done
for c in "harness-hook requirements-path" "harness-hook requirements-save < /tmp/req.md" "cat bin/harness-hook" "grep -n review-done bin/harness-hook" \
  "echo harness-hook review-done" "grep -n harness-hook stop.md"; do
  checkd "通す: $c" allow "$(guardb "$c")"
done
# 環境を差し替えて git の hook を外す形（HOME・XDG_CONFIG_HOME の差し替え、env -i）は拒否する。読むだけの形は通す
for c in "env -i PATH=/usr/bin git commit -m x" "HOME=/tmp/h git commit -m x" "XDG_CONFIG_HOME=/tmp/x git commit -m x" \
  "env - git commit -m x" "HOME=/x command git commit -m x" "XDG_CONFIG_HOME=/x nohup git commit -m x" \
  "FOO=1 HOME=/tmp/h git commit -m x" "git config -c core.hooksPath= commit -m x" "git -c core.hooksPath= commit -m x"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
for c in "git config core.hooksPath" "git config --global core.hooksPath" "GIT_CONFIG_NOSYSTEM=1 git status" "HOME=/tmp/h ls" "env -i ls"; do
  checkd "通す: $c" allow "$(guardb "$c")"
done
# 読むだけの形を通しても、設定する・消す形は拒否のまま
for c in "git config --unset core.hooksPath" "git config --add core.hooksPath /x" "env CLAUDECODE= git commit -m x" "FOO=1 CLAUDECODE= git commit -m x" \
  "if true; then CLAUDECODE= git commit -m x; fi" "{ CLAUDECODE= git commit -m x; }" "nohup CLAUDECODE= git commit -m x" \
  "time CLAUDECODE= git commit -m x" "command CLAUDECODE= git commit -m x" "exec CLAUDECODE= git commit -m x" "sudo -E CLAUDECODE= git commit -m x" \
  "declare CLAUDECODE=; git commit -m x" "typeset -x CLAUDECODE=" "local CLAUDECODE=" "readonly CLAUDECODE=" \
  "git config core.hooksPath --get" "git config --global core.hooksPath --get-all" "git config core.hooksPath -l" \
  "git commit --no-verify=true -m x" "git log -1 && git commit -n -m x" "/usr/bin/git commit -n -m x" "git -C . commit -n -m x"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
# 文字列で見る形（BYPASS）も、クォートを外したコマンドに当てる（クォートで語を割る形）。別の設定ファイルを読ませる include.path、
# rsync での上書きも拒否する
for c in 'git commit --\"no-verify\" -m x' 'git commit --no-\"verify\" -m x' 'env -u \"CLAUDECODE\" git commit -m x' "unset 'CLAUDECODE'" \
  "git config --global include.path /tmp/evil" "git -c include.path=/tmp/evil commit -m x" \
  'git config --global includeIf.\"gitdir:~/\".path /tmp/evil' "rsync -a /tmp/c/ ~/.config/git/" "rsync /tmp/x ~/.config/git/hooks/pre-commit"; do
  checkd "拒否する: $(printf '%s' "$c" | tr '\\' ' ')" deny "$(guardb "$c")"
done
# rsync の -t は時刻を保つオプション（cp の -t のように行き先を取らない）
for c in "rsync -avt src/ ~/.config/git/hooks/" "rsync -rt /tmp/c/ ~/.config/git/"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
# ヒアドキュメントの本文を検査するのは、シェル・インタプリタに渡すとき（同じ行にシェル等の語があるとき）だけ。
# 記憶の保存・コミットメッセージ・ファイルへの書き出しの本文は、ただのデータなので迂回の語があっても通す
for c in "bash -s <<'E'\\ngit commit -n -m x\\nE" "cat <<'E' | sh\\ngit commit -n -m x\\nE" \
  "python3 - <<'E'\\nimport os; os.system('git commit -n -m x')\\nE" "ssh nas <<'E'\\ngit commit --no-verify -m x\\nE" \
  "awk '{system(\$0)}' <<'E'\\ngit commit -n -m x\\nE" "fish <<'E'\\ngit commit -n -m x\\nE" \
  "cat > x.sh <<'E'\\ngit commit -n -m x\\nE\\nsh x.sh" "cat > f <<'E'\\ngit commit -n -m x\\nE\\nchmod +x f && ./f" \
  "tee f <<'E' >/dev/null\\ngit commit -n -m x\\nE\\n. ./f" "sh<<'E'\\ngit commit --no-verify -m x\\nE" "bash<<E\\ngit commit -n -m x\\nE" \
  "\$SHELL <<'E'\\ngit commit --no-verify -m x\\nE" "cd .git && cat >> config <<'E'\\n[core]\\n\\thooksPath = /dev/null\\nE" \
  "cat >> \\\"\$(git rev-parse --git-dir)/config\\\" <<'E'\\n[core] hooksPath = /dev/null\\nE" "! CLAUDECODE= git commit -m x" \
  "cat > Makefile <<'E'\\nall:\\n\\tgit commit --no-verify -m x\\nE\\nmake" \
  "cat > package.json <<'E'\\n{\\\"scripts\\\":{\\\"c\\\":\\\"git commit --no-verify -m x\\\"}}\\nE\\nnpm run c" \
  "git commit \$(cat <<E\\n--no-verify\\nE\\n) -m x" "git -c \\\"\$(cat <<E\\ncore.hooksPath=/dev/null\\nE\\n)\\\" commit -m x" \
  "read -r a <<E\\n--no-verify\\nE\\ngit commit \$a -m x" "cat >> \\\"\$(git rev-parse --git-path config)\\\" <<E\\n[core]\\nhooksPath=/x\\nE" \
  "cat > mise.toml <<'E'\\n[tasks.c]\\nrun = \\\"git commit --no-verify -m x\\\"\\nE\\nmise run c" \
  "git -c alias.x='!sh' x <<'E'\\ngit commit -n -m x\\nE" "git x <<'E'\\ngit commit --no-verify -m x\\nE" "gh x <<'E'\\ngit commit --no-verify -m x\\nE" \
  "cat <<'E' | git x\\ngit commit --no-verify -m x\\nE" "cd ~ && git apply <<'E'\\n+\\thooksPath = /dev/null\\nE" \
  "git apply --unsafe-paths --directory=\\\"\$HOME\\\" <<'E'\\n+\\thooksPath = /dev/null\\nE" \
  "git -c core.editor='sh -c' commit <<'E'\\ngit commit --no-verify -m x\\nE" "git -c core.pager=sh log <<'E'\\ngit commit --no-verify -m x\\nE" \
  "GIT_EDITOR='sh -c' git commit <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git commit -e -F - <<'E'\\ngit config --global core.hooksPath /dev/null\\nE" "git commit --edit -F - <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git tag -a v1 -e -F - <<'E'\\ngit commit --no-verify -m x\\nE" "git notes add -e -F - <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git commit -aeF - <<'E'\\ngit commit --no-verify -m x\\nE" "git commit --ed -F - <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git commit -F - --e <<'E'\\ngit commit --no-verify -m x\\nE" "git tag -a v1 --edi -F - <<'E'\\ngit commit --no-verify -m x\\nE" \
  "gh pr create -e --body-file - <<'E'\\ngit commit --no-verify -m x\\nE" "gh pr create --editor --body-file - <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git commit -t /dev/stdin <<'E'\\ngit commit --no-verify -m x\\nE" "git commit --template=/dev/stdin <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git commit -a -t /dev/stdin <<'E'\\ngit commit --no-verify -m x\\nE" "git commit -c HEAD <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git -p commit -F - <<'E'\\ngit commit --no-verify -m x\\nE" "cat <<'E' | git commit -F - && git -p log\\ngit commit --no-verify -m x\\nE" \
  "gh pr create --editor=true --body-file - <<'E'\\ngit commit --no-verify -m x\\nE" "gh pr create -e=true --body-file - <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git commit -a <<'E'\\ngit commit --no-verify -m x\\nE" "git commit --signoff <<'E'\\ngit commit --no-verify -m x\\nE" \
  "git tag -a v1 <<'E'\\ngit commit --no-verify -m x\\nE" "git notes add <<'E'\\ngit commit --no-verify -m x\\nE"; do
  checkd "拒否する: $(printf '%s' "$c" | tr '\\' ' ')" deny "$(guardb "$c")"
done
for c in "tinymemory save --type fact --title t <<'E'\\ngit commit -n と --no-verify は使わない。hooksPath を rsync で戻す形も拒否\\nE" \
  "git commit -F - <<'E'\\nguard: deny --no-verify, commit-tree and git commit -n\\nE" "cat > notes.md <<'E'\\ngit commit -n -m x\\nE" \
  "cat > f <<'E'\\nset core.hooksPath carefully\\nE" "cat > docs/notes.md <<'E'\\nthe hook blocks git config core.hooksPath /x\\nE" \
  "tinymemory save --tag go <<'E'\\nnever git commit --no-verify\\nE" "tinymemory save --title \\\"bash tips\\\" <<'E'\\nnever git commit --no-verify\\nE" \
  "gh pr create --title t --body-file - <<'E'\\nnever git commit --no-verify\\nE" "git -C . commit -q -F - <<'E'\\navoid --no-verify\\nE" \
  "git commit -aF - <<'E'\\navoid --no-verify\\nE" "git tag -a v1 -F - <<'E'\\navoid --no-verify\\nE" "git notes add -F - <<'E'\\navoid --no-verify\\nE" \
  "cat <<'E' | git commit --file=- --cleanup=strip\\navoid --no-verify\\nE" "git add -A && git commit -q -F - <<'E'\\navoid --no-verify\\nE"; do
  checkd "通す: $(printf '%s' "$c" | tr '\\' ' ')" allow "$(guardb "$c")"
done
for c in "git config alias.st status" "git config alias.ci commit" "git -c alias.lg='log --oneline -n 5' lg" "git grep -n commit-tree" \
  "rsync -a src/ /tmp/dest/" "rsync -rt ~/.config/git/ /tmp/backup/"; do
  checkd "通す: $c" allow "$(guardb "$c")"
done
# hooksPath を含む行で書き込む（リダイレクト・mv・cp・rsync・sponge・tee・sed -i など）形は、行き先を問わず拒否する（cd の後の相対パスでも）
for c in "cd ~/.config/git && grep -v hooksPath config > /tmp/c && mv /tmp/c config" \
  "grep -v hooksPath ~/.config/git/config > /tmp/c && rsync /tmp/c ~/.config/git/config" \
  "grep -v hooksPath ~/.config/git/config | sponge ~/.config/git/config"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
# hook（~/.config/git/hooks・.git/hooks とその下、~/.local/bin/harness-hook、~/.local/libexec/uv）を消す・動かす・権限を変える・
# 差し替える・書き換える形は拒否する。読むだけと、hook を元にした cp（写しを作る）は通す
for c in "rm ~/.config/git/hooks/pre-commit" "rm -rf ~/.config/git/hooks" 'unlink $HOME/.config/git/hooks/run-hook' \
  'shred -u ${XDG_CONFIG_HOME}/git/hooks/pre-commit' "truncate -s 0 ~/.local/bin/harness-hook" "rm .git/hooks/pre-commit" \
  "mv ~/.config/git/hooks /tmp/h" "mv /tmp/x ~/.config/git/hooks/pre-commit" "mv ~/.config/git ~/.config/git.bak" \
  "chmod -x ~/.config/git/hooks/run-hook" "chmod 000 ~/.local/libexec/uv" "chattr +i .git/hooks/pre-commit" \
  "chflags uchg ~/.config/git/hooks/pre-commit" "ln -sf /tmp/x ~/.config/git/hooks/pre-commit" "ln -s /tmp/x ~/.local/bin/harness-hook" \
  "cp /tmp/x ~/.config/git/hooks/pre-commit" "install -m 755 /tmp/x .git/hooks/pre-commit" "cp -r /tmp/hooks ~/.config/git/" \
  "echo 'exit 0' > ~/.config/git/hooks/pre-commit" "printf x >> ~/.local/bin/harness-hook" "echo x >~/.config/git/hooks/pre-commit" \
  "echo x | tee ~/.config/git/hooks/pre-commit" "sed -i '' 's/1/0/' ~/.config/git/hooks/run-hook" \
  "bash -c 'rm ~/.config/git/hooks/pre-commit'" "rm ~/.config/git/config" "mv ~/.gitconfig /tmp/"; do
  checkd "拒否する: $c" deny "$(guardb "$c")"
done
for c in "cat ~/.config/git/hooks/run-hook" "ls -l ~/.config/git/hooks" "grep -n exit ~/.config/git/hooks/run-hook" \
  "head ~/.local/bin/harness-hook" "file ~/.local/libexec/uv" "sh -n ~/.config/git/hooks/run-hook" "test -x .git/hooks/pre-commit" \
  "cp ~/.config/git/hooks/run-hook /tmp/run-hook.copy" "cp -r .git /tmp/backup" "mv /tmp/f ~" "rm -rf /tmp/x" "chmod +x tests/x.sh"; do
  checkd "通す: $c" allow "$(guardb "$c")"
done
for c in "sh -c \\\"git commit -m 'remove -n'\\\"" "bash -c 'git commit -m \\\"drop -n\\\"'" "eval 'git commit -m \\\"use -n\\\"'" \
  'git commit -m \"a; b\" && git log -n 3' "cp -t /tmp ~/.gitconfig" "cp ~/.gitconfig /tmp/.gitconfig" \
  "git commit -m \\\"\$(cat <<'EOF'\\nIt's about -n\\nEOF\\n)\\\""; do
  checkd "通す: $(printf '%s' "$c" | tr '\\' ' ')" allow "$(guardb "$c")"
done
# 迂回にならない形は通す: --no-verbose、小文字の git_config、環境変数を読むだけ、メッセージの中の -n、commit-tree・hooksPath を探すだけ
for c in "git add -A && git commit -m x" "git log --oneline -n 5" "git status" "git commit --no-verbose -m x" "grep -n git_config file" \
  "grep -n GIT_CONFIG bin/harness-hook" 'echo $CLAUDECODE' "printenv CLAUDECODE" \
  'git commit -m \"remove -n option\"' "git commit -m 'handle -inf values'" 'git commit --message=\"use -n\"' 'git commit -am \"drop -n\"' \
  "git log --grep=commit-tree" "grep -rn hooksPath file" "grep -n core.hooksPath README.md" \
  "cat ~/.config/git/config" "grep -n hooksPath ~/.gitconfig" "sed -n 1,5p .git/config" "cat ~/.gitconfig > /tmp/copy" \
  "cp ~/.gitconfig /tmp/backup" "cp ~/.gitconfig ~/.gitconfig.bak" "grep -rn hooksPath . 2>/dev/null" "(cd /tmp && ls)" 'echo $(date)' \
  "git config --get core.hooksPath" "git config --global --get-all core.hooksPath" "git log src/commit.py -n 3" \
  'echo \"CLAUDECODE=$CLAUDECODE\"' "aws s3 ls --no-verify-ssl"; do
  checkd "通す: $(printf '%s' "$c" | tr '\\' ' ')" allow "$(guardb "$c")"
done
expect "拒否の理由に、一致した語を含める" [ -n "$(guardb "git commit --no-verify" | grep -- "--no-v")" ]

# ---- 作業別ブランチの強制 ----
checkd "作業ブランチ上の編集は許可する" allow "$(guarde "$REPO/src/app.py")"
checkd "git リポジトリ外の編集は許可する" allow "$(guarde "$TMP/note.md")"
U="$TMP/unborn"; git init -q -b main "$U"
checkd "git init 直後（最初のコミット前）は main でも編集できる" allow "$(guarde "$U/app.py")"
CWD="$U"; turn; reqs; echo c > "$U/app.py"; echo 'uv run pytest -q' > "$U/.harness-verify"; bash_ "uv run pytest -q"; accept; review reviewer; git -C "$U" add -A
checkx "最初のコミットは main に置ける（証拠がそろっていれば）" 0 sh -c "cd '$U' && '$HOOK' pre-commit"
check "最初のコミット前の main では、Stop も『ブランチを切れ』と差し戻さない" pass "$(stop)"
CWD=""
ln -s "$REPO/src/lib.py" "$TMP/outside-link.py"
fresh; $G switch -q main
checkd "main 上の編集は拒否する（まだ無いディレクトリへの新規ファイルでも）" deny "$(guarde "$REPO/src/new/app.py")"
checkd "リポジトリ外のシンボリックリンク経由でも、実体が main 上なら拒否する" deny "$(guarde "$TMP/outside-link.py")"
checkd "NotebookEdit（notebook_path）も同じく拒否する" deny "$(printf '{%s,"hook_event_name":"PreToolUse","tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s"}}' "$(common)" "$REPO/nb.ipynb" | "$HOOK" guard-branch)"
# main の上には requirements-save では保存できないので、証拠がそろった状態を作るために写しを直接置く
turn; P="$(cd "$REPO" && "$HOOK" requirements-path)"; printf 'AC1: x\n' > "$P"; $G rev-parse HEAD > "$P.head"
write src/app.py m; write tests/test_app.py m; bash_ "uv run pytest -q"; accept; review reviewer; $G add -A
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
expect "settings.json の SubagentStop は、reviewer と acceptor の終了で review-done を呼ぶ" grep -q '"matcher": "reviewer|acceptor".*harness-hook review-done' "$DOTFILES/config/claude/settings.json"
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
