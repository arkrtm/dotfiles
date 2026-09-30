#!/bin/sh
# 受け入れ検査（ARK-49）: superpowers との差を埋めた機能（skill・agent・CLAUDE.md・README・hook・tests/skills.sh）が要件どおりか。
# 文書は要となる語で確かめる（言い回しの変更で壊れないように）。hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで、
# 実物と同じ形の hook 入力を渡して観測する。tests/skills.sh は写しを 1 か所ずつ壊して落ちることを確かめる。
# AC9（Linear の記録）と AC17（claude -p を使う E2E。課金がある）はここでは確かめない。失敗が 1 つでもあれば exit 1
#   sh tests/acceptance/harness-parity.sh
set -eu
D="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$D/bin/harness-hook"
UV="$HOME/.local/libexec/uv"; [ -x "$UV" ] || UV="$(mise which uv 2>/dev/null || true)"
[ -x "$UV" ] || { echo "FAIL uv の実体が見つからない"; exit 1; }
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" CLAUDECODE=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM 2>/dev/null || true
mkdir -p "$HOME/.local/libexec" "$HOME/.local/bin"
ln -s "$UV" "$HOME/.local/libexec/uv"; ln -s "$HOOK" "$HOME/.local/bin/harness-hook"

fail=0
ng() { echo "FAIL $1"; fail=1; }
has() { grep -Eq -- "$2" "$D/$1" || ng "$1 に「$2」が無い"; }   # has <file> <grep の拡張正規表現>
all() { f="$1"; shift  # all <file> <語>...: すべての語を含む行がある
  awk -v ws="$*" 'BEGIN { n = split(ws, w, " ") } { ok = 1; for (i = 1; i <= n; i++) if (!index($0, w[i])) ok = 0; if (ok) { hit = 1; exit } } END { exit !hit }' "$D/$f" \
    || ng "$f に「$*」をすべて含む行が無い"; }
C=config/claude; S=$C/skills

# ---------- 文書（AC1〜6, 8, 12, 14〜16）----------
# AC1: /design
has $S/design/SKILL.md '^name: design$'
for w in Explore AskUserQuestion '2〜3 案' 推奨 構成 データの流れ インタフェース エラー テスト 対象外 承認 本文; do has $S/design/SKILL.md "$w"; done
all $S/design/SKILL.md issue 本文 設計
# AC2: /tdd と reviewer・implementer の RED の理由
has $S/tdd/SKILL.md '^name: tdd$'
all $S/tdd/SKILL.md 期待した理由 assert
all $S/tdd/SKILL.md import RED
has $S/tdd/SKILL.md '避けるべき書き方'
all $S/tdd/SKILL.md 設計の問題
all $S/tdd/SKILL.md バグ 再現するテスト
for f in $C/agents/reviewer.md $C/agents/implementer.md; do all $f RED import; all $f RED assert; done
# AC3: 着手時の検証一式と、統合後の片付け
all $C/CLAUDE.md 着手時 検証一式 元から落ちている
all $C/CLAUDE.md マージ main 検証一式 ブランチを消す
all $C/CLAUDE.md worktree remove
# AC4: /implement の計画
all $S/implement/SKILL.md 全体の制約
all $S/implement/SKILL.md レビューの焦点 壊れやすい テスト
# AC5: /diagnose の多層の防御
all $S/diagnose/SKILL.md 根本原因 境界 検証
# AC6: Linear が使えない環境
all $C/CLAUDE.md Linear 使えない docs/tasks/
# AC8: README の対応表と全体図
has README.md 'superpowers との対応'
has README.md '流れの全体図'
for s in brainstorming writing-plans executing-plans subagent-driven-development dispatching-parallel-agents test-driven-development \
  testing-anti-patterns systematic-debugging verification-before-completion requesting-code-review receiving-code-review \
  using-git-worktrees finishing-a-development-branch writing-skills using-superpowers; do
  grep -q "^| .*$s" "$D/README.md" || ng "AC8: README の対応表に $s の行が無い"
done
# 対応表に「強い方」の列があり、各行のその列が判定の語（自作／同等／superpowers／自作だけ／superpowers だけ）のどれか
tbl="$(awk '/^### superpowers との対応/ { f = 1; next } f && /^#/ { exit } f && /^\|/' "$D/README.md")"
col="$(printf '%s\n' "$tbl" | head -1 | awk -F'|' '{ for (i = 2; i < NF; i++) { g = $i; gsub(/^ +| +$/, "", g); if (g ~ /強い/) { print i; exit } } }')"
if [ -z "$col" ]; then ng "AC8: README の対応表の見出しに、どちらが強いかの列が無い"
else
  rows="$(printf '%s\n' "$tbl" | awk -F'|' 'NR > 2' | wc -l | tr -d ' ')"
  [ "$rows" -ge 15 ] || ng "AC8: README の対応表の行が少ない（$rows 行）"
  bad="$(printf '%s\n' "$tbl" | awk -F'|' -v c="$col" 'NR > 2 { g = $c; gsub(/^ +| +$/, "", g); if (g !~ /^(自作|同等|superpowers|自作だけ|superpowers だけ)$/) print "  [" g "] " $0 }')"
  [ -z "$bad" ] || ng "AC8: README の対応表で、どちらが強いかの列が判定の語でない行がある:
$bad"
fi
all README.md 凡例 自作 同等 superpowers 自作だけ
# AC12（文書）: acceptor・reviewer は写しから読む。/issue に写しを書く手順
for f in $C/agents/acceptor.md $C/agents/reviewer.md $S/accept/SKILL.md $S/review/SKILL.md; do all $f requirements-path 依頼の文面; done
has $S/issue/SKILL.md 'requirements-save'
# AC11（文書）: reviewer は RED の記録で確かめる
for f in $C/agents/reviewer.md $S/review/SKILL.md; do has $f 'harness-red-log'; done
# AC14: CLAUDE.md
all $C/CLAUDE.md 重大 /accept /verify '/review fix'
all $C/CLAUDE.md 迷ったら重い方
all $C/CLAUDE.md 格上げ 下げない
all $C/CLAUDE.md S 解釈が複数 聞く
all $C/CLAUDE.md 破棄 明示の依頼
all $C/CLAUDE.md worktree --force 使わない
all $C/CLAUDE.md /code-review 実装の直後
all $C/CLAUDE.md 人 PR /code-review 指摘 同じ
# AC15: /implement
all $S/implement/SKILL.md 進捗 本文 チェックリスト
all $S/implement/SKILL.md 後の波 インタフェース /review
all $S/implement/SKILL.md 受け入れ条件 タスク
has $S/implement/SKILL.md 'RED で期待する失敗'
# AC16: description は「いつ使うか」、言い訳の表、/diagnose の追加、reviewer の「判断しなかったこと」
for f in "$D"/$S/*/SKILL.md; do
  d="$(sed -n 's/^description: *//p' "$f" | head -1)"
  case "$d" in *使う*) ;; *) ng "AC16: ${f#"$D"/} の description に「いつ使うか」が無い: $d" ;; esac
done
for f in $S/verify/SKILL.md $S/tdd/SKILL.md; do has $f '^\| *言い訳 *\|'; done
all $S/diagnose/SKILL.md 汚染 半分
all $S/diagnose/SKILL.md sleep 条件
all $S/diagnose/SKILL.md 原因 コードの外
has $C/agents/reviewer.md '^## 判断しなかったこと'

# ---------- AC7: tests/skills.sh ----------
sh "$D/tests/skills.sh" >/dev/null 2>&1 || ng "AC7: tests/skills.sh が本物のリポジトリで落ちる"
grep -qx 'sh tests/skills.sh' "$D/.harness-verify" || ng "AC7: .harness-verify に sh tests/skills.sh が無い"
T="$TMP/copy"
copy() { rm -rf "$T"; mkdir -p "$T/config/claude" "$T/bin"
  cp -R "$D/$C/skills" "$D/$C/agents" "$D/$C/CLAUDE.md" "$D/$C/settings.json" "$T/$C/"; cp "$D/install.sh" "$T/"; cp "$D/bin/harness-hook" "$T/bin/"; }
edit() { sed "$2" "$T/$1" > "$TMP/e"; cp "$TMP/e" "$T/$1"; cmp -s "$TMP/e" "$D/$1" && ng "AC7（前提）: $1 を壊せていない（$2）"; return 0; }
breaks() { # breaks <説明>: 壊した写しで skills.sh が落ちる
  if out="$(sh "$D/tests/skills.sh" "$T" 2>&1)"; then ng "AC7: 壊しても skills.sh が通った: $1"; fi; }
copy; sh "$D/tests/skills.sh" "$T" >/dev/null 2>&1 || ng "AC7（前提）: 壊す前の写しで skills.sh が落ちる"
copy; edit $S/design/SKILL.md 's/^name: design$/name: designs/'; breaks 'skill の name がディレクトリ名と違う'
copy; edit $S/tdd/SKILL.md 's/^description:.*/description:/'; breaks 'skill の description が空'
copy; edit $S/accept/SKILL.md 's/^agent: acceptor$/agent: acceptr/'; breaks 'skill の agent: が agents に無い'
copy; edit $C/CLAUDE.md 's|`/diagnose`|`/diagnoze`|'; breaks 'CLAUDE.md の `/diagnose` を存在しない名前に'
copy; edit $S/implement/SKILL.md 's|`/tdd`|`/tddd`|'; breaks 'skill の本文の `/tdd` を存在しない名前に'
copy; edit $S/verify/SKILL.md '/^description:/s|/review|/reveiw|'; breaks 'skill の description（バッククォートの外）の /review を存在しない名前に'
copy; edit $S/accept/SKILL.md '/^description:/s|/verify|/verfy|'; breaks 'accept の description（バッククォートの外）の /verify を存在しない名前に'
copy; edit $C/agents/reviewer.md 's|^範囲限定の再レビュー（/review fix）|範囲限定の再レビュー（/reviw fix）|'; breaks 'reviewer.md の本文（バッククォートの外、全角括弧の直後）の /review を存在しない名前に'
copy; edit $C/agents/reviewer.md 's|、/review fix は起点|、/revieww fix は起点|'; breaks 'reviewer.md の本文（読点の直後）の /review を存在しない名前に'
copy; edit $C/CLAUDE.md '1s|$| /nosuchcmd を使う|'; breaks 'CLAUDE.md の行末に空白区切りの存在しない /nosuchcmd'
copy; edit install.sh '/^config\/claude\/skills\/tdd /d'; breaks 'install.sh の LINKS から skills/tdd を消す'
copy; edit install.sh '/^config\/claude\/agents\/implementer.md /d'; breaks 'install.sh の LINKS から agents/implementer.md を消す'
copy; edit $C/settings.json 's/"matcher": "reviewer|acceptor"/"matcher": "reviewer"/'; breaks 'SubagentStop の matcher から acceptor を消す'
copy; edit $C/settings.json 's/"matcher": "reviewer|acceptor"/"matcher": "acceptor"/'; breaks 'SubagentStop の matcher から reviewer を消す'

# ---------- hook の準備 ----------
SID="par-$$"; R=""
common() { printf '"session_id":"%s","cwd":"%s","transcript_path":"/dev/null"' "$SID" "$R"; }
turn() { printf '{%s,"hook_event_name":"UserPromptSubmit","prompt":"x"}' "$(common)" | "$HOOK" turn; }
run_ok() { # run_ok <command> [入力への追加 JSON]: Bash の成功
  printf '{%s%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}' "$(common)" "${2:-}" "$1" | "$HOOK" bash; }
run_ng() { # run_ng <command> <error> [入力への追加 JSON]: Bash の失敗
  printf '{%s%s,"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"%s"},"error":"%s","is_interrupt":false}' "$(common)" "${3:-}" "$1" "$2" | "$HOOK" bash-failed; }
sub() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s","last_assistant_message":"%s"}' "$(common)" "$1" "$2" | "$HOOK" review-done; }
REV='## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
ACC='## 条件ごとの結果\n- [AC1] 合格 — a → b\n## 判定\n受け入れ: 合格'
acc() { sub acceptor "$ACC"; }; rev() { sub reviewer "$REV"; }
stop() { printf '{%s,"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"done"}' "$(common)" | "$HOOK" stop; }
blocked() { case "$(stop)" in *'"decision": "block"'*) return 0 ;; *) return 1 ;; esac; }
commit_ok() { (cd "$R" && "$HOOK" pre-commit) >/dev/null 2>&1; }
newrepo() { # newrepo <名前> [.harness-verify の中身]: main に初期コミット、feat/x に切り替え、cwd にする
  R="$TMP/$1"; mkdir -p "$R/tests"; git init -q -b main "$R"; echo base > "$R/tests/test_a.py"
  [ -z "${2:-}" ] || printf '%b\n' "$2" > "$R/.harness-verify"
  git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m init; git -C "$R" switch -q -c feat/x; turn; }
k=0
change() { k=$((k + 1)); turn; echo "c$k" > "$R/app.py"; echo "c$k" > "$R/tests/test_app.py"; git -C "$R" add -A; }
save() { printf '%s\n' "${1:-要件と受け入れ条件}" | (cd "$R" && "$HOOK" requirements-save) >/dev/null; }

# ---------- AC12: 要件の写し ----------
newrepo req 'uv run pytest -q'
P="$(cd "$R" && "$HOOK" requirements-path)"
case "$P" in "$(cd "$R" && pwd -P)/.git/"*feat_x*) ;; *) ng "AC12: requirements-path が git dir の下のブランチごとの場所でない: $P" ;; esac
git -C "$R" switch -q -c feat/y; P2="$(cd "$R" && "$HOOK" requirements-path)"; git -C "$R" switch -q feat/x
[ "$P" != "$P2" ] || ng "AC12: ブランチが違っても requirements-path が同じ: $P2"
out="$(printf '要件 A\n- AC1 x\n' | (cd "$R" && "$HOOK" requirements-save))"
[ "$out" = "$P" ] && [ "$(cat "$P")" = "$(printf '要件 A\n- AC1 x')" ] || ng "AC12: requirements-save が標準入力をそのまま写しに保存しない（出力 $out）"
rm -f "$P"
# 写しが無い → 検証・受け入れ・レビューがそろっても Stop は差し戻し、pre-commit は拒否。理由に保存のしかた
change; run_ok 'uv run pytest -q'; acc; rev
r="$(stop)"; case "$r" in *'"decision": "block"'*requirements-save*) ;; *) ng "AC12: 写しが無いのに Stop が requirements-save を理由に差し戻さない: $r" ;; esac
commit_ok && ng "AC12: 写しが無いのに pre-commit が通した"
# 写しを保存すれば、証拠を取り直すと通る
save; run_ok 'uv run pytest -q'; acc; rev
blocked && ng "AC12: 写しを保存して証拠をそろえても Stop が差し戻す"
commit_ok || ng "AC12: 写しを保存して証拠をそろえても pre-commit が拒否"
# 写しを書き換えると、検証・受け入れ・レビューはどれも無効（1 つでも取り直さなければ通らない）
for skip in verify accept review; do
  save "要件 v-$skip"
  [ $skip = verify ] || run_ok 'uv run pytest -q'; [ $skip = accept ] || acc; [ $skip = review ] || rev
  commit_ok && ng "AC12: 写しを書き換えた後、$skip を取り直さずに pre-commit が通した"
  blocked || ng "AC12: 写しを書き換えた後、$skip を取り直さずに Stop が通した"
done
save "要件 v-all"; run_ok 'uv run pytest -q'; acc; rev
commit_ok || ng "AC12: 書き換えた写しで 3 つとも取り直しても pre-commit が拒否"

# ---------- AC10: 検証コマンドの宣言 ----------
# 宣言が無い → 何を成功させても証拠にならず、理由に宣言の場所（.harness-verify と <git-common-dir>/harness-verify）
newrepo nodecl; save; change; run_ok 'uv run pytest -q'; acc; rev
r="$(stop)"; GC="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
case "$r" in *'"decision": "block"'*.harness-verify*"$GC/harness-verify"*) ;; *) ng "AC10: 宣言が無いのに Stop が宣言の場所を理由に差し戻さない: $r" ;; esac
msg="$(cd "$R" && "$HOOK" pre-commit 2>&1 || true)"; commit_ok && ng "AC10: 宣言が無いのに pre-commit が通した"
case "$msg" in *.harness-verify*"$GC/harness-verify"*) ;; *) ng "AC10: pre-commit の拒否理由に宣言の場所が無い: $msg" ;; esac
# <git-common-dir>/harness-verify の宣言でも通る
echo 'uv run pytest -q' > "$GC/harness-verify"; run_ok 'uv run pytest -q'
commit_ok || ng "AC10: <git-common-dir>/harness-verify の宣言どおりに成功させても pre-commit が拒否"
# 宣言が 2 行（テストと lint）: すべてが同じ内容で成功したときだけ証拠
newrepo decl 'uv run pytest -q\nuv run ruff check .'; save
only() { # only <説明> <command>...: 与えたコマンドだけを成功させても証拠にならない
  d="$1"; shift; change; acc; rev; for c in "$@"; do run_ok "$c"; done
  commit_ok && ng "AC10: $d だけで pre-commit が通した"; blocked || ng "AC10: $d だけで Stop が通した"; }
only 'lint（宣言の 1 行）' 'uv run ruff check .'
only 'テスト（宣言の 1 行）' 'uv run pytest -q'
only '宣言に無いコマンド' 'pytest -q' 'ruff check .'
only '絞った実行（-k）+ lint' 'uv run pytest -q -k app' 'uv run ruff check .'
only '絞った実行（ファイル指定）+ lint' 'uv run pytest -q tests/test_app.py' 'uv run ruff check .'
only 'パイプ付き + lint' 'uv run pytest -q | tail -3' 'uv run ruff check .'
change; acc; rev; run_ok 'uv run pytest -q' ',"agent_id":"a1","agent_type":"implementer"'; run_ok 'uv run ruff check .' ',"agent_id":"a1","agent_type":"implementer"'
commit_ok && ng "AC10: サブエージェント内の成功だけで pre-commit が通した"
change; acc; rev; run_ok 'uv run pytest -q'; run_ok 'uv run ruff check .'
commit_ok || ng "AC10: 宣言した 2 行をどちらも成功させても pre-commit が拒否"
blocked && ng "AC10: 宣言した 2 行をどちらも成功させても Stop が差し戻す"

# ---------- AC11: 失敗したテストの記録（harness-red-log）----------
RED="$(cd "$R" && git rev-parse --absolute-git-dir)/harness-red-log"
change; run_ng 'uv run pytest -q' 'Exit code 1\nE   AssertionError: expected 3, got 0'
grep -q 'uv run pytest -q' "$RED" 2>/dev/null && grep -q 'AssertionError: expected 3, got 0' "$RED" || ng "AC11: 失敗したテストのコマンドと出力が $RED に無い"
run_ng 'uv run pytest -q' 'E   AssertionError: from-subagent' ',"agent_id":"a2","agent_type":"implementer"'
grep -q 'from-subagent' "$RED" || ng "AC11: サブエージェント内の失敗が記録されない"
long="$(i=1; while [ $i -le 200 ]; do printf 'LINE%03d\\n' $i; i=$((i + 1)); done)"
run_ng 'uv run pytest -q' "$long"
grep -q 'LINE001' "$RED" || ng "AC11: 長い出力の先頭が記録されない"
grep -q 'LINE200' "$RED" && ng "AC11: 200 行の出力が切り詰められずに全部記録された"

# ---------- AC13: 迂回語の誤検知 ----------
guard() { printf '{%s,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(common)" "$1" | "$HOOK" guard-bash; }
for c in 'git commit --no-verbose -m x' 'grep -n git_config file' 'echo $CLAUDECODE'; do
  case "$(guard "$c")" in *'"permissionDecision": "deny"'*) ng "AC13: 通すべきものを拒否した: $c" ;; esac
done
for c in 'git commit --no-verify -m x' 'git commit -n -m x' 'git -c core.hooksPath=/dev/null commit -m x' 'GIT_CONFIG_GLOBAL=/dev/null git commit -m x' \
  'unset CLAUDECODE && git commit -m x' 'env -u CLAUDECODE git commit -m x' 'git commit-tree abc'; do
  case "$(guard "$c")" in *'"permissionDecision": "deny"'*) ;; *) ng "AC13: 拒否すべきものを通した: $c" ;; esac
done

# ---------- AC17（一部）: tests/e2e-flow.sh の「宣言した検証」の項目 ----------
# claude -p（課金あり）は動かさない。e2e-flow.sh の検査部分（passed=0 から最後まで）だけを、作った記録に対して流し、
# 宣言した検証の項目が、メインの会話で単独に実行したときだけ ok になることを見る（ほかの項目は作った記録では落ちてよい）
E2E="$TMP/e2e-check.sh"
{ echo 'set -u; W="$1"; R="$W/repo"; BASE=$(git -C "$R" rev-list --max-parents=0 HEAD)'; sed -n '/^passed=0; fail=0$/,$p' "$D/tests/e2e-flow.sh"; } > "$E2E"
grep -q '宣言した検証' "$E2E" || ng "AC17: tests/e2e-flow.sh の検査部分に、宣言した検証の項目が無い"
DECL='python3 -m unittest discover -s tests -t . -q'
e2e_decl() { # e2e_decl <名前> <Bash の command> [parent_tool_use_id]: 作った記録で、宣言した検証の項目の行を出す
  W="$TMP/e2e-$1"; mkdir -p "$W/repo"; git init -q -b main "$W/repo"; echo "$DECL" > "$W/repo/.harness-verify"
  git -C "$W/repo" add -A; git -C "$W/repo" -c user.name=t -c user.email=t@t commit -q -m init
  python3 -c 'import json, sys; print(json.dumps({"type": "assistant", "parent_tool_use_id": sys.argv[2] or None, "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": sys.argv[1]}}]}}))' "$2" "${3:-}" > "$W/stream.jsonl"
  sh "$E2E" "$W" 2>/dev/null | grep '宣言した検証'; }
case "$(e2e_decl main "$DECL")" in 'ok '*) ;; *) ng "AC17: メインの会話で宣言どおりに実行した記録で、宣言した検証の項目が ok にならない" ;; esac
case "$(e2e_decl cd "cd /x/repo && $DECL")" in 'ok '*) ;; *) ng "AC17: cd を前置した実行で、宣言した検証の項目が ok にならない" ;; esac
case "$(e2e_decl sub "$DECL" toolu_x)" in 'FAIL '*) ;; *) ng "AC17: サブエージェントだけが実行した記録で、宣言した検証の項目が FAIL にならない" ;; esac
case "$(e2e_decl pipe "$DECL 2>&1 | tail -3")" in 'FAIL '*) ;; *) ng "AC17: パイプ付きの実行で、宣言した検証の項目が FAIL にならない" ;; esac
case "$(e2e_decl narrow 'python3 -m unittest tests.test_words -q')" in 'FAIL '*) ;; *) ng "AC17: 宣言と違う（絞った）実行で、宣言した検証の項目が FAIL にならない" ;; esac
case "$(e2e_decl chain "cd /x; $DECL; echo exit=\$?")" in 'FAIL '*) ;; *) ng "AC17: ; でつないだ実行で、宣言した検証の項目が FAIL にならない" ;; esac

[ "$fail" = 0 ] && echo "harness-parity: ok"
exit "$fail"
