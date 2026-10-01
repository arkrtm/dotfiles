#!/bin/sh
# 受け入れ検査（ARK-51 の 4 回目の修正。AC37〜AC43）。
# hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで、実物と同じ形の hook 入力を渡して観測する。
# コミット・revert・cherry-pick は実際の git（共通 hooks = config/git/hooks を GIT_CONFIG_GLOBAL で設定）で行う。
# AC37・AC39 は c8c8485 の hook（git show で取り出す）でも同じ場面を流し、直す前は穴だったことを確かめる。
# 文書は言い回しの変更で壊れないよう、要となる語で確かめる。失敗が 1 つでもあれば exit 1
#   sh tests/acceptance/harness-ark51-r4.sh
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
OLD="$TMP/old-hook"; git -C "$D" show c8c8485:bin/harness-hook > "$OLD"; chmod +x "$OLD"

fail=0
ng() { echo "FAIL $1"; fail=1; }
SID="a51r4-$$"
ev() { # ev <hook のサブコマンド> <cwd> <イベント名> [追加の JSON] — HOOK_BIN で hook を差し替えられる（c8c8485 との比較）
  python3 -c 'import json, sys
d = {"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": "/dev/null", "hook_event_name": sys.argv[3]}
d.update(json.loads(sys.argv[4]) if len(sys.argv) > 4 else {})
print(json.dumps(d))' "$SID" "$2" "$3" "${4:-}" | "${HOOK_BIN:-$HOOK}" "$1"; }
js() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
turn() { ev turn "$1" UserPromptSubmit '{"prompt": "x"}'; }
stop() { ev stop "$1" Stop '{"stop_hook_active": false, "last_assistant_message": "done"}'; }
stopc() { ev stop "$1" Stop '{"stop_hook_active": true, "last_assistant_message": "done"}'; }  # 差し戻しの後の続き
ran() { ev bash "$1" PostToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}, \"tool_response\": {\"stdout\": \"\", \"stderr\": \"\", \"interrupted\": false}}"; }
ver() { (cd "$1" && sh "$D/config/claude/skills/review/snapshot.sh" 2>/dev/null) || true; }
ACS=1   # 報告に合格で書く受け入れ条件の番号（要件の写しの番号すべてが要る）
accepted_v() { ev review-done "$1" SubagentStop "{\"agent_type\": \"acceptor\", \"last_assistant_message\": $(js "受け入れ検証した版: $2
## 条件ごとの結果
$(for n in $ACS; do echo "- [AC$n] 合格 — a → b"; done)
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
husky() { # husky <名前>: リポジトリ側の core.hooksPath（.husky。何もしない pre-commit）を持つリポジトリ。共通 hooks は呼ばれない
  r="$(newrepo "$1")"; mkdir -p "$r/.husky"; printf 'exit 0\n' > "$r/.husky/pre-commit"; chmod +x "$r/.husky/pre-commit"
  git -C "$r" add -A; human "$r" commit -q -m husky; git -C "$r" config core.hooksPath .husky; echo "$r"; }
commits() { _r=$1; shift; git -C "$_r" commit -q "$@" >/dev/null 2>&1; }      # 共通 hooks（関門）を通るコミット
commit_err() { _r=$1; shift; git -C "$_r" commit -q "$@" 2>&1 >/dev/null || true; } # 止まったときの理由（stderr）
human() { _r=$1; shift; env -u CLAUDECODE git -C "$_r" "$@"; }                  # 人の操作（関門の対象外）
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# ---------- AC37: 差し戻しの後の続き（stop_hook_active）でも、関門を通っていないコミットの事後の確認をする ----------
# 場面 1: 関門を通っていないコミットで差し戻した後の続きで、もう 1 つ関門を通さずにコミットする
# 場面 2: コミット以外の理由（証拠が無い）で差し戻した後の続きで、関門を通さずにコミットする
for how in after-commit-block after-other-block; do
  for H in "$HOOK" "$OLD"; do
    export XDG_STATE_HOME="$TMP/state-37-$how-$(basename "$H")"; R="$(newrepo "s37-$how-$(basename "$H")")"
    HOOK_BIN=$H; export HOOK_BIN; save_req "$R"; turn "$R"
    if [ "$how" = after-commit-block ]; then
      echo u1 > "$R/src/app.py"; git -C "$R" add -A; human "$R" commit -q -m ungated1
      is_block "$(stop "$R")" || ng "AC37（前提・$how）: 関門を通っていないコミットを最初の Stop が差し戻さない"
    else
      echo w > "$R/src/app.py"
      is_block "$(stop "$R")" || ng "AC37（前提・$how）: 証拠の無いコード変更を最初の Stop が差し戻さない"
    fi
    echo u2 > "$R/src/other.py"; git -C "$R" add -A; human "$R" commit -q -m ungated-in-continuation; c2="$(git -C "$R" rev-parse --short HEAD)"
    out="$(stopc "$R")"
    if [ "$H" = "$OLD" ]; then
      is_block "$out" && ng "AC37（前提・$how）: c8c8485 の hook も続きで差し戻していた（直す前の穴が観測できない）"
    else
      is_block "$out" || ng "AC37: 差し戻しの後の続きで関門を通さずに作ったコミットを Stop が差し戻さない（$how）"
      has "$out" "$c2" || ng "AC37: 続きの差し戻しの理由に、続きで作ったコミット $c2 が無い（$how）: $out"
      is_block "$(stopc "$R")" && ng "AC37: 差し戻し済みのコミットだけなのに、続きの Stop がまた差し戻した（止まらなくなる。$how）"
      is_deny "$(guard_at "$R" 'git push origin feat/x')" || ng "AC37: 続きで作ったコミットの push を拒否しない（$how）"
      is_deny "$(guard_at "$R" 'git switch main && git merge --ff-only feat/x')" || ng "AC37: 続きで作ったコミットを含むブランチの main への merge を拒否しない（$how）"
      turn "$R"   # 次のターンでも記録は残る
      out="$(guard_at "$R" 'git push origin feat/x')"
      is_deny "$out" && has "$out" "$c2" || ng "AC37: 次のターンで、続きで作ったコミット $c2 の push を拒否しない（$how）: $out"
    fi
    unset HOOK_BIN
  done
done
export XDG_STATE_HOME="$TMP/state"
# 続きでコミットを作らなければ、続きの Stop は通す
R="$(newrepo s37-none)"; save_req "$R"; turn "$R"; echo u > "$R/src/app.py"; git -C "$R" add -A; human "$R" commit -q -m ungated
stop "$R" >/dev/null; is_block "$(stopc "$R")" && ng "AC37: 続きで新しいコミットが無いのに、続きの Stop が差し戻した"

# ---------- AC39: リポジトリ側の core.hooksPath があるリポジトリで、git 以外を含むコマンドの git commit ----------
for H in "$OLD" "$HOOK"; do
  export XDG_STATE_HOME="$TMP/state-39-$(basename "$H")"; HOOK_BIN=$H; export HOOK_BIN
  R="$(husky "hk-$(basename "$H")")"; save_req "$R"; turn "$R"; echo c4 > "$R/src/app.py"; evidence "$R"
  for c in 'git add -A && git commit -q -m x && echo done'; do
    is_deny "$(guard_at "$R" "$c")" && ng "AC39（前提）: 証拠がそろっているのに Bash の前の判定が拒否した: $c"
    (cd "$R" && sh -c "$c") >/dev/null; ran "$R" "$c"
    [ "$(git -C "$R" show HEAD:src/app.py)" = c4 ] || ng "AC39（前提）: コミットに証拠の内容が入っていない"
    out="$(stop "$R")"
    if [ "$H" = "$OLD" ]; then
      is_block "$out" || ng "AC39（前提）: c8c8485 の hook も差し戻さなかった（直す前の穴が観測できない）"
    else
      is_block "$out" && ng "AC39: 判定を通した「$c」の後の Stop が差し戻した: $out"
      is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC39: 判定を通した「$c」のコミットの push を拒否した"
    fi
  done
  unset HOOK_BIN
done
export XDG_STATE_HOME="$TMP/state"
# ほかの git 以外を含む形も記録する
for c in 'git commit -q -m y; echo done' 'git add -A && git commit -q -m z && npm --version >/dev/null 2>&1 || true'; do
  R="$(husky hk-more)"; save_req "$R"; turn "$R"; echo "$c" > "$R/src/app.py"; git -C "$R" add -A; evidence "$R"
  is_deny "$(guard_at "$R" "$c")" && ng "AC39（前提）: 証拠がそろっているのに判定が拒否した: $c"
  (cd "$R" && sh -c "$c") >/dev/null 2>&1; ran "$R" "$c"
  is_block "$(stop "$R")" && ng "AC39: 判定を通した「$c」の後の Stop が差し戻した"
  rm -rf "$R"
done
# 内容が証拠と違えば記録しない: ステージだけ違う内容、同じ行の git 以外のコマンドがコミットの前に内容を書き換える形
R="$(husky hk-ng1)"; save_req "$R"; turn "$R"; echo BAD > "$R/src/app.py"; git -C "$R" add src/app.py; echo GOOD > "$R/src/app.py"; evidence "$R"
c='git commit -q -m sneaky && echo done'; (cd "$R" && sh -c "$c") >/dev/null; ran "$R" "$c"
[ "$(git -C "$R" show HEAD:src/app.py)" = BAD ] || ng "AC39（前提）: ステージした BAD がコミットされていない"
is_block "$(stop "$R")" || ng "AC39: 証拠と違う内容（ステージだけ BAD）のコミットを関門を通ったものとして記録した"
R="$(husky hk-ng2)"; save_req "$R"; turn "$R"; echo good > "$R/src/app.py"; evidence "$R"
c='echo EVIL > src/app.py && git add -A && git commit -q -m x && echo done'; (cd "$R" && sh -c "$c") >/dev/null; ran "$R" "$c"
[ "$(git -C "$R" show HEAD:src/app.py)" = EVIL ] || ng "AC39（前提）: 書き換えた EVIL がコミットされていない"
is_block "$(stop "$R")" || ng "AC39: 同じ行で書き換えて証拠と違う内容になったコミットを、関門を通ったものとして記録した"
is_deny "$(guard_at "$R" 'git push origin feat/x')" || ng "AC39: 証拠と違う内容のコミットの push を拒否しない"

# ---------- AC38: requirements-save は写しが古くても条件の削除に承認を求める。--new で新しい依頼を始める ----------
ACS="1 2"; R="$(newrepo req)"; P="$(cd "$R" && "$HOOK" requirements-path)"
rsave() { printf '%b' "$2" | (cd "$R" && "$HOOK" requirements-save $1) 2>&1; }
rsave "" 'AC1: a\nAC2: b\n' >/dev/null || ng "AC38（前提）: 最初の版を保存できない"
turn "$R"; echo x > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A; commits "$R" -m gated || ng "AC38（前提）: 証拠のそろったコミットが止まった"
if out="$(rsave "" 'AC1: a\n')"; then ng "AC38: 写しが古い（コード変更のコミットの後）とき、AC2 が消えた版を承認の節なしで保存した"; else
  has "$out" "変更の承認" || ng "AC38: 保存しなかった理由に「## 変更の承認」が無い: $out"
  has "$out" "requirements-save --new" || ng "AC38: 保存しなかった理由に、新しい依頼なら --new を使うことが無い: $out"
fi
grep -q '^AC2: b' "$P" || ng "AC38: 保存しなかったのに写しが書き換わった"
rsave "" 'AC1: a\nAC2: b\n' >/dev/null || ng "AC38: 写しが古いとき、同じ条件（同じ依頼の続き）の版を保存しなかった"
turn "$R"; echo y > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A; commits "$R" -m g2 || ng "AC38（前提）: 2 回目のコミットが止まった"
rsave "" 'AC1: a\nAC2: b\nAC3: c\n' >/dev/null || ng "AC38: 写しが古いとき、条件を足す版を保存しなかった"
rsave "" 'AC3: c\n## 変更の承認\n> ユーザー: AC1・AC2 は要らない\n' >/dev/null || ng "AC38: 写しが古いとき、承認の節がある減らす版を保存しなかった"
ACS=1; n_before="$(ls "$P.history" | wc -l | tr -d ' ')"
rsave "--new" 'AC9: new\n' >/dev/null || ng "AC38: --new で新しい依頼の版を保存しなかった"
grep -q '^AC9: new' "$P" || ng "AC38: --new の後の写しが新しい版でない"
[ "$(ls "$P.history")" = 001.md ] || ng "AC38: --new の後の .history が新しい版から始まっていない: $(ls "$P.history" | tr '\n' ' ')"
[ "$(ls "$P.history.prev" 2>/dev/null | wc -l | tr -d ' ')" = "$n_before" ] || ng "AC38: 前の依頼の版（$n_before 版）が .history.prev に移っていない"
grep -q '^AC3: c' "$P.history.prev/$(ls "$P.history.prev" | tail -1)" || ng "AC38: .history.prev の最後の版が前の依頼の最後の版でない"
if rsave "" 'AC10: z\n' >/dev/null; then ng "AC38: --new の後、同じ依頼の途中で AC9 を消した版を承認なしで保存した"; fi
git -C "$R" switch -q main
rsave "--new" 'AC1: q\n' >/dev/null && ng "AC38: main の上で --new の保存ができた"
git -C "$R" switch -q feat/x
step2="$(awk '/^2\. \*\*要件の固定\*\*/ { f = 1 } /^3\. / { f = 0 } f' "$D/config/claude/CLAUDE.md")"
has "$step2" 'requirements-save --new' || ng "AC38: CLAUDE.md の手順 2 に requirements-save --new が無い"
hd="$D/docs/harness.md"
grep -q 'requirements-save --new' "$hd" && grep -q '\.history\.prev' "$hd" && grep '写しが古くなった後' "$hd" | grep -q '変更の承認' \
  || ng "AC38: README（細目の docs/harness.md）に、写しが古くても承認を求めること・--new・.history.prev が無い"
grep -q '\.history\.prev' "$D/config/claude/agents/reviewer.md" && grep '\.history\.prev' "$D/config/claude/agents/reviewer.md" | grep -q '続き' \
  || ng "AC38: reviewer.md に、.history.prev があるとき前の依頼の続きでないかを確かめることが無い"

# ---------- AC42: 頼まれた revert・cherry-pick は --no-commit で行い、証拠をそろえてから git commit する ----------
R="$(newrepo rv)"; save_req "$R"
turn "$R"; echo g1 > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A; commits "$R" -m gated || ng "AC42（前提）: 証拠のそろったコミットが止まった"
stop "$R" >/dev/null
# そのままの git revert（git の hook は呼ばれない）は Stop が差し戻す。文は迂回と決めつけず、--no-commit の手順を示す
turn "$R"; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1 || ng "AC42（前提）: git revert が失敗した"
out="$(stop "$R")"
is_block "$out" || ng "AC42（前提）: そのままの git revert の後に Stop が差し戻さない"
has "$out" "hook が呼ばれなかった" || ng "AC42: 差し戻しの文に「git の hook が呼ばれなかった」が無い: $out"
has "$out" "--no-commit" || ng "AC42: 差し戻しの文に --no-commit で行い直す手順が無い: $out"
has "$out" "迂回" && ng "AC42: 差し戻しの文が迂回と決めつけている: $out"
git -C "$R" reset -q --hard HEAD~1; stop "$R" >/dev/null
# --no-commit → 証拠 → git commit（実際の git と共通 hooks）。revert に手を加えた形は、証拠が無ければ止まる
turn "$R"; save_req "$R"
git -C "$R" revert --no-commit HEAD >/dev/null 2>&1 || ng "AC42: git revert --no-commit が失敗した"
echo fix > "$R/src/fix.py"; git -C "$R" add -A
[ -n "$(commit_err "$R" -m revert)" ] || ng "AC42（前提）: 手を加えた revert が証拠なしでコミットできた"
evidence "$R"; commits "$R" -m "Revert gated" || ng "AC42: revert --no-commit の後、証拠をそろえた git commit が止まった: $(commit_err "$R" -m r)"
[ "$(git -C "$R" log -1 --format=%s)" = "Revert gated" ] || ng "AC42（前提）: revert のコミットができていない"
git -C "$R" cat-file -e HEAD:src/app.py 2>/dev/null && ng "AC42（前提）: revert で src/app.py が戻っていない"
is_block "$(stop "$R")" && ng "AC42: revert --no-commit → 証拠 → git commit の後に Stop が差し戻した"
is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC42: revert --no-commit の手順のコミットの push を拒否した"
# cherry-pick も同じ
human "$R" switch -q -c other main; echo o > "$R/src/o.py"; git -C "$R" add -A; human "$R" commit -q -m other-change; human "$R" switch -q feat/x
turn "$R"; save_req "$R"
git -C "$R" cherry-pick --no-commit other >/dev/null 2>&1 || ng "AC42: git cherry-pick --no-commit が失敗した"
[ -n "$(commit_err "$R" -m cp)" ] || ng "AC42（前提）: 関門を通っていないコミットの cherry-pick が証拠なしでコミットできた"
evidence "$R"; commits "$R" -m "cp other" || ng "AC42: cherry-pick --no-commit の後、証拠をそろえた git commit が止まった"
is_block "$(stop "$R")" && ng "AC42: cherry-pick --no-commit → 証拠 → git commit の後に Stop が差し戻した"
step7="$(awk '/^7\. \*\*コミット\*\*/ { f = 1 } /^8\. / { f = 0 } f' "$D/config/claude/CLAUDE.md")"
printf '%s\n' "$step7" | grep -- '--no-commit' | grep 'revert' | grep -q 'cherry-pick' \
  || ng "AC42: CLAUDE.md の手順 7 に、頼まれた revert・cherry-pick を --no-commit で行う手順が無い"

# ---------- AC40: 受け入れ条件は行頭に AC1: の番号を付ける ----------
grep '^| S |' "$D/config/claude/CLAUDE.md" | grep -q 'AC1:' || ng "AC40: CLAUDE.md の S の行に AC1: の番号を付けることが無い"
printf '%s\n' "$step2" | grep 'AC1:' | grep -q '番号' || ng "AC40: CLAUDE.md の手順 2 に、受け入れ条件の行頭に AC1: の番号を付けることが無い"

# ---------- AC41: /wrap-up で関門の対象のファイルを変えるときの手順 ----------
wl="$(grep 'harness-code' "$D/config/claude/skills/wrap-up/SKILL.md" || true)"
for w in 写し /accept /verify /review コミット; do has "$wl" "$w" || ng "AC41: wrap-up の skill の関門の対象の行に「$w」が無い: $wl"; done

# ---------- AC43: README のハーネス節を分ける ----------
git -C "$D" show c8c8485:README.md > "$TMP/old-readme.md"
python3 - "$TMP/old-readme.md" "$D/README.md" "$hd" <<'EOF' || fail=1
import re, sys
def sec(t):
    s = t.index("## Claude Code ハーネス"); return t[s:t.index("## 端末ごとの注意", s)]
old, new, doc = sec(open(sys.argv[1]).read()), sec(open(sys.argv[2]).read()), open(sys.argv[3]).read()
bad = []
if len(new) * 2 > len(old): bad.append(f"README のハーネス節が c8c8485 の半分以下でない（{len(new)} / {len(old)} 字）")
if "docs/harness.md" not in new: bad.append("README のハーネス節から docs/harness.md へのリンクが無い")
for w in ["流れの全体図", "superpowers との対応", "| test-driven-development", "限界"]:
    if w not in new: bad.append(f"README のハーネス節に「{w}」が無い（概要・全体図・対応表・限界の要点を残す）")
# 限界の要点は短い箇条
pts = [l for l in new.split("### 仕組みと限界の要点")[-1].splitlines() if l.startswith("- ")]
if not pts or any(len(l) > 300 for l in pts): bad.append("README の限界の要点が短い箇条でない")
# 移した細目の見出し・語が docs/harness.md にある
for w in ["拒否する形", "通す形", "見ていないもの", "ヒアドキュメント", "git の hook が呼ばれない", "マージ・cherry-pick・revert の途中",
          "報告の版", "利用者の作業中の変更", "要件の写し", "関門の対象", "TDD", "検証（"]:
    if w not in doc: bad.append(f"docs/harness.md に「{w}」の細目が無い")
# 細目を失わない: c8c8485 の節（対応表を除く）のコード片（`…`）と ARK 番号が、README か docs/harness.md に残っている
body = "\n".join(l for l in old.splitlines() if not l.startswith("|"))
toks = {m.group(1) or m.group(2) for m in re.finditer(r"``\s?(.+?)\s?``|`([^`\n]+)`", body)} | set(re.findall(r"ARK-\d+", body))
lost = sorted(t for t in toks if t not in new + doc)
if len(toks) < 100: bad.append(f"（前提）c8c8485 の節から取り出したコード片が少ない（{len(toks)} 件）")
if lost: bad.append(f"c8c8485 の README にあった細目の語が消えた: {lost}")
for b in bad: print("FAIL AC43: " + b)
sys.exit(1 if bad else 0)
EOF

[ "$fail" = 0 ] && echo "harness-ark51-r4: ok"
[ "$fail" = 0 ]
