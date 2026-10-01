#!/bin/sh
# 受け入れ検査（ARK-51 の 3 回目の修正。AC25〜AC33・AC35・AC36。AC34 の E2E は claude -p を使うので手動の tests/e2e-flow.sh）。
# hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで、実物と同じ形の hook 入力を渡して観測する。
# コミット・rebase・cherry-pick・pull は実際の git（共通 hooks = config/git/hooks を GIT_CONFIG_GLOBAL で設定）で行う。
# AC32 は 235e128 の hook（git show で取り出す）と同じコマンドを渡して比べる。
# 文書は言い回しの変更で壊れないよう、要となる語で確かめる。失敗が 1 つでもあれば exit 1
#   sh tests/acceptance/harness-ark51-r3.sh
set -eu
D="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$D/bin/harness-hook"
UV="$HOME/.local/libexec/uv"; [ -x "$UV" ] || UV="$(mise which uv 2>/dev/null || true)"
[ -x "$UV" ] || { echo "FAIL uv の実体が見つからない"; exit 1; }
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" CLAUDECODE=1 TMPDIR="$TMP/tmpdir"
unset XDG_CONFIG_HOME GIT_CONFIG_SYSTEM 2>/dev/null || true
mkdir -p "$HOME/.local/libexec" "$HOME/.local/bin" "$TMPDIR" "$TMP/r"
ln -s "$UV" "$HOME/.local/libexec/uv"; ln -s "$HOOK" "$HOME/.local/bin/harness-hook"
printf '[core]\n\thooksPath = %s\n[user]\n\tname = t\n\temail = t@t\n' "$D/config/git/hooks" > "$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"

fail=0
ng() { echo "FAIL $1"; fail=1; }
SID="a51r3-$$"
ev() { # ev <hook のサブコマンド> <cwd> <イベント名> [追加の JSON] — HOOK_BIN で hook を差し替えられる（AC32 の比較）
  python3 -c 'import json, sys
d = {"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": "/dev/null", "hook_event_name": sys.argv[3]}
d.update(json.loads(sys.argv[4]) if len(sys.argv) > 4 else {})
print(json.dumps(d))' "$SID" "$2" "$3" "${4:-}" | "${HOOK_BIN:-$HOOK}" "$1"; }
js() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
turn() { ev turn "$1" UserPromptSubmit '{"prompt": "x"}'; }
stop() { ev stop "$1" Stop '{"stop_hook_active": false, "last_assistant_message": "done"}'; }
ran() { ev bash "$1" PostToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}, \"tool_response\": {\"stdout\": \"\", \"stderr\": \"\", \"interrupted\": false}}"; }
ver() { (cd "$1" && sh "$D/config/claude/skills/review/snapshot.sh" 2>/dev/null) || true; }
accepted_v() { ev review-done "$1" SubagentStop "{\"agent_type\": \"acceptor\", \"last_assistant_message\": $(js "受け入れ検証した版: $2
## 条件ごとの結果
- [AC1] 合格 — a → b
## 判定
受け入れ: 合格")}"; }
reviewed_v() { ev review-done "$1" SubagentStop "{\"agent_type\": \"reviewer\", \"last_assistant_message\": $(js "レビューした版: $2
## 判定
仕様適合: 承認
テスト: 承認
品質・保守性: 承認")}"; }
evidence() { ran "$1" "sh tests/ok.sh"; accepted_v "$1" "$(ver "$1")"; reviewed_v "$1" "$(ver "$1")"; }
guard_at() { ev guard-bash "$1" PreToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}}"; }
is_block() { case "$1" in *'"decision": "block"'*) return 0 ;; *) return 1 ;; esac; }
is_deny() { case "$1" in *'"permissionDecision": "deny"'*) return 0 ;; *) return 1 ;; esac; }
save_req() { printf 'AC1: 要件\n' | (cd "$1" && "$HOOK" requirements-save) >/dev/null; }
newrepo() { # newrepo <名前>: 宣言した検証（sh tests/ok.sh）と最初のコミットを持つ feat/x のリポジトリ
  r="$TMP/r/$1"; mkdir -p "$r/tests" "$r/src"; git init -q -b main "$r"
  printf 'sh tests/ok.sh\n' > "$r/.harness-verify"; printf 'exit 0\n' > "$r/tests/ok.sh"; echo base > "$r/src/lib.py"
  git -C "$r" add -A; env -u CLAUDECODE git -C "$r" commit -q -m init; git -C "$r" switch -q -c feat/x; echo "$r"; }
commits() { _r=$1; shift; git -C "$_r" commit -q "$@" >/dev/null 2>&1; }      # 共通 hooks（関門）を通るコミット
commit_err() { _r=$1; shift; git -C "$_r" commit -q "$@" 2>&1 >/dev/null || true; } # 止まったときの理由（stderr）
human() { _r=$1; shift; env -u CLAUDECODE git -C "$_r" "$@"; }                  # 人の操作（関門の対象外）
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
reset_tree() { git -C "$1" reset -q --hard; git -C "$1" clean -qfd; }

# ---------- AC25: 新規追加に証拠が要らないのはテストだけ ----------
R="$(newrepo tests)"; save_req "$R"
for f in src/components/SpeedTest.tsx api/spec/openapi.yaml src/test/server.go src/test_utils.go lib/spec/helper.rb src/__tests__/helper.js \
  tests_old/x.py src/foo.test.json; do
  turn "$R"; mkdir -p "$R/$(dirname "$f")"; echo x > "$R/$f"; git -C "$R" add -A
  is_block "$(stop "$R")" || ng "AC25: 証拠なしの $f の追加を Stop が差し戻さない"
  commits "$R" -m "$f" && ng "AC25: 証拠なしの $f の追加をコミットできた"
  reset_tree "$R"
done
for f in tests/test_x.py src/foo.test.ts src/test/java/FooTest.java spec/a_spec.rb tests/fixtures/x.json \
  test/x.go __tests__/a.js src/foo_test.go src/FooTests.swift src/FooTest.cs src/a_spec.rb src/foo.spec.ts; do
  turn "$R"; mkdir -p "$R/$(dirname "$f")"; echo x > "$R/$f"; git -C "$R" add -A
  is_block "$(stop "$R")" && ng "AC25: テストの $f の追加だけで Stop が差し戻した"
  commits "$R" -m "$f" || { ng "AC25: テストの $f の追加だけのコミットが止まった"; reset_tree "$R"; }
done

# ---------- AC26: 受け入れ条件を減らす版は承認の節が無ければ保存しない。版は .history に残る ----------
R="$(newrepo req)"
rsave() { printf '%b' "$1" | (cd "$R" && "$HOOK" requirements-save) 2>&1; }
P="$(cd "$R" && "$HOOK" requirements-path)"
rsave 'AC1: a\nAC2: b\n' >/dev/null || ng "AC26（前提）: 最初の版を保存できない"
if out="$(rsave 'AC1: a\nAC3: c\n')"; then ng "AC26: AC2 が消えた版を承認の節なしで保存した"; else
  has "$out" "変更の承認" || ng "AC26: 保存しなかった理由に「## 変更の承認」の節を書くことが無い: $out"
  has "$out" "承認" || ng "AC26: 保存しなかった理由に承認を得ることが無い: $out"
fi
grep -q 'AC2: b' "$P" || ng "AC26: 保存しなかったのに写しが書き換わった"
rsave 'AC1: a\nAC2: b2\nAC3: c\n' >/dev/null || ng "AC26: 条件を足す（減らさない）版を保存しなかった"
rsave 'AC1: a\nAC3: c\n## 変更の承認\n> ユーザー: AC2 は要らない\n' >/dev/null || ng "AC26: 承認の節がある、減らす版を保存しなかった"
n="$(ls "$P.history" 2>/dev/null | wc -l | tr -d ' ')"
[ "$n" = 3 ] || ng "AC26: .history に保存した 3 版が残っていない（$n 件）"
grep -q 'AC2: b$' "$P.history/$(ls "$P.history" | head -1)" || ng "AC26: .history の最初の版が最初に保存した内容でない"
rv="$D/config/claude/agents/reviewer.md"
grep -q '\.history' "$rv" && grep -q '変更の承認' "$rv" && grep '\.history' "$rv" | grep -q '修正が必要' \
  || ng "AC26: reviewer.md に、.history の最初の版と比べ承認が無ければ「修正が必要」にすることが無い"

# ---------- AC27: 写しの前からある追跡済みファイルの未ステージの変更（WIP）は証拠の対象から外す ----------
R="$(newrepo wip)"
echo wip > "$R/src/lib.py"; echo note > "$R/scratch.py"           # 利用者の WIP（追跡済みの変更と未追跡）
turn "$R"; save_req "$R"
echo task > "$R/src/app.py"; evidence "$R"; git -C "$R" add src/app.py
commits "$R" -m task || ng "AC27: WIP を残したタスクのファイルだけの部分コミットが止まった"
[ "$(git -C "$R" show HEAD:src/lib.py)" = base ] || ng "AC27: WIP がコミットに入った"
[ "$(git -C "$R" status --porcelain)" = "$(printf ' M src/lib.py\n?? scratch.py')" ] || ng "AC27: WIP が未ステージのまま残っていない: $(git -C "$R" status --porcelain)"
is_block "$(stop "$R")" && ng "AC27: WIP を残したターンを Stop が差し戻した"
# 同じ依頼の続き（コミットの後なので写しを保存し直す。WIP の基準は最初の保存のまま）
turn "$R"; save_req "$R"; echo task2 > "$R/src/app.py"; evidence "$R"; git -C "$R" add src/app.py src/lib.py
err="$(commit_err "$R" -m with-wip)"
[ -n "$err" ] || ng "AC27: ステージした WIP（追跡済みの変更）が証拠なしでコミットできた"
has "$err" "src/lib.py" || ng "AC27: ステージした WIP で止めた理由に src/lib.py が無い: $err"
git -C "$R" restore --staged src/lib.py
commits "$R" -m task2 || ng "AC27: 写しを保存し直した後、WIP のステージを外したコミットが止まった: $(commit_err "$R" -m task2)"
# WIP を変えたら対象に戻る（Stop が証拠を求める）。元の内容に戻せば再び外れる
turn "$R"; save_req "$R"; echo wip-changed > "$R/src/lib.py"
is_block "$(stop "$R")" || ng "AC27: WIP のファイルを変えたのに、Stop が証拠を求めない"
echo wip > "$R/src/lib.py"
is_block "$(stop "$R")" && ng "AC27: WIP を元の内容に戻したのに、Stop が差し戻した"

# ---------- AC28: rebase・pull --rebase・cherry-pick で付け替えた、関門を通ったコミット ----------
R="$(newrepo rb)"; save_req "$R"
B="$TMP/r/rb.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"; human "$R" push -q origin main
turn "$R"; echo rb1 > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
commits "$R" -m gated || ng "AC28（前提）: 証拠のそろったコミットが止まった"
human "$R" switch -q main; echo other > "$R/src/other.py"; git -C "$R" add -A; human "$R" commit -q -m "main moves"; human "$R" push -q origin main; human "$R" switch -q feat/x
turn "$R"; old="$(git -C "$R" rev-parse HEAD)"; git -C "$R" rebase -q main >/dev/null 2>&1 || ng "AC28（前提）: rebase が失敗した"
[ "$(git -C "$R" rev-parse HEAD)" != "$old" ] || ng "AC28（前提）: rebase でコミットが付け替わっていない"
is_block "$(stop "$R")" && ng "AC28: rebase で付け替えた、関門を通ったコミットを Stop が差し戻した"
is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC28: rebase で付け替えたコミットの push を拒否した"
# pull --rebase（別の人がリモートの main を進めた。ターンの前に進めた場合と、ターンの途中で進めた場合）
C="$TMP/r/rb-clone"; human "$R" clone -q -b main "$B" "$C"
pushed_by_other() { echo "$1" > "$C/src/$1.py"; git -C "$C" add -A; human "$C" commit -q -m "$1"; human "$C" push -q origin main; }
for when in before during; do
  if [ "$when" = before ]; then pushed_by_other other1; sleep 1; turn "$R"; else turn "$R"; sleep 1; pushed_by_other other2; fi
  git -C "$R" pull -q --rebase origin main >/dev/null 2>&1 || ng "AC28（前提・$when）: pull --rebase が失敗した"
  git -C "$R" merge-base --is-ancestor origin/main HEAD || ng "AC28（前提・$when）: pull --rebase でリモートの変更が入っていない"
  out="$(stop "$R")"
  is_block "$out" && ng "AC28: pull --rebase（他人のコミットをターンの$( [ $when = before ] && echo 前 || echo 途中 )に push）の後に Stop が差し戻した: $out"
  is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC28: pull --rebase（$when）で付け替えたコミットの push を拒否した"
done
# cherry-pick
human "$R" switch -q -c cp main; turn "$R"; git -C "$R" cherry-pick feat/x >/dev/null 2>&1 || ng "AC28（前提）: cherry-pick が失敗した"
is_block "$(stop "$R")" && ng "AC28: cherry-pick で付け替えたコミットを Stop が差し戻した"
# 付け替えの後に手を加えた（patch が違う）コミットは差し戻す。理由に reset --soft と既存の証拠のままのコミットし直し
turn "$R"; echo changed > "$R/src/app.py"; git -C "$R" add -A; human "$R" commit -q --amend --no-edit
out="$(stop "$R")"
is_block "$out" || ng "AC28: 付け替えの後に手を加えたコミット（patch が違う）を Stop が差し戻さない"
has "$out" "reset --soft" || ng "AC28: 差し戻しの理由に reset --soft が無い: $out"
has "$out" "既存の証拠" || ng "AC28: 差し戻しの理由に、内容が証拠と同じなら既存の証拠のままコミットし直せることが無い: $out"
# 付け替えの免除（他人のコミットを fetch で除く）が、このターンの自分の関門を通っていないコミットまで除かない
# （push の後に fetch し直す・自分のコミットをリモート追跡ブランチに置く形。235e128 の hook はどれも差し戻していた）
# 自分のコミットを作った・付け替えた記録が、別の worktree・URL からの pull --rebase（記録の文に ':' を含む）にある形も同じ
other_main() { human . clone -q -b main "$B" "$TMP/r/rf-c"; echo o > "$TMP/r/rf-c/src/o.py"; git -C "$TMP/r/rf-c" add -A
  human "$TMP/r/rf-c" commit -q -m other; human "$TMP/r/rf-c" push -q origin main; rm -rf "$TMP/r/rf-c"; }
for how in 'human . push -q "$B" feat/x; git fetch -q origin' 'human . push -q "$B" feat/x:refs/heads/tmp; git fetch -q origin' \
  'human . push -q origin feat/x; git branch -dr origin/feat/x; git fetch -q origin' \
  'git fetch -q . feat/x:refs/remotes/origin/z' 'git update-ref refs/remotes/origin/z HEAD' \
  'git worktree add -q "$TMP/r/rf-wt" -b w2 main && cd "$TMP/r/rf-wt" && echo w > src/w.py && git add -A && human . commit -q -m w && human . push -q "$B" w2 && git fetch -q origin' \
  'other_main; git pull -q --rebase "file://$B" main; human . push -q "$B" feat/x; git fetch -q origin'; do
  R="$(newrepo rf)"; save_req "$R"; B="$TMP/r/rf.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"; human "$R" push -q origin main
  turn "$R"; echo u > "$R/src/app.py"; git -C "$R" add -A; human "$R" commit -q -m ungated
  (cd "$R" && eval "$how") >/dev/null 2>&1 || ng "AC28（前提）: 失敗した: $how"
  is_block "$(stop "$R")" || ng "AC28: このターンの関門を通っていないコミットを、次の後に Stop が差し戻さない（見逃し）: $how"
  rm -rf "$R" "$B"
done
# 関門を通ったコミットを URL からの pull --rebase で付け替え、他人のコミットが FETCH_HEAD にだけ入る形（差し戻さない）
R="$(newrepo rfu)"; save_req "$R"; B="$TMP/r/rf.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"; human "$R" push -q origin main
turn "$R"; echo g > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A; commits "$R" -m gated || ng "AC28（前提）: 証拠のそろったコミットが止まった"
(cd "$R" && other_main) >/dev/null 2>&1; turn "$R"
git -C "$R" pull -q --rebase "file://$B" main >/dev/null 2>&1 || ng "AC28（前提）: URL からの pull --rebase が失敗した"
[ "$(git -C "$R" rev-list --count HEAD)" = 3 ] || ng "AC28（前提）: URL からの pull --rebase で他人のコミットが入っていない"
out="$(stop "$R")"; is_block "$out" && ng "AC28: 関門を通ったコミットを URL からの pull --rebase で付け替えた後に Stop が差し戻した: $out"
is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC28: URL からの pull --rebase で付け替えたコミットの push を拒否した"
rm -rf "$R" "$B"

# ---------- AC36: 変更なしの --amend で、関門を通っていないコミットを関門を通ったことにしない ----------
# 人の操作で関門を通らないコミット → エージェントが共通 hooks を通る --amend で付け直す（同じターン・次のターン）
for how in '--amend --no-edit' '--amend -m renamed'; do
  for when in same next; do
    R="$(newrepo am)"; save_req "$R"; turn "$R"; echo u > "$R/src/app.py"; git -C "$R" add -A; human "$R" commit -q -m ungated
    old="$(git -C "$R" rev-parse HEAD)"; [ "$when" = next ] && { stop "$R" >/dev/null; turn "$R"; }; sleep 1 # 同じ秒だと同じコミットになる
    eval "commits \"\$R\" $how" || ng "AC36（前提）: 変更なしの $how（$when）が pre-commit で止まった"
    [ "$(git -C "$R" rev-parse HEAD)" != "$old" ] || ng "AC36（前提）: $how でコミットが付け直されていない"
    is_block "$(stop "$R")" || ng "AC36: 関門を通っていないコミットを変更なしの git commit $how（$when のターン）で付け直したら Stop が差し戻さない"
    rm -rf "$R"
  done
done
# 関門を通ったコミットに、文書を足す・証拠をそろえたコードを足す --amend（次のターン）は差し戻さない
for add in doc code; do
  R="$(newrepo amok)"; save_req "$R"; turn "$R"; echo g > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
  commits "$R" -m gated || ng "AC36（前提）: 証拠のそろったコミットが止まった"; stop "$R" >/dev/null; turn "$R"
  if [ "$add" = doc ]; then echo note > "$R/README.md"; else save_req "$R"; echo g2 > "$R/src/app.py"; echo h > "$R/src/helper.py"; evidence "$R"; fi
  git -C "$R" add -A; commits "$R" --amend --no-edit || ng "AC36: 関門を通ったコミットに $add を足す --amend が止まった: $(commit_err "$R" --amend --no-edit)"
  out="$(stop "$R")"; is_block "$out" && ng "AC36: 関門を通ったコミットに $add を足す --amend を Stop が差し戻した: $out"
  is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC36: $add を足す --amend の後の push を拒否した"
  rm -rf "$R"
done
# 関門を通ったコミットに証拠の無いコードを足す --amend は止まる（足したものが関門を通らない）
R="$(newrepo amng)"; save_req "$R"; turn "$R"; echo g > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A; commits "$R" -m gated
stop "$R" >/dev/null; turn "$R"; echo bad > "$R/src/app.py"; git -C "$R" add -A
commits "$R" --amend --no-edit && ng "AC36: 関門を通ったコミットに証拠の無いコードを足す --amend が通った"
rm -rf "$R"

# ---------- AC29: 証拠が付かない・合わない理由を名指す ----------
R="$(newrepo why)"; save_req "$R"
turn "$R"; echo w1 > "$R/src/app.py"; ran "$R" "sh tests/ok.sh"; v="$(ver "$R")"
echo late > "$R/src/late_change.py"                                  # 報告の版の後に変わったファイル
accepted_v "$R" "$v"; reviewed_v "$R" "$v"
out="$(stop "$R")"
is_block "$out" || ng "AC29（前提）: 報告の版が合わないのに Stop が差し戻さない"
has "$out" "src/late_change.py" || ng "AC29: Stop の理由に、報告の版の後に変わったファイル名が無い: $out"
git -C "$R" add -A; err="$(commit_err "$R" -m x)"
has "$err" "src/late_change.py" || ng "AC29: pre-commit の理由に、報告の版の後に変わったファイル名が無い: $err"
R="$(newrepo pre)"; echo mine > "$R/src/pre_existing.py"; turn "$R"; save_req "$R"
echo t > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
err="$(commit_err "$R" -m x)"
[ -n "$err" ] || ng "AC29（前提）: 写しの前からあったファイルをステージしたコミットが止まらない"
has "$err" "src/pre_existing.py" || ng "AC29: pre-commit の理由に、写しの前からあったファイル名が無い: $err"
has "$err" "restore --staged" || ng "AC29: pre-commit の理由に手順（git restore --staged）が無い: $err"
ac="$D/config/claude/agents/acceptor.md"
grep -q 'mktemp' "$ac" && grep -Eq 'gitignore|無視' "$ac" || ng "AC29: acceptor.md に、出力をリポジトリの外（mktemp）か無視された場所に書くことが無い"
grep '版' "$ac" | grep -q '実行' || ng "AC29: acceptor.md に、版を実行を終えた後に取ることが無い"

# ---------- AC30: 関門を通っていないコミットを含むブランチの main・master への git merge ----------
for base in main master; do
  R="$(newrepo "mg-$base")"; [ "$base" = main ] || git -C "$R" branch -q -m main master
  save_req "$R"; turn "$R"; echo u > "$R/src/app.py"; git -C "$R" add -A; human "$R" commit -q -m ungated
  stop "$R" >/dev/null; human "$R" switch -q "$base"; turn "$R"
  for c in 'git merge feat/x' 'git merge --ff-only feat/x' 'git merge --no-ff -m m feat/x' 'git status && git merge feat/x'; do
    is_deny "$(guard_at "$R" "$c")" || ng "AC30: 関門を通っていないコミットを含むブランチの $base への merge を拒否しない: $c"
  done
  # git merge の「-」は直前のブランチ（@{-1}）= feat/x
  for c in 'git merge -' 'git merge --ff-only -'; do
    is_deny "$(guard_at "$R" "$c")" || ng "AC30: 直前のブランチ（-）の $base への merge を拒否しない: $c"
  done
  # 同じ Bash 呼び出しで feat/x から main・master に移ってから merge する形
  human "$R" switch -q feat/x; turn "$R"
  for c in "git switch $base && git merge --ff-only feat/x" "git checkout $base && git merge feat/x" "git switch $base; git merge feat/x" \
    "git switch -C $base && git merge feat/x" "git checkout -q $base 2>/dev/null && git merge feat/x" \
    "git switch $base && git merge -" "git checkout $base && git merge --ff-only -" \
    "git switch $base && git merge HEAD@{1}" "git checkout $base && git merge @{-1}" "git switch feat/x && git switch $base && git merge -"; do
    is_deny "$(guard_at "$R" "$c")" || ng "AC30: $base に移ってから merge する形を拒否しない: $c"
  done
  # main・master 以外に移ってからの merge は対象外
  for c in 'git switch --detach && git merge -' 'git switch -c main2 && git merge -'; do
    is_deny "$(guard_at "$R" "$c")" && ng "AC30: main・master 以外への merge を拒否した: $c"
  done
done
R="$(newrepo mg-ok)"; save_req "$R"; turn "$R"; echo g > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A; commits "$R" -m gated
stop "$R" >/dev/null; turn "$R"
for c in 'git switch main && git merge --ff-only -' 'git switch main && git merge HEAD@{1}'; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC30: 関門を通ったコミットだけのブランチの merge を拒否した: $c"
done
human "$R" switch -q main; turn "$R"
is_deny "$(guard_at "$R" 'git merge --ff-only feat/x')" && ng "AC30: 関門を通ったコミットだけのブランチの merge を拒否した"

# ---------- AC32: 誤検知を減らす。迂回は 235e128 の hook と同じく拒否 ----------
OLD="$TMP/old-hook"; git -C "$D" show 235e128:bin/harness-hook > "$OLD"; chmod +x "$OLD"
R="$(newrepo g32)"; mkdir -p "$R/scripts"; nl='
'
old_guard() { HOOK_BIN="$OLD" guard_at "$R" "$1"; }
for c in "rg -n 'no-verify' src/" 'grep -rn no-verify . | head -5' 'chmod +x .git/hooks/pre-commit' 'cp scripts/pre-commit .git/hooks/pre-commit' \
  'HOME=$PWD/tmp-home git init' "git commit -m \"\$(cat <<'EOF'${nl}fix: do not use git commit -n here${nl}EOF${nl})\""; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: 通さない（誤検知）: $c"
done
# 承認済みの変更（要件の写しの「## 変更の承認」）: --no-verify を検索の引数に書いた行は、235e128 と同じく拒否する（検索は 'no-verify' で代用）
for c in "rg -n -- '--no-verify' src/" 'grep -- --no-verify f'; do
  is_deny "$(old_guard "$c")" || ng "AC32（前提）: 235e128 の hook が通していた: $c"
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: --no-verify を検索の引数に書いた行を通す（承認済みの変更では拒否）: $c"
done
# 迂回の候補: 235e128 が拒否していたものは今も拒否する（今の hook で通るものがあれば失敗）。ダッシュ形の git、検索のコマンドの
# コマンドを起動するオプションを含む。ag は getopt_long なので --pag・--page も --pager として受け、出力が端末でなくても起動する（ag 2.2.0 で実測）
n_old=0
for c in 'git commit --no-verify -m x' 'git commit -n -m x' 'git commit -anm x' "rg -n -- '--no-verify' src/ && git commit -n -m x" \
  "grep -- --no-verify f; git commit --no-verify -m x" 'grep -q x f || git commit --no-verify -m x' "rg x \$(git commit -n -m x)" \
  'grep --no-verify f > out.txt' 'cat f | grep -- --no-verify | sh' "grep -- --no-verify f | xargs git commit" \
  'chmod +x ~/.config/git/hooks/pre-commit' 'chmod -x ~/.config/git/hooks/pre-commit' 'cp x ~/.config/git/hooks/pre-commit' \
  'rm ~/.config/git/hooks/pre-commit' 'ln -sf /bin/true ~/.config/git/hooks/pre-commit' 'cp x ~/.local/bin/harness-hook' \
  'chmod -x ~/.local/bin/harness-hook' 'rm ~/.local/bin/harness-hook' "cat > ~/.config/git/hooks/pre-commit <<'E'${nl}exit 0${nl}E" \
  'cp scripts/pre-commit .git/hooks/pre-commit && git config core.hooksPath .git/hooks' 'git config core.hooksPath .git/hooks' \
  'git -c core.hooksPath=.git/hooks commit -m x' 'HOME=$PWD/tmp-home git commit -m x' 'HOME=/tmp/h git commit -m x' \
  'env HOME=/tmp/h git commit -m x' 'XDG_CONFIG_HOME=/x git commit -m x' 'GIT_CONFIG_GLOBAL=/dev/null git commit -m x' \
  'HOME=$PWD/tmp-home git init && HOME=$PWD/tmp-home git commit -m x' 'export HOME=/tmp/h; git commit -m x' \
  "git commit -m \"\$(cat <<'EOF'${nl}msg${nl}EOF${nl})\" -n" "git commit -n -m \"\$(cat <<'EOF'${nl}msg${nl}EOF${nl})\"" \
  "sh -c \"\$(cat <<'EOF'${nl}git commit -n -m x${nl}EOF${nl})\"" "eval \"\$(cat <<'EOF'${nl}git commit -n -m x${nl}EOF${nl})\"" \
  "git commit \$(cat <<'EOF'${nl}-n${nl}EOF${nl}) -m x" "git commit -m \"\$(cat <<EOF${nl}\$(git commit -n -m y)${nl}EOF${nl})\"" \
  'env -u CLAUDECODE git commit -m x' 'git commit-tree HEAD^{tree} -m x' 'HOME=$PWD/h git rebase main' 'HOME=$PWD/h git merge feat/x' \
  "rg -n -- '--no-verify' src/ \$(git commit -n -m x)" 'cp scripts/pre-commit .git/hooks/pre-commit; git commit -n -m x' \
  'HOME=$PWD/tmp-home git init && git commit -n -m x' 'HOME=$PWD/h git am x.patch' 'HOME=$PWD/h git pull' 'HOME=$PWD/h git revert HEAD' \
  'HOME=$PWD/h git cherry-pick x' 'HOME=$PWD/h git -C r commit -m x' 'HOME=$PWD/h git init x && cd x && HOME=$PWD/h git commit -m y' \
  'rg --no-verify -l . | sh' 'cp scripts/x .git/config' 'ln -s ~/.config/git/hooks/pre-commit .git/hooks/x && rm ~/.config/git/hooks/pre-commit' \
  'git commit -m -m -n' 'git commit -m x -m -m -n' 'git commit -m --message -n' 'git commit --message -m -n' "git commit -m '-m' -n -a" \
  'git commit -m -m -nm x' 'git commit -m -- -n' 'git commit -m -F -n' 'git commit --message=-m -n' 'git commit -m -m -m -m -n' \
  'HOME=/tmp/h git-commit -m x' 'HOME=/tmp/h /opt/homebrew/opt/git/libexec/git-core/git-commit -m x' \
  'XDG_CONFIG_HOME=/x /usr/lib/git-core/git-merge feat' 'HOME=/tmp/h /usr/lib/git-core/git-co[m]mit -m x' \
  "HOME=/tmp/h /usr/lib/git-core/git''-commit -m x" '/usr/lib/git-core/git-commit -n -m x' \
  "ag --pager='git commit --no-verify -F -' x f" "ack --pager='git commit --no-verify -F -' x f" 'rg --pre sh -- --no-verify f' \
  "rg --hostname-bin='git commit --no-verify -m x' --hyperlink-format '{host}' x f" \
  "ag --pag='git commit --no-verify -F -' x f" "ag --page='git commit --no-verify -F -' x f" \
  "ag --pag 'git commit --no-verify -F -' x f" 'rg --pr=sh -- --no-verify f' \
  './rg commit --no-verify -m x' './grep commit --no-verify -m x' '/tmp/x/head commit --no-verify -m x' \
  "rg x <<EOF${nl}\$(git commit --no-verify -m x)${nl}EOF" "rg x <<EOF${nl}\`git commit --no-verify -m x\`${nl}EOF" \
  "head <<EOF${nl}\${x:-\$(git commit --no-verify -m x)}${nl}EOF" "rg x <<E\"OF\"${nl}foo${nl}EOF${nl}git commit --no-verify -m x"; do
  # ↑ './rg' からの 3 つ: パスで指した検索のコマンド名は別のプログラムでありうる（git へのシンボリックリンク ./rg で、失敗する pre-commit を
  # 飛ばしてコミットができることを bash・zsh で実測）。最後の 4 つ: 検索のコマンドのヒアドキュメント。区切りの語がクォートされていない
  # 本文のコマンド置換はシェルが実行する。<<E"OF" の区切りの語は EOF で、その後の行はコマンド（どれも bash・zsh でコミットができた）
  if is_deny "$(old_guard "$c")"; then
    n_old=$((n_old + 1)); is_deny "$(guard_at "$R" "$c")" || ng "AC32: 235e128 が拒否していた迂回を今の hook が通す: $c"
  fi
done
# PATH の前の方に git へのシンボリックリンク rg を置くと（~/.local/bin などへの ln -s は 235e128 も今も通す）、名前だけの rg も git になる
mkdir -p "$TMP/shadow"; ln -s "$(command -v git)" "$TMP/shadow/rg"
for c in 'rg commit --no-verify -m x'; do
  is_deny "$(PATH="$TMP/shadow:$PATH" old_guard "$c")" || ng "AC32（前提）: 235e128 の hook が通していた: $c"
  is_deny "$(PATH="$TMP/shadow:$PATH" guard_at "$R" "$c")" || ng "AC32: PATH の rg が git のとき、迂回を今の hook が通す: $c"
done
# alias や未知のサブコマンドで環境を差し替えた git（コミットを作りうる）も拒否する
for c in 'HOME=/tmp/h git ci -m x' 'env HOME=/tmp/h git ci -m x' 'GIT_CONFIG_GLOBAL=/dev/null git c -m x' 'HOME=/tmp/h git -C r ci -m x' \
  'HOME=/tmp/h git stash' 'HOME=/tmp/h git -c alias.x=commit x' 'HOME=/tmp/h sh -c "git ci -m x"' \
  'HOME=/tmp/h git $(echo commit) -m x' 'HOME=/tmp/h git `echo commit` -m x' 'HOME=/tmp/h git "$(printf commit)" -m x' \
  'HOME=/tmp/h git "$c"' 'HOME=/tmp/h git ${c}' 'env HOME=/tmp/h git -C r "$c" -m x' 'export HOME=/tmp/h; git "$c" -m x' \
  'HOME=/tmp/h git \commit -m x' "HOME=/tmp/h git c'o'mmit -m x" \
  'HOME=/tmp/h git {commit,-m,x}' 'HOME=/tmp/h git -C r {commit,-m,x}' 'XDG_CONFIG_HOME=/x git {merge,feat/y}' \
  'env HOME=/tmp/h git {commit,-m,x}' 'export HOME=/tmp/h; git {commit,-m,x}' 'HOME=/tmp/h git co{mmit,} -m x' 'HOME=/tmp/h git stat{us,}' \
  'env -u HOME /usr/lib/git-core/git-commit -m x' 'unset XDG_CONFIG_HOME HOME; /usr/lib/git-core/git-commit -m x' \
  'HOME=/tmp/h "$(git --exec-path)/git-commit" -m x'; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: 環境を差し替えた git を通す: $c"
done
# サブコマンドを展開で渡す形（R2-1。ブレース展開を含む）は、235e128 の hook も拒否していた（比較の前提）
for c in 'HOME=/tmp/h git $(echo commit) -m x' 'HOME=/tmp/h git `echo commit` -m x' 'HOME=/tmp/h git "$(printf commit)" -m x' \
  'HOME=/tmp/h git "$c"' 'HOME=/tmp/h git ${c}' 'HOME=/tmp/h git {commit,-m,x}' 'HOME=/tmp/h git -C r {commit,-m,x}' \
  'XDG_CONFIG_HOME=/x git {merge,feat/y}'; do
  is_deny "$(old_guard "$c")" || ng "AC32（前提）: 235e128 の hook が展開で渡す形を通していた: $c"
done
[ "$n_old" -ge 45 ] || ng "AC32（前提）: 235e128 の hook が拒否した候補が少ない（$n_old 件）。比べられていない"
# 環境を差し替えない形でも、ブレース展開で -n・--no-verify を渡すものは拒否する（235e128 では通っていた穴）
for c in 'git commit -{n,m} x' 'git {commit,-n,-m,x}' 'git commit {-n,-m,x}' 'git co{mmit,} -n -m x' 'git commit -m x {-n,}' \
  'git commit --{no-verify,} -m x' 'git commit -m x -{{n,},}' 'git commit -m x {"-n",}' 'sh -c '"'"'git commit -{n,m} x'"'" \
  'git commit -{a,b,c,d}{a,b,c,d}{a,b,c,d}{a,b,c,d}{a,b,c,d} -m x' \
  'git commit -{n..n} -m x' 'git commit -{n..m} x' 'git commit -m x -{n..n}' 'git commit -{l..n..2} -m x' \
  'git {commit,-{n..n},-m,x}' 'sh -c '"'"'git commit -{n..n} -m x'"'" \
  'git commit -m x -{a..z}{a..z}' 'git commit -{n..n}m{1..300}' 'git commit -m x {,-n}{,}{1..300}' \
  'git commit {-n,-m{1..1}}' 'git commit {-n,-m{1..300}}' 'git commit {-{n..n},-m1}' 'git commit -nm1' \
  'git commit -q{n..n} -m x' 'git commit -a{n,} -m x' 'git commit -m x {-n,f}' 'git commit -m x -v{,n}' \
  'git commit -m{,} {-n,}' 'git commit {-m,-m} {-n,}' 'git commit -m x -m{,} {-n,}' 'git commit -m{,,,} {-n,}' 'git commit -m -m -m{,} {-n,}'; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: ブレース展開で関門を飛ばす形を通す: $c"
done
# クォートの中の {a,b} は展開されない。展開したとみなすと -n が値に見えて位置がずれる形（R4-1）も、235e128 と同じく拒否する
for c in "git commit -m '{x,-m}' -n" 'git commit -m "{x,-m}" -n' "git -C '{a,b}' commit -n -m x" "git -c 'x.y={a,b}' commit -n -m x" \
  "git commit '-m{x,-m}' -n" 'git commit -m\{x,-m\} -n' "git commit -m '{x,-m}' --no-verify" "git commit -m '{a,b}' -n"; do
  is_deny "$(old_guard "$c")" || ng "AC32（前提）: 235e128 の hook がクォートの中のブレースの形を通していた: $c"
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: クォートの中のブレースで位置をずらした迂回を通す: $c"
done
# クォートの中のブレースと、クォートの外のブレース・連番で作る -n の組み合わせ（bash で実際にコミットできる形）も拒否する
for c in "git commit -m '{x,-m}' -{n..n}" "git commit -m '{x,-m}' {-n,}" "git commit -m x -m '{y,-m}' {-n,}" \
  'git commit -m \{x,-m\} {-n,}' "git -c 'x.y={a,b}' commit {-n,} -m x" "git commit -m '{x,-m}' {-n,-m{1..1}}" \
  'git commit -m {x,"-m}" {-n,}' "git commit -m \$'a\\'{x,-m}' {-n,}" 'git commit -m "a\"{x,-m}" {-n,}' 'git commit -m "a\\" {-n,}' \
  "git commit -m 'it'\"'\"'s {x,-m}' {-n,}" "git commit -m '{x,-m}' {\\-n,}" "git commit -m '{x,-m}' -a{n,}"; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: クォートの中と外のブレースを組み合わせた迂回を通す: $c"
done
for c in "git commit -m '{x,-m}' -a" "git commit -am '{x,-m}'" 'git commit -m "fix {a,b} parsing"' "git -C '{a,b}' status"; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: クォートの中にブレースを含む普通のコマンドを拒否した（誤検知）: $c"
done
# ブレース（連番を含む）を含む普通のコマンドは通す
for c in 'git commit -m "use {n,m} quantifiers"' 'echo {a,b}' 'cp src/{a,b}.py dst/' 'git add src/{a,b}.py' 'mv file.{txt,bak}' \
  'echo {1..3}' 'git commit -m x {1..a}' 'git add src/{a..c}.py' 'for i in {1..3}; do echo $i; done' 'git log -{1..3}' \
  'git commit -am new' 'git commit -qm next' 'git commit -sm note' 'git commit -m n' 'git commit -m -n' 'git log -n1'; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: ブレースを含む普通のコマンドを拒否した（誤検知）: $c"
done
# 大きな連番を含む普通のコマンド（235e128 は通していた）を、展開の上限で拒否しない（誤検知を増やさない）
for c in 'for i in {1..300}; do echo $i; done' 'git commit -m "{1..300}"' "echo '{1..300}'" 'touch file{001..300}.txt' \
  "printf '%s\\n' {a..z}{0..9}" 'echo {a..z}{a..z}' "python3 -c 'print(1)' {1..300}" 'git add src/{a..z}{a..z}.py'; do
  is_deny "$(old_guard "$c")" && ng "AC32（前提）: 235e128 の hook も拒否していた: $c"
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: 235e128 が通していた大きな連番のコマンドを拒否した（誤検知が増えた）: $c"
done
# 誤検知を減らした形は、235e128 では拒否されていた（変わったことの確認）
changed=0
for c in 'chmod +x .git/hooks/pre-commit' 'HOME=$PWD/tmp-home git init' \
  'git commit -uno -m x' 'git commit -mnote' 'git commit -Fn.txt'; do
  is_deny "$(old_guard "$c")" && changed=$((changed + 1))
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: 通さない（誤検知。-n の束ではない）: $c"
done
[ "$changed" -ge 1 ] || ng "AC32（前提）: 235e128 でも通していた（誤検知の修正が観測できない）"
# ヒアドキュメント: 区切りの語にクォート・エスケープが無い本文のコマンド置換は、データのコマンド（cat・wc・cd・git commit -F -・tinymemory）
# でもシェルが実行する。区切りの語はクォートを外して連結した語（<<E"OF"・<<'E'OF・<<E\OF は EOF）で、その行の後はコマンド。
# どれも失敗する pre-commit を置いたリポジトリで、bash・zsh ともにコミットができた（235e128 は多くを通していた穴）
B='$(git commit -n -m x)'; T='	'
for c in "cat <<EOF${nl}\$(git commit --no-verify -m x)${nl}EOF" "wc <<EOF${nl}${B}${nl}EOF" "cd . <<EOF${nl}\`git commit -n -m x\`${nl}EOF" \
  "git commit -F - <<EOF${nl}msg ${B}${nl}EOF" "cat <<E\"OF\"${nl}foo${nl}EOF${nl}git commit --no-verify -m x" \
  "cat <<'E'OF${nl}foo${nl}EOF${nl}git commit -n -m x" "cat <<E\\OF${nl}foo${nl}EOF${nl}git commit -n -m x" \
  "cat <<E\"O\"F${nl}foo${nl}EOF${nl}git commit -n -m x" "cat <<-EOF${nl}${T}${B}${nl}${T}EOF" "cat > out.txt <<EOF${nl}${B}${nl}EOF" \
  "cat <<'A' <<B${nl}x${nl}A${nl}${B}${nl}B" "tinymemory save <<EOF${nl}${B}${nl}EOF" "cat << EOF${nl}${B}${nl}EOF" \
  "cat <<EOF${nl}EOFX${nl}${B}${nl}EOF" "cat <<EOF | wc${nl}${B}${nl}EOF" "cat <<EOF${nl}\$(${nl}git commit -n -m x${nl})${nl}EOF" \
  "cat <<EOF${nl}'${B}'${nl}EOF" "cat <<\$X${nl}${B}${nl}\$X" "cat <<EOF${nl}\${x:=\`git commit -n -m x\`}${nl}EOF" \
  "cat <<EOF${nl}\$(cat <<'X'${nl}foo${nl}X${nl})${nl}${B}${nl}EOF" \
  "cat <<EOF${nl}# note ${B}${nl}EOF" "cat <<EOF${nl}x #\`git commit -n -m x\`${nl}EOF" "cat <<EOF${nl}\$(echo \")\"; git commit -n -m x)${nl}EOF" \
  "cat <<EOF${nl}\$(echo \\); git commit -n -m x)${nl}EOF" "cat <<EOF${nl}\$(echo '#'; git commit -n -m x)${nl}EOF" \
  "cat <<EOF${nl}\$((\`git commit -n -m x\`))${nl}EOF" "cat <<EOF${nl}\$(( ${B} ))${nl}EOF" "cat <<EOF${nl}\$[${B}]${nl}EOF" \
  "cat <<EOF${nl}\$(echo \"${B}\")${nl}EOF" "cat <<EOF${nl}\$(: ')' ; git commit -n -m x)${nl}EOF" "cat <<EOF${nl}\\\\${B}${nl}EOF"; do
  # ↑ 2 行目から（R2-1）: 本文の # の後の置換、置換の中のクォート・エスケープした )、算術展開の中の置換、\\ の後の置換（どれも bash・zsh でコミットができた）
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: ヒアドキュメントの本文・区切りの後で実行される迂回を通す: $c"
done
# 本文の文章（置換の外の git commit -n、# の行）は、置換の中身が安全ならデータ（R2-3。bash・zsh で実行してもコミットはできない）
for c in "cat > notes.txt <<EOF${nl}run git commit -n${nl}built \$(date)${nl}EOF" "cat > notes.txt <<EOF${nl}built \$(date) then git commit -n -m x${nl}EOF" \
  "cat > notes.txt <<EOF${nl}never run git commit -n; use \$(echo hooks)${nl}EOF" "cat > notes.txt <<EOF${nl}\$HOME and \`date\` ; git commit -n -m x${nl}EOF" \
  "cat > notes.txt <<EOF${nl}(git commit -n -m x)${nl}EOF"; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: ヒアドキュメントの本文の文章を拒否した（誤検知）: $c"
done
# 本文のバッククォートの中のエスケープ（\` \$）は、外したうえで中身を検査する。入れ子のバッククォートで実行される迂回は拒否
# （どれも bash・zsh でコミットができ、235e128 は通していた）。中身が安全なら文章は通す
E='`echo \`git commit -n -m x\``'
for c in "cat <<EOF${nl}${E}${nl}EOF" "cat <<EOF${nl}"'`echo \$(git commit -n -m x)`'"${nl}EOF" \
  "cat <<EOF${nl}"'`echo "\`git commit -n -m x\`"`'"${nl}EOF" "cat <<EOF${nl}"'x `: \`git commit -n -m x\``'"${nl}EOF" \
  "cat <<EOF${nl}# ${E}${nl}EOF" "cat <<EOF${nl}\${x:-${E}}${nl}EOF"; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: ヒアドキュメントの本文の入れ子のバッククォートで実行される迂回を通す: $c"
done
for c in "cat > notes.txt <<EOF${nl}"'built `echo \`date\``'"${nl}run git commit -n -m x later${nl}EOF" \
  "cat > notes.txt <<EOF${nl}"'`echo \$HOME` then git commit -n -m x'"${nl}EOF" \
  "cat > notes.txt <<EOF${nl}"'host `echo \`hostname\``; git commit -n -m x'"${nl}EOF"; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: 入れ子のバッククォートの中身が安全な本文の文章を拒否した（誤検知）: $c"
done
# ふつうのコマンド行・3 段の入れ子・$() の中の入れ子も同じ（受け入れ検証 21 回目の参考 1。どれも bash・zsh でコミットができた）。
# 中身が安全な入れ子は通す
for c in "echo ${E}" 'true && echo `echo \$(git commit -n -m x)`' "x=\$(echo ${E})" \
  "cat <<EOF${nl}"'`echo \`echo \\\`git commit -n -m x\\\`\``'"${nl}EOF" "cat <<EOF${nl}\$(echo ${E})${nl}EOF"; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: 入れ子のバッククォートで実行される迂回を通す: $c"
done
for c in 'echo `echo \`date\``' 'git log -1 --format=%s `echo \`git rev-parse HEAD\``' 'echo "built `echo \`date\``"; git status'; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: 中身が安全な入れ子のバッククォートを拒否した（誤検知）: $c"
done
# ダッシュ形の git はコマンドの位置かパスの直後の git- だけ（R2-2）。引数の中の git-（URL・ディレクトリ名）は通す
for c in 'HOME=$PWD/tmp-home git clone https://github.com/x/git-foo' 'git init ~/src/my-git-tool' 'HOME=$PWD/tmp-home git init ~/src/my-git-tool'; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: 引数に git- を含むコミットを作らない git を拒否した（誤検知）: $c"
done
for c in 'PATH="$(git --exec-path):$PATH" git-commit -n -m x' 'export PATH="$(git --exec-path):$PATH"; git-commit -n -m x' \
  '(PATH="$(git --exec-path):$PATH"; git-commit -n -m x)' '"$(git --exec-path)"/git-commit -n -m x' 'HOME=/tmp/h "$(git --exec-path)"/git-commit -m x' \
  'HOME=/tmp/h env git-commit -m x' 'exec git-commit -n -m x'; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC32: ダッシュ形の git の迂回を通す: $c"
done
# 区切りの語をクォート・エスケープした本文はデータ（シェルは展開しない）。記憶の保存・コミットメッセージ・ファイルへの書き出しは通す
for c in "tinymemory save <<'EOF'${nl}lesson: never git commit --no-verify; ${B} is bad${nl}EOF" \
  "git commit -F - <<'EOF'${nl}fix: guard git commit --no-verify and \`git commit -n\`${nl}${nl}${B}${nl}EOF" \
  "cat > notes.txt <<'EOF'${nl}git commit --no-verify -m x${nl}${B}${nl}EOF" "git commit -m \"\$(cat <<'EOF'${nl}fix: block git commit -n${nl}EOF${nl})\"" \
  "cat <<\"EOF\" > notes.txt${nl}${B}${nl}EOF" "cat <<\\EOF${nl}${B}${nl}EOF" "cat <<-'EOF' > notes.txt${nl}${T}${B}${nl}${T}EOF" \
  "harness-hook requirements-save <<'EOF'${nl}AC1: git commit --no-verify は拒否${nl}EOF" "cat > notes.txt <<EOF${nl}plain git commit -n mention${nl}EOF" \
  "cat > notes.txt <<EOF${nl}value \$((1+2)) and \$HOME${nl}EOF" "cat <<\"E'O\"F${nl}foo${nl}EOF${nl}git commit -n -m x"; do
  is_deny "$(guard_at "$R" "$c")" && ng "AC32: クォートした区切りのヒアドキュメント（データ）を拒否した（誤検知）: $c"
done

# ---------- AC31・AC33・AC35: 文書 ----------
grep -q 'timeout' "$D/config/claude/skills/verify/SKILL.md" && grep -q '600000' "$D/config/claude/skills/verify/SKILL.md" \
  || ng "AC31: /verify に、Bash の timeout（最大 600000 ミリ秒）を指定することが無い"
# 限界の細目は ARK-51 の 4 回目（AC43）で docs/harness.md に移った。移した先が項目ごとの箇条に分かれているかを見る
lim="$D/docs/harness.md"
[ "$(grep -c '^ *- ' "$lim")" -ge 10 ] || ng "AC33: docs/harness.md の限界の細目が項目ごとの箇条に分かれていない"
[ "$(awk 'length($0) > 1200' "$lim" | wc -l | tr -d ' ')" = 0 ] || ng "AC33: docs/harness.md に長い段落（1200 字超）が残っている"
grep -q '常時読み込む' "$D/README.md" && grep -q '43,631' "$D/README.md" && grep -q '31,752' "$D/README.md" \
  || ng "AC33: README に計測し直した常時読み込みの量（43,631 と 31,752）が無い"
grep -q '^| diagnosing-superpowers' "$D/README.md" || ng "AC33: superpowers との対応表に diagnosing-superpowers の行が無い"
srow="$(grep '^| S |' "$D/config/claude/CLAUDE.md")"
for w in 期待する結果 受け入れ条件 '1 問' 写し; do has "$srow" "$w" || ng "AC35: CLAUDE.md の S の行に「$w」が無い"; done

[ "$fail" = 0 ] && echo "harness-ark51-r3: ok"
[ "$fail" = 0 ]
