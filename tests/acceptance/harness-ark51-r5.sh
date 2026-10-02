#!/bin/sh
# 受け入れ検査（ARK-51 の 5 回目の修正。AC44〜AC52）。
# hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで、実物と同じ形の hook 入力を渡して観測する。
# コミット・stash・rebase・reset は実際の git（共通 hooks = config/git/hooks を GIT_CONFIG_GLOBAL で設定）で行う。
# AC44〜AC50 は 55a1257 の hook（git show で取り出す）でも同じ場面を流し、直す前は穴だったことを確かめる
# （hook の差し替えは ~/.local/bin/harness-hook のリンクの付け替え。共通 hooks もこれを呼ぶ）。
# 文書は言い回しの変更で壊れないよう、要となる語で確かめる。失敗が 1 つでもあれば exit 1。V=1 で観測値を出す
#   sh tests/acceptance/harness-ark51-r5.sh
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
ln -s "$UV" "$HOME/.local/libexec/uv"
printf '[core]\n\thooksPath = %s\n[user]\n\tname = t\n\temail = t@t\n[advice]\n\tdetachedHead = false\n' "$D/config/git/hooks" > "$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
OLD="$TMP/old-hook"; git -C "$D" show 55a1257:bin/harness-hook > "$OLD"; chmod +x "$OLD"
GATE="$HOME/.local/bin/harness-hook"
n=0
use() { # use <hook>: hook を差し替え、状態を新しくする（新旧の状態を混ぜない）
  ln -sf "$1" "$GATE"; n=$((n + 1)); export XDG_STATE_HOME="$TMP/state-$n"; }
use "$HOOK"

fail=0
ng() { echo "FAIL $1"; fail=1; }
say() { [ -z "${V:-}" ] || printf '  %s\n' "$*" >&2; }
SID="a51r5-$$"
ev() { # ev <hook のサブコマンド> <cwd> <イベント名> [追加の JSON]
  python3 -c 'import json, sys
d = {"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": "/dev/null", "hook_event_name": sys.argv[3]}
d.update(json.loads(sys.argv[4]) if len(sys.argv) > 4 else {})
print(json.dumps(d))' "$SID" "$2" "$3" "${4:-}" | "$GATE" "$1"; }
js() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
turn() { ev turn "$1" UserPromptSubmit '{"prompt": "x"}'; }
stop() { ev stop "$1" Stop '{"stop_hook_active": false, "last_assistant_message": "done"}'; }
ran() { ev bash "$1" PostToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}, \"tool_response\": {\"stdout\": \"\", \"stderr\": \"\", \"interrupted\": false}}"; }
failed() { # failed <cwd> <コマンド> [agent_id]: PostToolUseFailure（agent_id があればサブエージェントの中）
  ev bash-failed "$1" PostToolUseFailure "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}, \"error\": \"Exit code 1\"${3:+, \"agent_id\": \"$3\"}}"; }
ver() { (cd "$1" && sh "$D/config/claude/skills/review/snapshot.sh" 2>/dev/null) || true; }
accepted() { ev review-done "$1" SubagentStop "{\"agent_type\": \"acceptor\", \"last_assistant_message\": $(js "受け入れ検証した版: $(ver "$1")
## 条件ごとの結果
- [AC1] 合格 — a → b
## 判定
受け入れ: 合格")}"; }
reviewed() { ev review-done "$1" SubagentStop "{\"agent_type\": \"reviewer\", \"last_assistant_message\": $(js "レビューした版: $(ver "$1")
## 判定
仕様適合: 承認
テスト: 承認
品質・保守性: 承認")}"; }
evidence() { ran "$1" "sh tests/ok.sh"; accepted "$1"; reviewed "$1"; }
guard() { ev guard-bash "$1" PreToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}}"; }
guard_edit() { ev guard-branch "$1" PreToolUse "{\"tool_name\": \"Edit\", \"tool_input\": {\"file_path\": $(js "$2"), \"old_string\": \"a\", \"new_string\": \"b\"}}"; }
is_block() { case "$1" in *'"decision": "block"'*) return 0 ;; *) return 1 ;; esac; }
is_deny() { case "$1" in *'"permissionDecision": "deny"'*) return 0 ;; *) return 1 ;; esac; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
save_req() { printf 'AC1: 要件\n' | (cd "$1" && "$GATE" requirements-save) >/dev/null 2>&1; }
newrepo() { # newrepo <名前>: 宣言した検証（sh tests/ok.sh）と最初のコミットを持つ feat/x のリポジトリ（origin = 裸のリポジトリ）
  r="$TMP/r/$1"; mkdir -p "$r/tests" "$r/src" "$r/docs"; git init -q -b main "$r"
  printf 'sh tests/ok.sh\n' > "$r/.harness-verify"; printf 'exit 0\n' > "$r/tests/ok.sh"; echo base > "$r/src/lib.py"; echo doc > "$r/docs/note.md"
  git -C "$r" add -A; human "$r" commit -q -m init
  git init -q --bare -b main "$r.git"; git -C "$r" remote add origin "$r.git"; git -C "$r" push -q -u origin main 2>/dev/null
  git -C "$r" switch -q -c feat/x; echo "$r"; }
commits() { _r=$1; shift; git -C "$_r" commit -q "$@" >/dev/null 2>&1; }      # 共通 hooks（関門）を通る Claude のコミット
commit_err() { _r=$1; shift; git -C "$_r" commit -q "$@" 2>&1 >/dev/null || true; }
human() { _r=$1; shift; env -u CLAUDECODE git -C "$_r" "$@"; }                  # 人の操作（関門の対象外）
main_commit() { # main_commit <repo> <ファイル> <内容>: 人が main を進める（作業ブランチに戻る）
  _b="$(git -C "$1" branch --show-current)"; human "$1" switch -q main; echo "$3" > "$1/$2"; human "$1" add -A; human "$1" commit -q -m "main: $2"
  human "$1" switch -q "$_b"; }

# ---------- AC44: 証拠の指紋に土台（HEAD）のコード・テストを含める ----------
for H in "$HOOK" "$OLD"; do
  use "$H"; R="$(newrepo "s44-$n")"; save_req "$R"; turn "$R"
  echo feature > "$R/src/app.py"; evidence "$R"
  git -C "$R" stash -q -u
  echo base2 > "$R/src/lib.py"; human "$R" commit -q -am "base: code"    # 土台にコードのコミット
  git -C "$R" stash pop -q >/dev/null; git -C "$R" add -A
  save_req "$R"   # コミットで写しが古くなるので、同じ内容で保存し直す（指紋の写しの部分は変わらない）
  if [ "$H" = "$OLD" ]; then
    commits "$R" -m feat || ng "AC44（前提）: 55a1257 の hook も土台が変わった後のコミットを止めた（直す前の穴が観測できない）"
  else
    err="$(commit_err "$R" -m feat)"; say "AC44 拒否の理由: $(echo "$err" | head -n 3)"
    [ -n "$err" ] && [ "$(git -C "$R" log -1 --format=%s)" = "base: code" ] || ng "AC44: 証拠の後に土台がコードのコミットで変わったのに、同じ変更のコミットを pre-commit が止めない"
    evidence "$R"   # 新しい土台で証拠を取り直す（写しは保存し直さない）
    commits "$R" -m feat || ng "AC44: 新しい土台で証拠を取り直してもコミットできない: $(commit_err "$R" -m feat | head -n 3)"
    [ "$(git -C "$R" show HEAD:src/app.py)" = feature ] || ng "AC44: 取り直した後のコミットに変更が入っていない"
  fi
done
use "$HOOK"; R="$(newrepo s44-doc)"; save_req "$R"; turn "$R"
echo feature > "$R/src/app.py"; evidence "$R"
git -C "$R" stash -q -u; echo doc2 > "$R/docs/note.md"; human "$R" commit -q -am "base: docs"; git -C "$R" stash pop -q >/dev/null; git -C "$R" add -A
save_req "$R"
commits "$R" -m feat || ng "AC44: 土台が文書だけのコミットで変わったのに証拠が無効になった: $(commit_err "$R" -m feat | head -n 3)"

# ---------- AC45: main・master への取り込みは、関門を通った先端だけ ----------
# 準備: feat/x に関門を通ったコミット C1、人が main を進めた M1（別のファイル）、上流 origin/main は main より先（M2）
int_repo() {
  R="$(newrepo "s45-$n")"; save_req "$R"; turn "$R"; echo f > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
  commits "$R" -m C1 || ng "AC45（前提）: 関門を通るコミット C1 ができない"
  main_commit "$R" src/main.py m1
}
for H in "$HOOK" "$OLD"; do
  use "$H"; int_repo; turn "$R"
  nonff="$(guard "$R" 'git switch main && git merge feat/x')"
  git -C "$R" rebase -q main >/dev/null 2>&1 || ng "AC45（前提）: rebase できない"
  rebased="$(guard "$R" 'git switch main && git merge --ff-only feat/x')"
  bf="$(guard "$R" 'git branch -f main feat/x')"; ur="$(guard "$R" 'git update-ref refs/heads/main feat/x')"; sc="$(guard "$R" 'git switch -C main feat/x')"
  bc="$(guard "$R" 'git branch -C feat/x main')"; bm="$(guard "$R" 'git branch -M feat/x main')"; pd="$(guard "$R" 'git push . feat/x:main')"
  human "$R" switch -q main
  rs="$(guard "$R" 'git reset --hard feat/x')"; rb="$(guard "$R" 'git rebase feat/x')"
  if [ "$H" = "$OLD" ]; then
    is_deny "$rebased" && ng "AC45（前提）: 55a1257 の hook も rebase の後の先端の取り込みを拒否した（直す前の穴が観測できない）"
    say "AC45 55a1257: 非 ff の merge=$(is_deny "$nonff" && echo deny || echo allow) rebase 後の ff=$(is_deny "$rebased" && echo deny || echo allow) branch -f=$(is_deny "$bf" && echo deny || echo allow) update-ref=$(is_deny "$ur" && echo deny || echo allow) switch -C=$(is_deny "$sc" && echo deny || echo allow) reset=$(is_deny "$rs" && echo deny || echo allow) rebase on main=$(is_deny "$rb" && echo deny || echo allow)"
    continue
  fi
  say "AC45 rebase 後の ff の拒否の理由: $rebased"
  say "AC45 branch -C=$(is_deny "$bc" && echo deny || echo allow) branch -M=$(is_deny "$bm" && echo deny || echo allow) push .=$(is_deny "$pd" && echo deny || echo allow): $pd"
  for p in "非 ff の merge:$nonff" "rebase の後の先端の ff:$rebased" "branch -f main:$bf" "update-ref refs/heads/main:$ur" "switch -C main:$sc" "main の上の reset --hard feat/x:$rs" "main の上の rebase feat/x:$rb" \
           "branch -C feat/x main:$bc" "branch -M feat/x main:$bm" "push . feat/x（先 main）:$pd"; do
    is_deny "${p#*:}" || ng "AC45: ${p%%:*} を拒否しない: ${p#*:}"
  done
  say "AC45 非 ff の merge の拒否の理由: $nonff"
  for w in 'reset --soft main' '写し' '/accept' '/verify' '/review' 'コミット' 'ff-only'; do has "$rebased" "$w" || ng "AC45: rebase の後の拒否の理由に「$w」が無い: $rebased"; done
  for w in 'rebase' 'reset --soft' '写し' '/accept' '/verify' '/review'; do has "$nonff" "$w" || ng "AC45: 非 ff の merge の拒否の理由に「$w」が無い: $nonff"; done
  # 拒否しない形: main の古いコミットへ戻す reset、上流（origin/main。main より先）に合わせる reset
  is_deny "$(guard "$R" 'git reset --hard HEAD~1')" && ng "AC45: main の古いコミットへ戻す reset を拒否した"
  O="$TMP/r/other-$n"; human "$R" clone -q "$R.git" "$O" 2>/dev/null; echo m2 > "$O/src/up.py"; human "$O" add -A; human "$O" commit -q -m M2; human "$O" push -q origin main 2>/dev/null
  git -C "$R" fetch -q origin
  up="$(guard "$R" 'git reset --hard origin/main')"; is_deny "$up" && ng "AC45: 上流（origin/main）に合わせる reset を拒否した: $up"
  # 手順 9 の手順: rebase → reset --soft <基点> → 写しの保存 → 証拠 → コミット → ff
  human "$R" switch -q feat/x; turn "$R"
  git -C "$R" reset -q --soft main; save_req "$R"; evidence "$R"
  commits "$R" -m feat || ng "AC45: reset --soft と証拠の取り直しの後にコミットできない: $(commit_err "$R" -m feat | head -n 3)"
  ok="$(guard "$R" 'git switch main && git merge --ff-only feat/x')"
  is_deny "$ok" && ng "AC45: 手順どおりにコミットした先端の ff の取り込みを拒否した: $ok"
  okp="$(guard "$R" 'git push . feat/x:main')"; is_deny "$okp" && ng "AC45: 手順どおりにコミットした先端の push . feat/x:main を拒否した: $okp"
  ( cd "$R" && git switch -q main && git merge -q --ff-only feat/x ) || ng "AC45（前提）: 実際の ff ができない"
  [ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse feat/x)" ] || ng "AC45: ff の後に main が feat/x の先端でない"
done
step9="$(awk '/^9\. \*\*統合\*\*/ { f = 1 } f && /^$/ { exit } f' "$D/config/claude/CLAUDE.md")"
for w in 'git rebase <基点>' 'git reset --soft <基点>' '写しを保存し直す' '/accept' '/verify' '/review' 'コミット' 'fast-forward'; do
  has "$step9" "$w" || ng "AC45: CLAUDE.md の手順 9 に「$w」が無い"
done
python3 - "$step9" <<'EOF' || ng "AC45: CLAUDE.md の手順 9 の順序が rebase → reset --soft → 写し → /accept → /verify → /review → コミット → fast-forward でない"
import sys
s = sys.argv[1]; i = s.index("git rebase <基点>"); last = -1
for w in ["git rebase <基点>", "git reset --soft <基点>", "写しを保存し直す", "/accept", "/verify", "/review", "コミット", "fast-forward"]:
    j = s.index(w, i); assert j > last, w; last = i = j
EOF
# husky 型（リポジトリ側の core.hooksPath で共通の pre-commit が呼ばれない）: Bash の前の判定を通した文書だけのコミットは
# 関門を通ったものとして記録され、main に ff で取り込める。判定を通さずにできた同じ形のコミットは取り込まない
for how in guarded bare; do
  use "$HOOK"; R="$(newrepo "s45-husky-$how")"; mkdir -p "$R/.husky"; git -C "$R" config core.hooksPath .husky; turn "$R"
  echo code > "$R/src/app.py"
  is_deny "$(guard "$R" 'git commit -qam code')" || ng "AC45（husky 型）: 証拠の無いコードのコミットを Bash の前に止めない"
  rm "$R/src/app.py"; echo doc2 > "$R/docs/note.md"
  if [ "$how" = guarded ]; then
    g="$(guard "$R" 'git commit -qam docs')"; is_deny "$g" && ng "AC45（husky 型）: 文書だけのコミットを Bash の前に拒否した: $g"
    git -C "$R" commit -qam docs; ran "$R" 'git commit -qam docs'
  else
    git -C "$R" commit -qam docs
  fi
  [ "$(git -C "$R" log -1 --format=%s)" = docs ] || ng "AC45（husky 型・前提）: 文書だけのコミットができない"
  ff="$(guard "$R" 'git switch main && git merge --ff-only feat/x')"; say "AC45 husky 型 $how の ff: $ff"
  if [ "$how" = guarded ]; then
    is_deny "$ff" && ng "AC45（husky 型）: 判定を通した文書だけのコミットの先端の ff を拒否した: $ff"
    ( cd "$R" && git switch -q main && git merge -q --ff-only feat/x ) && [ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse feat/x)" ] \
      || ng "AC45（husky 型・前提）: 実際の ff ができない"
  else
    is_deny "$ff" || ng "AC45（husky 型）: 判定を通していない先端の ff を拒否しない（記録が効いているか分からない）"
  fi
done

# ---------- AC46: ターンとターンの間の利用者の編集は、変えずに未ステージなら証拠の対象から外す ----------
for H in "$HOOK" "$OLD"; do
  use "$H"; R="$(newrepo "s46-$n")"; turn "$R"; save_req "$R"
  echo claude > "$R/src/app.py"; stop "$R" >/dev/null
  echo user > "$R/src/user.py"; echo user-mod > "$R/src/lib.py"   # ターンの間の利用者の編集（未追跡と追跡済み）
  turn "$R"; evidence "$R"; git -C "$R" add src/app.py
  if [ "$H" = "$OLD" ]; then
    commits "$R" -m partial && ng "AC46（前提）: 55a1257 の hook も部分コミットを通した（直す前の穴が観測できない）"
    continue
  fi
  commits "$R" -m partial || ng "AC46: ターンの間の利用者の編集があると、Claude の分だけの部分コミットができない: $(commit_err "$R" -m partial | head -n 3)"
  [ "$(git -C "$R" show --name-only --format= HEAD)" = src/app.py ] || ng "AC46: 部分コミットに app.py 以外が入った"
  is_block "$(stop "$R")" && ng "AC46: 部分コミットの後の Stop が差し戻した（利用者の編集が残っているだけ）"
  turn "$R"; git -C "$R" add src/user.py
  err="$(commit_err "$R" -m user)"; say "AC46 利用者の編集をステージしたときの理由: $(echo "$err" | head -n 2)"
  [ -n "$err" ] && [ "$(git -C "$R" log -1 --format=%s)" = partial ] || ng "AC46: 利用者の編集をステージしたのに、証拠なしでコミットできた"
  has "$err" 'src/user.py' || ng "AC46: 利用者の編集をステージしたときの理由にそのファイル名が無い: $err"
  # 理由の文は、ターンの間に変わった利用者の編集も含むことが分かる言い回し（写しの前からあったものだけと書かない）
  has "$err" '利用者の作業中の変更' && has "$err" 'ターンとターンの間' || ng "AC46: 理由の文が利用者の作業中の変更（ターンの間の編集を含む）を示していない: $err"
  has "$err" 'git restore --staged' || ng "AC46: 理由の文にステージから外す戻し方が無い: $err"
done

# ---------- AC47: 競合を解消した rebase の後の差し戻しは、reset --soft の先が新しい土台 ----------
for H in "$HOOK" "$OLD"; do
  use "$H"; R="$(newrepo "s47-$n")"; save_req "$R"; turn "$R"; echo feat > "$R/src/lib.py"; evidence "$R"; git -C "$R" add -A
  commits "$R" -m C1 || ng "AC47（前提）: 関門を通るコミット C1 ができない"
  base0="$(git -C "$R" rev-parse --short main)"; main_commit "$R" src/lib.py main-side; m1="$(git -C "$R" rev-parse --short main)"
  stop "$R" >/dev/null; turn "$R"
  git -C "$R" rebase -q main >/dev/null 2>&1 && ng "AC47（前提）: rebase が競合しない"
  echo resolved > "$R/src/lib.py"; git -C "$R" add src/lib.py
  GIT_EDITOR=true git -C "$R" rebase --continue >/dev/null 2>&1 || GIT_EDITOR=true human "$R" rebase --continue >/dev/null 2>&1 || ng "AC47（前提）: rebase --continue できない"
  [ "$(git -C "$R" rev-parse HEAD~1)" = "$(git -C "$R" rev-parse main)" ] || ng "AC47（前提）: rebase の後の HEAD の親が main でない"
  out="$(stop "$R")"; say "AC47 $(basename "$H"): $out"
  got="$(printf '%s' "$out" | grep -o 'reset --soft [0-9a-f]*' | head -n 1 | sed 's/reset --soft //')"
  if [ "$H" = "$OLD" ]; then
    case "$(git -C "$R" rev-parse "$got" 2>/dev/null)" in "$(git -C "$R" rev-parse main)") ng "AC47（前提）: 55a1257 の hook も新しい土台を示した（直す前の穴が観測できない）" ;; esac
    say "AC47 55a1257 の reset --soft の先: $got（main の古い先端 $base0、新しい土台 $m1）"
  else
    is_block "$out" || ng "AC47: 競合を解消した rebase の後の Stop が差し戻さない"
    [ -n "$got" ] && [ "$(git -C "$R" rev-parse "$got")" = "$(git -C "$R" rev-parse main)" ] || ng "AC47: reset --soft の先（$got）が新しい土台 $m1 でない: $out"
  fi
done

# ---------- AC48: コミット時刻を過去にした、関門を通っていないコミットも Stop が差し戻す ----------
for H in "$HOOK" "$OLD"; do
  use "$H"; R="$(newrepo "s48-$n")"; save_req "$R"; turn "$R"; echo x > "$R/src/app.py"; git -C "$R" add -A
  GIT_COMMITTER_DATE='2020-01-01T00:00:00' GIT_AUTHOR_DATE='2020-01-01T00:00:00' human "$R" commit -q -m backdated
  out="$(stop "$R")"
  if [ "$H" = "$OLD" ]; then is_block "$out" && ng "AC48（前提）: 55a1257 の hook も差し戻した（直す前の穴が観測できない）"
  else
    is_block "$out" || ng "AC48: コミット時刻を過去にした、関門を通っていないコミットを Stop が差し戻さない"
    has "$out" "$(git -C "$R" rev-parse --short HEAD)" || ng "AC48: 差し戻しの理由にそのコミットが無い: $out"
    is_deny "$(guard "$R" 'git push origin feat/x')" || ng "AC48: そのコミットの push を拒否しない"
  fi
done

# ---------- AC49: main の先端の detached HEAD で、編集と写しの保存を拒否する ----------
for H in "$HOOK" "$OLD"; do
  use "$H"; R="$(newrepo "s49-$n")"; human "$R" switch -q --detach main
  e="$(guard_edit "$R" "$R/src/app.py")"; rc=0; printf 'AC1: x\n' | (cd "$R" && "$GATE" requirements-save) >/dev/null 2>&1 || rc=$?
  if [ "$H" = "$OLD" ]; then
    is_deny "$e" && [ "$rc" != 0 ] && ng "AC49（前提）: 55a1257 の hook も拒否した（直す前の穴が観測できない）"
  else
    is_deny "$e" || ng "AC49: main の先端の detached HEAD で編集を拒否しない: $e"
    [ "$rc" != 0 ] || ng "AC49: main の先端の detached HEAD で写しの保存を拒否しない"
    [ -s "$(cd "$R" && "$GATE" requirements-path)" ] && ng "AC49: 拒否したのに写しが書かれた"
  fi
done
# rebase の途中（競合で main の先端の detached HEAD に止まっている）は、競合を解消する編集を拒否しない（merge・apply の両方の方式）
for how in merge apply; do
  use "$HOOK"; R="$(newrepo "s49-rb-$how")"; save_req "$R"; turn "$R"; echo feat > "$R/src/lib.py"; evidence "$R"; git -C "$R" add -A
  commits "$R" -m C1 || ng "AC49（前提）: 関門を通るコミット C1 ができない"
  main_commit "$R" src/lib.py main-side
  if [ "$how" = apply ]; then git -C "$R" rebase -q --apply main >/dev/null 2>&1 && ng "AC49（前提）: rebase が競合しない"
  else git -C "$R" rebase -q main >/dev/null 2>&1 && ng "AC49（前提）: rebase が競合しない"; fi
  [ -d "$(git -C "$R" rev-parse --absolute-git-dir)/rebase-$how" ] || ng "AC49（前提）: rebase-$how が無い"
  [ -z "$(git -C "$R" symbolic-ref -q HEAD)" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || ng "AC49（前提）: 競合中の HEAD が main の先端の detached でない"
  e="$(guard_edit "$R" "$R/src/lib.py")"; say "AC49 rebase（$how）の競合中の編集: ${e:-（出力なし = 許可）}"
  is_deny "$e" && ng "AC49: rebase（$how）の競合を解消する編集を拒否した: $e"
  git -C "$R" rebase --abort
done

# ---------- AC50: サブエージェント内の検証の失敗は RED の記録だけで、メインの検証済みを消さない ----------
for H in "$HOOK" "$OLD"; do
  use "$H"; R="$(newrepo "s50-$n")"; save_req "$R"; turn "$R"; echo y > "$R/src/app.py"
  ran "$R" "sh tests/ok.sh"; failed "$R" "sh tests/ok.sh" sub-1; accepted "$R"; reviewed "$R"; git -C "$R" add -A
  if [ "$H" = "$OLD" ]; then
    commits "$R" -m y && ng "AC50（前提）: 55a1257 の hook でもサブエージェントの失敗の後にコミットできた（直す前の穴が観測できない）"
  else
    commits "$R" -m y || ng "AC50: サブエージェント内の検証の失敗で、メインの検証済みが消えた: $(commit_err "$R" -m y | head -n 3)"
    grep -q 'sh tests/ok.sh' "$(git -C "$R" rev-parse --absolute-git-dir)/harness-red-log" 2>/dev/null || ng "AC50: サブエージェント内の失敗が RED として記録されていない"
    # メインの失敗は、これまでどおり検証済みを消す
    echo z > "$R/src/app.py"; ran "$R" "sh tests/ok.sh"; failed "$R" "sh tests/ok.sh"; accepted "$R"; reviewed "$R"; git -C "$R" add -A
    commits "$R" -m z && ng "AC50: メインの検証の失敗の後でもコミットできた（検証済みが消えていない）"
  fi
done

# ---------- AC51: 文書の食い違い ----------
C="$D/config/claude"
flow="$(grep -m1 '^流れ（どの規模もこの順' "$C/CLAUDE.md")"
has "$flow" 'S は受け入れ条件を 1 行で示して' || ng "AC51: CLAUDE.md の流れの S の説明が受け入れ条件の 1 行になっていない: $flow"
has "$flow" '1 問' || ng "AC51: CLAUDE.md の流れの S に、期待する結果が無いとき 1 問で確かめることが無い"
srow="$(grep -m1 '^| S |' "$C/CLAUDE.md")"; has "$srow" '1 問' && has "$srow" '受け入れ条件の 1 行' || ng "AC51: CLAUDE.md の表の S の行と流れの S が食い違う: $srow"
scenes="$(sed -n 's/^#   sh tests\/e2e-flow.sh .*\[\([a-z|]*\)\].*/\1/p' "$D/tests/e2e-flow.sh" | head -n 1 | tr '|' '\n' | grep -c .)"
[ "$scenes" = 5 ] || ng "AC51: tests/e2e-flow.sh の場面が 5 でない（$scenes）"
grep -q "の $scenes 場面）" "$D/README.md" || ng "AC51: README の e2e の場面の数が tests/e2e-flow.sh の $scenes と合わない"
brain="$(grep -m1 '^| brainstorming |' "$D/README.md")"
[ "$(printf '%s' "$brain" | awk -F' \\| ' '{ print $3 }')" = superpowers ] || ng "AC51: README の brainstorming の強い方が superpowers でない: $brain"
has "$brain" spike && has "$brain" '視覚' || ng "AC51: README の brainstorming に spike・視覚の補助が無いことが書かれていない"
grep 'env -u CLAUDECODE' "$D/docs/harness.md" | grep -q 'スクリプトの中' || ng "AC51: docs/harness.md の env -u CLAUDECODE にスクリプトの中で使うことが無い"
hdr="$(grep -c '^ *| 分類 | 拒否する形 | 通す形 |' "$D/docs/harness.md" || true)"
[ "$hdr" = 1 ] || ng "AC51: docs/harness.md に拒否する形と通す形の 1 つの表が無い（見出しの行 $hdr）"
grep -Eq '^- (拒否する形|通す形)[:：（]' "$D/docs/harness.md" && ng "AC51: docs/harness.md に拒否する形・通す形の別々の箇条書きが残っている"
models="$(grep -m1 '^サブエージェントは用途に合わせる' "$C/CLAUDE.md")"
has "$models" 'opus に固定' || ng "AC51: CLAUDE.md の受け入れ検証・レビューのモデルが opus の固定と書かれていない"
for a in acceptor reviewer; do grep -qx 'model: opus' "$C/agents/$a.md" || ng "AC51: agents/$a.md の model が opus でない"; done
v="$(cat "$C/skills/verify/SKILL.md")"; has "$v" '.gitignore' && has "$v" '生成物' || ng "AC51: /verify に検証の生成物を先に .gitignore に入れることが無い"
# 写しが無いときの理由（ブランチ名を変えたら保存し直す）、写しが古いときの理由（--new）。実際の Stop と pre-commit で観測する
use "$HOOK"; R="$(newrepo s51-missing)"; turn "$R"; echo w > "$R/src/app.py"; out="$(stop "$R")"
has "$out" 'ブランチ名を変えた' || ng "AC51: 写しが無いときの理由に、ブランチ名を変えたら保存し直すことが無い: $out"
R="$(newrepo s51-stale)"; save_req "$R"; turn "$R"; echo a > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
commits "$R" -m a || ng "AC51（前提）: 最初のコミットができない"
turn "$R"; echo b > "$R/src/app.py"; out="$(stop "$R")"; git -C "$R" add -A; err="$(commit_err "$R" -m b)"
say "AC51 写しが古いとき: $out / $(echo "$err" | head -n 2)"
has "$out" 'requirements-save --new' || ng "AC51: 写しが古いときの Stop の理由に requirements-save --new が無い: $out"
has "$err" 'requirements-save --new' || ng "AC51: 写しが古いときの pre-commit の理由に requirements-save --new が無い: $err"
# tests/skills.sh が README の e2e の場面の数を確かめる（本物で通り、場面の数を変えた写しで落ちる）
sh "$D/tests/skills.sh" >/dev/null 2>&1 || ng "AC51: tests/skills.sh が本物のリポジトリで落ちる"
T="$TMP/copy"; mkdir -p "$T/config/claude" "$T/bin" "$T/tests"
cp -R "$C/skills" "$C/agents" "$C/CLAUDE.md" "$C/settings.json" "$T/config/claude/"; cp "$D/install.sh" "$D/README.md" "$T/"; cp "$HOOK" "$T/bin/"; cp "$D/tests/e2e-flow.sh" "$T/tests/"
sh "$D/tests/skills.sh" "$T" >/dev/null 2>&1 || ng "AC51（前提）: 壊す前の写しで tests/skills.sh が落ちる"
sed 's/の 5 場面）/の 4 場面）/' "$D/README.md" > "$T/README.md"; cmp -s "$T/README.md" "$D/README.md" && ng "AC51（前提）: README の場面の数を書き換えられない"
out="$(sh "$D/tests/skills.sh" "$T" 2>&1)" && ng "AC51: README の場面の数を 4 にしても tests/skills.sh が通った"
has "$out" 'e2e の場面の数' || ng "AC51: tests/skills.sh の失敗に e2e の場面の数の項目が無い: $out"
grep -q '否定: e2e の場面' "$D/tests/skills.sh" || ng "AC51: tests/skills.sh に e2e の場面の数の否定のテストが無い"

# ---------- AC52: Stop と SubagentStop の harness-hook の timeout が 60 秒 ----------
python3 - "$C/settings.json" <<'EOF' || ng "AC52: settings.json の Stop・SubagentStop の harness-hook の timeout が 60 でない"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
for ev, sub in (("Stop", "harness-hook stop"), ("SubagentStop", "harness-hook review-done")):
    t = [x.get("timeout") for g in h[ev] for x in g["hooks"] if x["command"].endswith(sub)]
    assert t == [60], (ev, t)
EOF

[ "$fail" = 0 ] && echo "acceptance ark51-r5: ok"
exit "$fail"
