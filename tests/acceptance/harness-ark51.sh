#!/bin/sh
# 受け入れ検査（ARK-51）: 厳しい採点の指摘を直したもの（AC1〜AC13、2 回目の修正の AC14〜AC24）。
# hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで、実物と同じ形の hook 入力を渡して観測する。
# git の hook を通る・通らないコミットは、実際の git（共通 hooks = config/git/hooks を GIT_CONFIG_GLOBAL で設定）で作る。
# 一時ディレクトリの判定（AC5）を確かめるため、hook に渡す TMPDIR は $TMP/tmpdir にし、リポジトリはその外（$TMP/r）に置く。
# 文書は言い回しの変更で壊れないよう、要となる語と順序で確かめる。失敗が 1 つでもあれば exit 1
#   sh tests/acceptance/harness-ark51.sh
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
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"   # 本番と同じ: 全リポジトリの hook は run-hook（CLAUDECODE があれば関門）

fail=0
ng() { echo "FAIL $1"; fail=1; }
SID="a51-$$"
ev() { # ev <hook のサブコマンド> <cwd> <イベント名> [追加の JSON のキーと値（python の dict の中身）]
  python3 -c 'import json, sys
d = {"session_id": sys.argv[1], "cwd": sys.argv[2], "transcript_path": "/dev/null", "hook_event_name": sys.argv[3]}
d.update(json.loads(sys.argv[4]) if len(sys.argv) > 4 else {})
print(json.dumps(d))' "$SID" "$2" "$3" "${4:-}" | "$HOOK" "$1"; }
js() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
turn() { ev turn "$1" UserPromptSubmit '{"prompt": "x"}'; }
stop() { ev stop "$1" Stop '{"stop_hook_active": false, "last_assistant_message": "done"}'; }
ran() { # ran <cwd> <コマンド>: Bash の成功（PostToolUse）
  ev bash "$1" PostToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}, \"tool_response\": {\"stdout\": \"\", \"stderr\": \"\", \"interrupted\": false}}"; }
ver() { (cd "$1" && sh "$D/config/claude/skills/review/snapshot.sh" 2>/dev/null) || true; }   # ver <cwd>: 今の作業ツリー全体の版（報告に書く。hook は今の版の報告だけを記録する）
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
guard() { ev guard-bash "$R" PreToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$1")}}"; }
is_block() { case "$1" in *'"decision": "block"'*) return 0 ;; *) return 1 ;; esac; }
is_deny() { case "$1" in *'"permissionDecision": "deny"'*) return 0 ;; *) return 1 ;; esac; }
save_req() { printf 'AC1: 要件\n' | (cd "$1" && "$HOOK" requirements-save) >/dev/null; }
newrepo() { # newrepo <名前>: $TMP/r/<名前> に、宣言した検証（sh tests/ok.sh）と最初のコミットを持つ feat/x のリポジトリを作る
  r="$TMP/r/$1"; mkdir -p "$r/tests" "$r/src"; git init -q -b main "$r"
  printf 'sh tests/ok.sh\n' > "$r/.harness-verify"; printf 'exit 0\n' > "$r/tests/ok.sh"; echo base > "$r/src/lib.py"
  git -C "$r" add -A; env -u CLAUDECODE git -C "$r" commit -q -m init; git -C "$r" switch -q -c feat/x; echo "$r"; }
evidence() { ran "$1" "sh tests/ok.sh"; accepted "$1"; reviewed "$1"; }   # evidence <top>: 検証・受け入れ・レビュー
reset_tree() { git -C "$1" reset -q --hard; git -C "$1" clean -qfd; }

# ---------- AC1・AC3・AC10: guard-bash ----------
R="$(newrepo guard)"
for c in 'rsync -avt src/ ~/.config/git/hooks/' 'rsync -rt /tmp/c/ ~/.config/git/'; do
  is_deny "$(guard "$c")" || ng "AC1: 拒否しない: $c"
done
is_deny "$(guard 'rsync -rt ~/.config/git/ /tmp/backup/')" && ng "AC1: 通さない: rsync -rt ~/.config/git/ /tmp/backup/"
nl='
'
for c in "tinymemory save <<'E'${nl}git commit --no-verify と -n は使わない${nl}E" \
  "git commit -F - <<'E'${nl}guard: deny --no-verify and core.hooksPath${nl}E" "cat > f <<'E'${nl}git commit --no-verify -m x${nl}E" \
  "cat > notes.md <<'E'${nl}run it with sh; never git commit --no-verify${nl}E" "cat > f <<'E'${nl}git commit --no-verify${nl}E${nl}git add f" \
  "cat > f <<'E'${nl}set core.hooksPath carefully${nl}E" "cat > docs/notes.md <<'E'${nl}the hook blocks git config core.hooksPath /x${nl}E" \
  "tinymemory save --tag go <<'E'${nl}never git commit --no-verify${nl}E" "tinymemory save \"task notes\" <<'E'${nl}never git commit --no-verify${nl}E" \
  "tinymemory save --title \"bash tips\" <<'E'${nl}never git commit --no-verify${nl}E"; do
  is_deny "$(guard "$c")" && ng "AC3: 本文がデータのヒアドキュメントを拒否した: $c"
done
for c in "sh <<E${nl}git commit --no-verify -m x${nl}E" "bash -s <<E${nl}git commit --no-verify -m x${nl}E" "cat <<E | sh${nl}git commit --no-verify -m x${nl}E" \
  "zsh <<E${nl}git commit -n -m x${nl}E" "python3 <<E${nl}import os; os.system('git commit --no-verify')${nl}E" "ssh h <<E${nl}git commit --no-verify${nl}E" \
  ". /dev/stdin <<E${nl}git commit --no-verify${nl}E" "eval \"\$(cat <<E${nl}git commit --no-verify${nl}E${nl})\""; do
  is_deny "$(guard "$c")" || ng "AC3: シェル等に渡すヒアドキュメントの迂回を拒否しない: $c"
done
for c in 'git config --get core.hooksPath' 'git log src/commit.py -n 3' 'echo "CLAUDECODE=$CLAUDECODE"' 'aws s3 ls --no-verify-ssl'; do
  is_deny "$(guard "$c")" && ng "AC10: 通さない（誤検知）: $c"
done
# HEAD（456d6bf）の hook が拒否していた迂回は拒否のまま。下は、どれも実際の git で関門を飛ばせる形
# （git config は名前の後の --get などを値として書く: core.hooksPath が「--get」になり、共通 hooks が外れる。
#   declare・typeset・local・readonly で CLAUDECODE を空にすると、子の git の run-hook が関門を掛けない）
for c in 'git commit --no-verify -m x' 'git commit -n -m x' 'git -C . commit -anm x' 'git -c core.hooksPath=/dev/null commit -m x' \
  'git config core.hooksPath /dev/null' 'git config --unset core.hooksPath' 'env -u CLAUDECODE git commit -m x' 'CLAUDECODE= git commit -m x' \
  'unset CLAUDECODE; git commit -m x' 'git commit-tree HEAD^{tree} -m x' 'git log -1 && git commit -n -m x' 'git -c alias.c=commit c -n -m x' \
  'git config core.hooksPath --get' 'git config core.hooksPath --get-all' 'git config core.hooksPath -l' 'git config --global core.hooksPath --get' \
  'declare CLAUDECODE=; git commit -m x' 'typeset -x CLAUDECODE=' 'readonly CLAUDECODE=' 'local CLAUDECODE=' \
  'git config core.hooksPath --get-regexp' 'git config core.hooksPath /dev/null --get' 'git config -l; git config --global core.hooksPath /x' \
  'declare -gx CLAUDECODE=' 'export -n CLAUDECODE; git commit -m x'; do
  is_deny "$(guard "$c")" || ng "AC10: HEAD が拒否していた迂回を通す: $c"
done
# ヒアドキュメントでファイルに書き、同じコマンドの中で実行する形（AC3 と AC10 がぶつかる形は、実行する方を優先して拒否と決めた）と、
# AC3 の一覧に無い実行器に渡す形。どれも HEAD は拒否していた
run='git commit --no-verify -m x'
for c in "cat > x.sh <<'E'${nl}${run}${nl}E${nl}sh x.sh" "cat > f <<'E'${nl}${run}${nl}E${nl}bash f" "cat > f <<'E'${nl}${run}${nl}E${nl}. ./f" \
  "cat > f <<'E'${nl}${run}${nl}E${nl}chmod +x f; ./f" "cat > /tmp/f.sh <<'E'${nl}${run}${nl}E${nl}/tmp/f.sh" "cat > f <<'E'${nl}${run}${nl}E${nl}source f" \
  "awk '{system(\$0)}' <<E${nl}${run}${nl}E" "fish <<E${nl}${run}${nl}E" "xargs -I{} sh -c {} <<E${nl}${run}${nl}E" \
  "sh<<E${nl}${run}${nl}E" "\$SHELL <<E${nl}${run}${nl}E" "\"\$SHELL\" -s <<'E'${nl}${run}${nl}E" \
  "cat > Makefile <<'E'${nl}c:${nl}	${run}${nl}E${nl}make c" "cat > package.json <<'E'${nl}{\"scripts\":{\"c\":\"${run}\"}}${nl}E${nl}npm run c" \
  "cat > conftest.py <<'E'${nl}import os; os.system('${run}')${nl}E${nl}pytest"; do
  is_deny "$(guard "$c")" || ng "AC10: ヒアドキュメントを実行する形の迂回を通す: $c"
done
# 設定ファイルに hooksPath を書く形（cd .git の後の相対パス）と、! の後の CLAUDECODE の代入
for c in "cd .git && cat >> config <<E${nl}[core]${nl}	hooksPath = /dev/null${nl}E" ' \! CLAUDECODE= git commit -m x' '! CLAUDECODE= git commit -m x'; do
  is_deny "$(guard "$c")" || ng "AC10: HEAD が拒否していた迂回を通す: $c"
done
# ヒアドキュメントの本文がコマンド置換・read でコマンドの引数や設定値になる形、git rev-parse --git-path で求めた設定に書く形、
# mise のタスクで実行する形。どれも HEAD は拒否していた（本文が引数・値になることは無害な値で確かめた）
for c in "git commit \$(cat <<E${nl}--no-verify${nl}E${nl}) -m x" "git -c \"\$(cat <<E${nl}core.hooksPath=/dev/null${nl}E${nl})\" commit -m x" \
  "read -r a <<E${nl}--no-verify${nl}E${nl}git commit \$a -m x" "cat >> \"\$(git rev-parse --git-path config)\" <<E${nl}[core]${nl}hooksPath=/x${nl}E" \
  "cat > mise.toml <<'E'${nl}[tasks.c]${nl}run = \"${run}\"${nl}E${nl}mise run c"; do
  is_deny "$(guard "$c")" || ng "AC10: HEAD が拒否していた迂回を通す: $c"
done
# data とみなすコマンド（git・gh）が本文を実行・適用する形。どれも HEAD は拒否していた（無害な値で、実際の git・gh で確かめた:
# 設定の alias（!sh）・gh の shell alias は本文を sh で実行し、git apply は本文のパッチで ~/.gitconfig を書き換える）
cfgpatch="--- a/.gitconfig${nl}+++ b/.gitconfig${nl}@@ -0,0 +1,2 @@${nl}+[core]${nl}+	hooksPath = /dev/null"
for c in "git x <<'E'${nl}${run}${nl}E" "git config alias.x '!sh' && git x <<'E'${nl}${run}${nl}E" "cat <<'E' | git x${nl}${run}${nl}E" \
  "gh x <<'E'${nl}${run}${nl}E" "cd ~ && git apply <<'E'${nl}${cfgpatch}${nl}E" "git -C ~ apply <<'E'${nl}${cfgpatch}${nl}E" \
  "git apply --unsafe-paths --directory=\"\$HOME\" <<'E'${nl}${cfgpatch}${nl}E"; do
  is_deny "$(guard "$c")" || ng "AC10: HEAD が拒否していた迂回を通す: $c"
done
# 設定済みのエディタ（別のコマンドの git config core.editor sh。今の hook も HEAD も通す）に本文を渡す形: -e で、本文が入った
# メッセージのファイルをエディタ（sh）が実行する（無害な値で、実際の git で ~/.gitconfig に書けることを確かめた）。どれも HEAD は拒否していた。
# git は長いオプションの一意な省略を受け付ける（git 2.55 で --ed・--edi・--e もエディタを起動することを確かめた）。
# -t（--template）に標準入力を渡すと、本文を下書きとしてエディタを起動する（git 2.55 で -t /dev/stdin・--template=/dev/stdin を確かめた）
hp='git config --global core.hooksPath /dev/null'
for c in "git commit -e -F - <<'E'${nl}${hp}${nl}E" "git commit --edit -F - <<'E'${nl}${hp}${nl}E" \
  "git commit -aeF - <<'E'${nl}${hp}${nl}E" "git commit -F - -e <<'E'${nl}${hp}${nl}E" \
  "git commit --ed -F - <<'E'${nl}${hp}${nl}E" "git commit -F - --e <<'E'${nl}${hp}${nl}E" \
  "git tag -a v1 --ed -F - <<'E'${nl}${hp}${nl}E" "git notes add --edi -F - <<'E'${nl}${hp}${nl}E" \
  "git tag -a v1 -e -F - <<'E'${nl}${hp}${nl}E" "git notes add -e -F - <<'E'${nl}${hp}${nl}E" \
  "git commit -t /dev/stdin <<'E'${nl}${hp}${nl}E" "git commit --template=/dev/stdin <<'E'${nl}${hp}${nl}E" \
  "gh pr create -e --body-file - <<'E'${nl}${hp}${nl}E" "gh pr create --editor --body-file - <<'E'${nl}${hp}${nl}E"; do
  is_deny "$(guard "$c")" || ng "AC10: HEAD が拒否していた迂回を通す: $c"
done
# メッセージ（-F・-m）を渡さない形もエディタを起動し、エディタは標準入力（本文）を受け継ぐ。標準入力を読むエディタ
# （git config core.editor 'sh -s'。今の hook も HEAD も通す）なら本文を実行する（git 2.55 で commit -a・tag -a・notes add を確かめた）。どれも HEAD は拒否していた
for c in "git commit -a <<'E'${nl}${hp}${nl}E" "git commit <<'E'${nl}${hp}${nl}E" "git tag -a v1 <<'E'${nl}${hp}${nl}E" \
  "git notes add <<'E'${nl}${hp}${nl}E" "git commit --signoff <<'E'${nl}${hp}${nl}E"; do
  is_deny "$(guard "$c")" || ng "AC10: エディタに本文を渡す形の迂回を通す: $c"
done
# -m・-F があってもエディタを起動する形（-e、-c、--fixup=amend: など。git 2.55 で commit -e -m x が本文を実行することを確かめた）。どれも HEAD は拒否していた
for c in "git commit -e -m x <<'E'${nl}${hp}${nl}E" "git commit -em x <<'E'${nl}${hp}${nl}E" "git tag -a v1 -m x -e <<'E'${nl}${hp}${nl}E" \
  "git notes add -em x <<'E'${nl}${hp}${nl}E" "git commit -c HEAD -m x <<'E'${nl}${hp}${nl}E" "git commit --fixup=amend:HEAD -m x <<'E'${nl}${hp}${nl}E"; do
  is_deny "$(guard "$c")" || ng "AC10: -m があってもエディタを起動する形の迂回を通す: $c"
done

# ---------- AC4: git の hook を通らなかったコミットを Stop で見つける（実際の git）----------
R="$(newrepo husky)"; save_req "$R"
mkdir -p "$R/.husky"; git -C "$R" config core.hooksPath .husky   # リポジトリ側の hooksPath（husky 等）: 共通 hooks は呼ばれない
turn "$R"; echo c1 > "$R/src/app.py"; git -C "$R" add -A
if git -C "$R" commit -q -m nohook 2>/dev/null; then :; else ng "AC4（前提）: リポジトリ側の hooksPath があるのに、コミットが止まった"; fi
sha="$(git -C "$R" rev-parse --short HEAD)"; out="$(stop "$R")"
is_block "$out" || ng "AC4: hook を通らない証拠なしのコミット（$sha）を Stop が差し戻さない"
case "$out" in *"$sha"*) ;; *) ng "AC4: 差し戻しの理由にコミット $sha が無い: $out" ;; esac
case "$out" in *reset*) ;; *) ng "AC4: 差し戻しの理由に戻す手順（reset）が無い: $out" ;; esac
case "$out" in *ユーザー*) ;; *) ng "AC4: 差し戻しの理由に、戻せなければユーザーに報告することが無い: $out" ;; esac
# ターンより前のコミットでは差し戻さない（上の nohook はもうターンの前）
turn "$R"; is_block "$(stop "$R")" && ng "AC4: ターンより前の、hook を通らないコミットで差し戻した"
# ドキュメントだけのコミットでは差し戻さない
turn "$R"; echo d > "$R/README.md"; git -C "$R" add -A; git -C "$R" commit -q -m docs
is_block "$(stop "$R")" && ng "AC4: hook を通らないドキュメントだけのコミットで差し戻した"
# 関門を通ったコミットでは差し戻さない（共通 hooks に戻して、証拠をそろえてコミット）
git -C "$R" config --unset core.hooksPath; save_req "$R"
turn "$R"; echo c2 > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
if git -C "$R" commit -q -m gated 2>/dev/null; then
  is_block "$(stop "$R")" && ng "AC4: 関門を通ったコミットで差し戻した"
else ng "AC4（前提）: 証拠をそろえたのに関門を通ったコミットができない"; fi
# 関門を通した後に、リポジトリ自身の pre-commit（整形など）がインデックスを書き換えたコミットでも差し戻さない
printf '#!/bin/sh\necho formatted > src/fmt.py\ngit add src/fmt.py\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
save_req "$R"; turn "$R"; echo c4 > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
if git -C "$R" commit -q -m reformatted 2>/dev/null; then
  git -C "$R" cat-file -e HEAD:src/fmt.py 2>/dev/null || ng "AC4（前提）: リポジトリの pre-commit の書き換えがコミットに入っていない"
  is_block "$(stop "$R")" && ng "AC4: 関門を通した後にリポジトリの pre-commit が書き換えたコミットで差し戻した"
else ng "AC4（前提）: 証拠をそろえたのに、リポジトリの pre-commit があるコミットができない"; fi
rm "$R/.git/hooks/pre-commit"
# 同じターンで関門を通したコミットの後でも、pre-commit を飛ばしたコミット（-n）は記録されず、差し戻す
save_req "$R"; turn "$R"; echo c5 > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
git -C "$R" commit -q -m gated2 2>/dev/null || ng "AC4（前提）: 証拠をそろえたのに関門を通ったコミットができない（gated2）"
echo c6 > "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -q -n -m skipped
sha="$(git -C "$R" rev-parse --short HEAD)"; out="$(stop "$R")"
is_block "$out" || ng "AC4: pre-commit を飛ばしたコミット（$sha）を Stop が差し戻さない"
case "$out" in *"$sha"*) ;; *) ng "AC4: 差し戻しの理由に -n のコミット $sha が無い: $out" ;; esac
turn "$R"
# 同じく証拠なしなら、共通 hooks の関門がコミットを止める（前提の確認）
turn "$R"; echo c3 > "$R/src/app.py"; git -C "$R" add -A
git -C "$R" commit -q -m nogate 2>/dev/null && ng "AC4（前提）: 共通 hooks の関門が証拠なしのコミットを止めない"
reset_tree "$R"

# ---------- AC5: 未登録のリポジトリにも、一時ディレクトリの外なら関門（実際の git。親ディレクトリから git -C）----------
O="$TMP/r/unregistered"; git init -q -b feat "$O"; echo c > "$O/app.py"; git -C "$O" add -A
(cd "$TMP/r" && git -C unregistered commit -q -m x 2>/dev/null) && ng "AC5: TMPDIR の外の未登録のリポジトリで、証拠なしのコミットが通った"
IN="$TMPDIR/unregistered"; git init -q -b feat "$IN"; echo c > "$IN/app.py"; git -C "$IN" add -A
(cd "$TMPDIR" && git -C unregistered commit -q -m x 2>/dev/null) || ng "AC5: TMPDIR の中の未登録のリポジトリのコミットを止めた"

# ---------- AC6: 文書・画像など以外はすべて証拠を求める ----------
R="$(newrepo kinds)"; save_req "$R"
for f in requirements.txt go.mod uv.lock Cargo.lock Gemfile .env app/x.erb t/x.j2 prisma/schema.prisma x.jsonc BUILD.bazel Procfile; do
  turn "$R"; mkdir -p "$R/$(dirname "$f")"; echo x > "$R/$f"
  is_block "$(stop "$R")" || ng "AC6: 証拠なしの変更を差し戻さない: $f"
  reset_tree "$R"
done
for f in README.md notes.txt logo.png LICENSE; do
  turn "$R"; echo x > "$R/$f"
  is_block "$(stop "$R")" && ng "AC6: 文書だけの変更で差し戻した: $f"
  reset_tree "$R"
done

# ---------- AC7: 宣言した検証はリポジトリのトップで実行したときだけ数える ----------
R="$(newrepo top)"; save_req "$R"; n=0
try7() { # try7 <cwd> <コマンド> <数える: yes|no>
  n=$((n + 1)); turn "$R"; echo "v$n" > "$R/src/app.py"; accepted "$R"; reviewed "$R"; ran "$1" "$2"
  if is_block "$(stop "$R")"; then got=no; else got=yes; fi
  [ "$got" = "$3" ] || ng "AC7: cwd=${1#"$TMP"/} で「$2」を数える=$got（期待 $3）"
  reset_tree "$R"; }
try7 "$R" "sh tests/ok.sh" yes
try7 "$R/src" "sh tests/ok.sh" no
try7 "$R/src" "cd $R && sh tests/ok.sh" yes
try7 "$R" "cd src && sh tests/ok.sh" no
try7 "$R" "cd $R/src && sh tests/ok.sh" no

# ---------- AC8: 要件の写しは main・master の上では保存しない ----------
R="$(newrepo onmain)"
for b in main master; do
  git -C "$R" switch -q -C "$b"
  if err="$(printf 'AC1: x\n' | (cd "$R" && "$HOOK" requirements-save) 2>&1 >/dev/null)"; then ng "AC8: $b の上で requirements-save が exit 0"
  else case "$err" in *ブランチ*) ;; *) ng "AC8: $b の上での拒否の理由にブランチを切ることが無い: $err" ;; esac; fi
done
U="$TMP/r/unborn"; git init -q -b main "$U"
printf 'AC1: x\n' | (cd "$U" && "$HOOK" requirements-save) >/dev/null 2>&1 || ng "AC8: 最初のコミットの前の main で保存できない"
C=config/claude
flow="$(grep -m 1 '^流れ（' "$D/$C/CLAUDE.md" || true)"
case "$flow" in *'→ ブランチ → 要件の固定 →'*) ;; *) ng "AC8: CLAUDE.md の流れの 1 行が「ブランチ → 要件の固定」の順でない" ;; esac
grep -q '^1\. \*\*ブランチ\*\*' "$D/$C/CLAUDE.md" || ng "AC8: CLAUDE.md の手順 1 がブランチでない"
grep -q '^2\. \*\*要件の固定\*\*' "$D/$C/CLAUDE.md" || ng "AC8: CLAUDE.md の手順 2 が要件の固定でない"
dia="$(awk '/^### 流れの全体図/ { f = 1; next } f && /^```/ { n++; if (n == 2) exit; next } f && n == 1' "$D/README.md")"
bl="$(printf '%s\n' "$dia" | grep -n '→ ブランチ' | head -1 | cut -d: -f1)"; rl="$(printf '%s\n' "$dia" | grep -n '→ 要件の写しを固定' | head -1 | cut -d: -f1)"
[ -n "$bl" ] && [ -n "$rl" ] && [ "$bl" -lt "$rl" ] || ng "AC8: README の流れの図が「ブランチ → 要件の写しを固定」の順でない（$bl, $rl）"

# ---------- AC9: 保存した後に HEAD が進んだ写しは古い ----------
R="$(newrepo fresh)"; save_req "$R"
turn "$R"; echo s1 > "$R/src/app.py"; evidence "$R"; git -C "$R" add -A
git -C "$R" commit -q -m s1 2>/dev/null || ng "AC9（前提）: 証拠をそろえたのにコミットできない"
turn "$R"; echo s2 > "$R/src/app.py"; evidence "$R"; out="$(stop "$R")"
is_block "$out" || ng "AC9: コミットの後の古い写しのまま、コード変更を通した"
case "$out" in *保存し直*) ;; *) ng "AC9: 理由に保存し直すことが無い: $out" ;; esac
git -C "$R" add -A; (cd "$R" && "$HOOK" pre-commit) >/dev/null 2>&1 && ng "AC9: 古い写しのまま pre-commit が通した"
save_req "$R"   # 同じ内容で保存し直す
is_block "$(stop "$R")" && ng "AC9: 同じ内容で保存し直しても差し戻す"
(cd "$R" && "$HOOK" pre-commit) >/dev/null 2>&1 || ng "AC9: 保存し直した後に pre-commit が通さない"
reset_tree "$R"

# ---------- AC11: 宣言した検証を並列に 5 本 ----------
R="$(newrepo par)"; save_req "$R"
printf 'sh tests/p1.sh\nsh tests/p2.sh\nsh tests/p3.sh\nsh tests/p4.sh\nsh tests/p5.sh\n' > "$R/.harness-verify"
git -C "$R" add -A; env -u CLAUDECODE git -C "$R" commit -q -m decl; save_req "$R"
for round in 1 2 3 4 5; do
  turn "$R"; echo "p$round" > "$R/src/app.py"; accepted "$R"; reviewed "$R"
  for i in 1 2 3 4 5; do ran "$R" "sh tests/p$i.sh" & done; wait
  is_block "$(stop "$R")" && ng "AC11: 並列の 5 本の成功が記録されていない（$round 回目）"
  reset_tree "$R"
done

# ---------- AC2・AC12: 文書 ----------
grep -q 'WRITES\b' "$D/bin/harness-hook" && ng "AC2: bin/harness-hook に存在しない名前 WRITES がある"
grep -n 'merge-base' "$D/$C/skills/review/SKILL.md" | grep -qE 'merge-base (main|master) ' && ng "AC12: /review branch の基点が main・master の決め打ち"
grep -q 'refs/remotes/origin/HEAD' "$D/$C/skills/review/SKILL.md" || ng "AC12: /review branch が origin/HEAD の基点を使わない"

# ---------- AC13: tests/skills.sh が流れの順序の入れ替えで落ちる ----------
sh "$D/tests/skills.sh" >/dev/null 2>&1 || ng "AC13: tests/skills.sh が本物で落ちる"
T="$TMP/copy"
copy() { rm -rf "$T"; mkdir -p "$T/$C" "$T/bin"
  cp -R "$D/$C/skills" "$D/$C/agents" "$D/$C/CLAUDE.md" "$D/$C/settings.json" "$T/$C/"; cp "$D/install.sh" "$D/README.md" "$T/"; cp "$D/bin/harness-hook" "$T/bin/"; }
breaks() { # breaks <ファイル> <sed の式> <説明>
  copy; sed "$2" "$T/$1" > "$TMP/e"; cmp -s "$TMP/e" "$D/$1" && { ng "AC13（前提）: $1 を壊せていない（$3）"; return 0; }
  cp "$TMP/e" "$T/$1"; sh "$D/tests/skills.sh" "$T" >/dev/null 2>&1 && ng "AC13: 入れ替えても skills.sh が通った: $3"; return 0; }
breaks $C/CLAUDE.md '/^流れ（/s/`\/accept`（受け入れ検証）→ `\/verify`/`\/verify` → `\/accept`（受け入れ検証）/' 'CLAUDE.md の流れの 1 行で /accept と /verify'
breaks $C/CLAUDE.md '/^流れ（/s/→ `\/review` → コミット/→ コミット → `\/review`/' 'CLAUDE.md の流れの 1 行で /review とコミット'
breaks $C/CLAUDE.md '/^流れ（/s/→ `\/wrap-up`（作業ブランチの上で）→ 統合の判断/→ 統合の判断 → `\/wrap-up`（作業ブランチの上で）/' 'CLAUDE.md の流れの 1 行で /wrap-up と統合'
breaks $C/CLAUDE.md 's/^5\. \*\*検証\*\*/5. **@@**/; s/^6\. \*\*レビュー\*\*/6. **検証**/; s/^5\. \*\*@@\*\*/5. **レビュー**/' 'CLAUDE.md の手順の検証とレビュー'
breaks $C/CLAUDE.md 's/^7\. \*\*コミット\*\*/7. **@@**/; s/^8\. \*\*締め\*\*/8. **コミット**/; s/^7\. \*\*@@\*\*/7. **締め**/' 'CLAUDE.md の手順のコミットと締め'
breaks README.md 's|→ /accept |→ @@ |; s|→ /verify |→ /accept |; s|→ @@ |→ /verify |' 'README の図の /accept と /verify'
breaks README.md 's|^  → /wrap-up|  → @@|; s|^  → 統合の判断|  → /wrap-up|; s|^  → @@|  → 統合の判断|' 'README の図の /wrap-up と統合'

# ==================== 2 回目の修正（AC14〜AC24）====================
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
failed() { ev bash-failed "$1" PostToolUseFailure "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}, \"error\": \"Exit code 1\\nFAILED: x\", \"is_interrupt\": false}"; }
guard_at() { ev guard-bash "$1" PreToolUse "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": $(js "$2")}}"; }
husky() { mkdir -p "$1/.husky"; git -C "$1" config core.hooksPath .husky; }   # リポジトリ側の hooksPath: 共通 hooks は呼ばれない
side() { # side <repo> <枝> <ファイル> <内容>: main から枝を切り、コードを変えたコミットを人の操作で作って feat/x に戻る
  git -C "$1" switch -q -c "$2" main; mkdir -p "$1/$(dirname "$3")"; echo "$4" > "$1/$3"; git -C "$1" add -A
  env -u CLAUDECODE git -C "$1" commit -q -m "$2"; git -C "$1" switch -q feat/x; }
commits() { _r=$1; shift; git -C "$_r" commit -q "$@" >/dev/null 2>&1; }   # commits <repo> <git commit の引数…>: 共通 hooks（関門）を通るコミット
# 以下、競合で止まる merge・cherry-pick・revert は exit 1 になるので（set -e）、|| true を付ける

# ---------- AC14: マージ・cherry-pick・revert の途中のコミットは、自動の結果との差に証拠を求める（実際の git）----------
R="$(newrepo merge)"; save_req "$R"
side "$R" s1 src/o1.py o1; turn "$R"
git -C "$R" merge -q --no-edit s1 >/dev/null 2>&1 || ng "AC14: 競合の無いマージ（自動の結果のまま）が止まった"
side "$R" s2 src/o2.py o2; save_req "$R"; turn "$R"; git -C "$R" merge -q --no-commit s2 >/dev/null 2>&1
commits "$R" --no-edit || ng "AC14: --no-commit の後、自動の結果のままのコミットが止まった"
side "$R" s3 src/o3.py o3; save_req "$R"; turn "$R"; git -C "$R" merge -q --no-commit s3 >/dev/null 2>&1
echo extra > "$R/src/extra.py"; git -C "$R" add -A
commits "$R" --no-edit && ng "AC14: merge --no-commit の後にコードを足したコミットが証拠なしで通った"
evidence "$R"; commits "$R" --no-edit || ng "AC14: merge --no-commit の後に足した変更に証拠をそろえても通らない"
side "$R" s4 src/o4.py o4; save_req "$R"; turn "$R"; git -C "$R" merge -q --no-commit s4 >/dev/null 2>&1; git -C "$R" rm -qf src/o4.py
commits "$R" --no-edit && ng "AC14: merge --no-commit の後に取り込むコードを消したコミットが証拠なしで通った"
git -C "$R" merge --abort 2>/dev/null || true; reset_tree "$R"
side "$R" s5 src/lib.py theirs; echo ours > "$R/src/lib.py"; git -C "$R" add -A; commits "$R" -n -m ours; save_req "$R"; turn "$R"
git -C "$R" merge -q s5 >/dev/null 2>&1 || true; [ -n "$(git -C "$R" diff --name-only --diff-filter=U)" ] || ng "AC14（前提）: 競合が起きていない"
echo resolved > "$R/src/lib.py"; git -C "$R" add -A
commits "$R" --no-edit && ng "AC14: 競合を解消したマージのコミットが証拠なしで通った"
evidence "$R"; commits "$R" --no-edit || ng "AC14: 競合の解消に証拠をそろえても通らない"
side "$R" s6 src/lib.py cp; save_req "$R"; turn "$R"; git -C "$R" cherry-pick s6 >/dev/null 2>&1 || true
[ -f "$R/.git/CHERRY_PICK_HEAD" ] || ng "AC14（前提）: cherry-pick が競合で止まっていない"
echo cpres > "$R/src/lib.py"; git -C "$R" add -A
commits "$R" --no-edit && ng "AC14: 競合を解消した cherry-pick のコミットが証拠なしで通った"
evidence "$R"; commits "$R" --no-edit || ng "AC14: cherry-pick の競合の解消に証拠をそろえても通らない"
echo r2 > "$R/src/lib.py"; git -C "$R" add -A; commits "$R" -n -m r2; save_req "$R"; turn "$R"
git -C "$R" revert --no-edit HEAD~1 >/dev/null 2>&1 || true; [ -f "$R/.git/REVERT_HEAD" ] || ng "AC14（前提）: revert が競合で止まっていない"
echo rres > "$R/src/lib.py"; git -C "$R" add -A
commits "$R" --no-edit && ng "AC14: 競合を解消した revert のコミットが証拠なしで通った"
git -C "$R" revert --abort 2>/dev/null || true; reset_tree "$R"
save_req "$R"; turn "$R"; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1 || ng "AC14: 競合の無い revert（自動の結果のまま）が止まった"
# Stop の事後の確認（共通 hooks が呼ばれないリポジトリ）: 自動の結果と違うマージコミットだけを差し戻す
R="$(newrepo merge-stop)"; husky "$R"; save_req "$R"
side "$R" t1 src/o1.py o1; turn "$R"; git -C "$R" merge -q --no-edit t1 >/dev/null 2>&1
is_block "$(stop "$R")" && ng "AC14: 自動の結果のままのマージコミットを Stop が差し戻した"
side "$R" t2 src/o2.py o2; save_req "$R"; turn "$R"; git -C "$R" merge -q --no-commit t2 >/dev/null 2>&1
echo x > "$R/src/x.py"; git -C "$R" add -A; git -C "$R" commit -q --no-edit
is_block "$(stop "$R")" || ng "AC14: 自動の結果にコードを足したマージコミットを Stop が差し戻さない"
# 3 つの枝のマージ（octopus）も --no-commit の後に手を加えられる（git 2.55 で確かめた。コミットの親は 3 つ）
side "$R" t3 src/o3.py o3; side "$R" t4 src/o4.py o4; save_req "$R"; turn "$R"
git -C "$R" merge -q --no-commit t3 t4 >/dev/null 2>&1; echo y > "$R/src/y.py"; git -C "$R" add -A; git -C "$R" commit -q --no-edit
[ "$(git -C "$R" log -1 --format=%P | wc -w | tr -d ' ')" = 3 ] || ng "AC14（前提）: 3 つの親のマージコミットができていない"
is_block "$(stop "$R")" || ng "AC14: 自動の結果にコードを足した 3 つの親のマージコミットを Stop が差し戻さない"
# merge-tree が自動の結果を求められない 2 つの親のマージ（無関係な履歴）も、最初の親との差で見る
git -C "$R" switch -q --orphan t6; git -C "$R" rm -rqf . >/dev/null 2>&1 || true; echo o > "$R/o6.md"; git -C "$R" add -A
env -u CLAUDECODE git -C "$R" commit -q -m t6; git -C "$R" switch -q feat/x; save_req "$R"; turn "$R"
git -C "$R" merge -q --no-commit --allow-unrelated-histories t6 >/dev/null 2>&1; echo z > "$R/src/z.py"; git -C "$R" add -A; git -C "$R" commit -q --no-edit
is_block "$(stop "$R")" || ng "AC14: merge-tree で求められないマージに足したコードを Stop が差し戻さない"
# ターン開始時の枝の先端から届くコミットは除く（コミット時刻がターンより後でも）
git -C "$R" switch -q -c t5 main; echo f > "$R/src/f.py"; git -C "$R" add -A
GIT_COMMITTER_DATE="$(($(date +%s) + 3600)) +0000" env -u CLAUDECODE git -C "$R" commit -q -m future; git -C "$R" switch -q feat/x
save_req "$R"; turn "$R"; git -C "$R" merge -q --no-edit t5 >/dev/null 2>&1
is_block "$(stop "$R")" && ng "AC14: ターン開始時の枝の先端から届くコミットを Stop が差し戻した"

# ---------- AC15: 共通の pre-commit が呼ばれないリポジトリでは、Bash の git commit・git push の前に判定する ----------
R="$(newrepo pre)"; husky "$R"; save_req "$R"
B="$TMP/r/pre.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"; env -u CLAUDECODE git -C "$R" push -q origin feat/x
turn "$R"; echo c1 > "$R/src/app.py"
for c in 'git commit -am x' 'git add -A && git commit -m x' 'git add -A; git commit -m x' "git -C $R commit -am x" 'cd src && git commit -am x'; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC15: 証拠なしのコード変更の git commit を拒否しない: $c"
done
is_deny "$(guard_at "$R" 'git log -1')" && ng "AC15: git commit でないコマンドを拒否した"
git -C "$R" add -A; evidence "$R"
is_deny "$(guard_at "$R" 'git commit -m gated')" && ng "AC15: 証拠がそろった git commit を拒否した"
git -C "$R" commit -q -m gated; ran "$R" 'git commit -m gated'   # Claude Code の Bash と同じく、許可された後に実行し PostToolUse を送る
is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC15: 判定を通った（証拠のそろった）コミットの push を拒否した"
is_block "$(stop "$R")" && ng "AC15: 判定を通った（証拠のそろった）コミットを Stop が差し戻した"
env -u CLAUDECODE git -C "$R" push -q origin feat/x
save_req "$R"; turn "$R"; echo c2 > "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -q -m unguarded   # 判定を通らないコミット
for c in 'git push' 'git push origin feat/x' 'git status && git push'; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC15: 関門を通っていないコミットの push を拒否しない: $c"
done
stop "$R" >/dev/null; turn "$R"   # 次のターンでも、そのコミットはリモートに無く、関門を通っていない
is_deny "$(guard_at "$R" 'git push origin feat/x')" || ng "AC15: 前のターンの、関門を通っていないコミット（リモートに無い）の push を拒否しない"
# 関門を通っていないコミットが別のローカルブランチにあれば、元のブランチに戻ってからの push・push --all も拒否する
R="$(newrepo pre-br)"; husky "$R"; B="$TMP/r/pre-br.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"
env -u CLAUDECODE git -C "$R" push -q origin feat/x; save_req "$R"; turn "$R"
git -C "$R" switch -q -c feat/y; echo u > "$R/src/u.py"; git -C "$R" add -A; git -C "$R" commit -q -m unguarded-y; git -C "$R" switch -q feat/x
stop "$R" >/dev/null; turn "$R"
for c in 'git push origin feat/x' 'git push --all origin' 'git push origin HEAD'; do
  is_deny "$(guard_at "$R" "$c")" || ng "AC15: 別のブランチにある、関門を通っていないコミットがあるのに push を拒否しない: $c"
done
git -C "$R" branch -q -D feat/y; turn "$R"
is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC15: 関門を通っていないコミットを消した後の push を拒否した"
N="$(newrepo pre-common)"; save_req "$N"; turn "$N"; echo c > "$N/src/app.py"; git -C "$N" add -A
is_deny "$(guard_at "$N" 'git commit -m x')" && ng "AC15: 共通の pre-commit が呼ばれるリポジトリで、Bash の git commit を拒否した"
# 証拠の付いた作業ツリーと違う内容（ステージだけ違う・一部だけステージ）のコミットは、判定を通ったものとして扱わない
# （共通の pre-commit はステージした内容で見て止める。husky 型でも、前で拒否するか、Stop が差し戻すか、push を拒否する）
unverified_commit() { # unverified_commit <名前> <説明> <git のコマンド>: 判定 → 実行 → PostToolUse → 作業ツリーを HEAD に戻す → Stop・次のターンの push
  R="$(newrepo "$1")"; husky "$R"; B="$TMP/r/$1.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"
  env -u CLAUDECODE git -C "$R" push -q origin feat/x; save_req "$R"; turn "$R"; shift; _d=$1; shift
  "$@"; is_deny "$(guard_at "$R" "$CMD")" && return 0
  (cd "$R" && sh -c "$CMD") >/dev/null 2>&1; ran "$R" "$CMD"; reset_tree "$R"
  is_block "$(stop "$R")" && return 0; turn "$R"
  is_deny "$(guard_at "$R" 'git push origin feat/x')" || ng "AC15: 証拠の無い内容のコミットを判定が通し、Stop も push も止めない（$_d）"; }
stage_bad() { echo BAD > "$R/src/app.py"; git -C "$R" add src/app.py; echo GOOD > "$R/src/app.py"; evidence "$R"; CMD='git commit -q -m x'; }
unverified_commit pre-stage "ステージした BAD と、証拠の付いた作業ツリーの GOOD" stage_bad
part() { echo k1 > "$R/src/app.py"; echo k2 > "$R/src/b.py"; evidence "$R"; CMD='git add src/app.py && git commit -q -m x'; }
unverified_commit pre-part "証拠の付いた作業ツリーの一部だけのコミット" part
# 記録してよい読むだけの git（diff・show など）も、作業ツリーを書き換えうる（--output）。書き換えた内容のコミットは通さない
diffout() { echo GOOD > "$R/src/app.py"; git -C "$R" add src/app.py; echo GOOD2 > "$R/src/app.py"; evidence "$R"; CMD='git diff --output=src/app.py && git commit -q -am x'; }
unverified_commit pre-diffout "git diff --output で作業ツリーを書き換えてから commit -am" diffout
# 逆に、証拠の付いた内容どおりのコミットは、関門を通ったものとして扱う（判定・Stop・次のターンの push のどれも止めない）
gated_commit() { # gated_commit <名前> <説明> <git のコマンド>: 写しより前からある未追跡の scratch.py を残し、src/app.py に証拠を付けてコミット
  R="$(newrepo "$1")"; husky "$R"; B="$TMP/r/$1.git"; git init -q --bare "$B"; git -C "$R" remote add origin "$B"
  env -u CLAUDECODE git -C "$R" push -q origin feat/x; echo mine > "$R/scratch.py"; turn "$R"; save_req "$R"; turn "$R"
  echo a > "$R/src/app.py"; git -C "$R" add src/app.py; evidence "$R"
  is_deny "$(guard_at "$R" "$3")" && ng "AC15: 証拠どおりのコミットを拒否した（$2）"
  (cd "$R" && sh -c "$3") >/dev/null 2>&1; ran "$R" "$3"
  is_block "$(stop "$R")" && ng "AC15: 証拠どおりのコミットを Stop が差し戻した（$2）"
  turn "$R"; is_deny "$(guard_at "$R" 'git push origin feat/x')" && ng "AC15: 証拠どおりのコミットの push を拒否した（$2）"; return 0; }
gated_commit pre-ok "写しより前からある未追跡のファイルを残した部分コミット（AC17）" 'git add src/app.py && git commit -q -m x'
gated_commit pre-heredoc "メッセージをヒアドキュメントで渡す（E2E で agent が使った形）" "git commit -q -F - <<'EOF'
feat: x
EOF"
gated_commit pre-heredoc-log "add・status・ヒアドキュメントの commit・log を 1 つのコマンドで（E2E の最初のコミットの形）" "git add src/app.py && git status --short && git commit -q -F - <<'EOF'
feat: x

Body.
EOF
git log --oneline -1"

# ---------- AC16: 報告の版が SubagentStop の時点の版と一致するときだけ記録する ----------
R="$(newrepo ver)"; save_req "$R"
try16() { # try16 <説明> <期待: ok|ng>: ステージしてコミットを試し、期待と違えば失敗
  git -C "$R" add -A; if commits "$R" -m "$1"; then got=ok; else got=ng; git -C "$R" reset -q; fi
  [ "$got" = "$2" ] || ng "AC16: $1（コミット: $got、期待 $2）"; reset_tree "$R"; }
turn "$R"; echo a > "$R/src/app.py"; v="$(ver "$R")"; echo a2 > "$R/src/app.py"; ran "$R" "sh tests/ok.sh"; accepted_v "$R" "$v"; reviewed_v "$R" "$v"
try16 "報告の後にコードを編集した（報告の版は古い）" ng
turn "$R"; echo b > "$R/src/app.py"; ran "$R" "sh tests/ok.sh"; accepted "$R"
ev review-done "$R" SubagentStop "{\"agent_type\": \"reviewer\", \"last_assistant_message\": $(js "## 判定
仕様適合: 承認
テスト: 承認
品質・保守性: 承認")}"
try16 "レビューの報告に版の行が無い" ng
turn "$R"; echo c > "$R/src/app.py"; v="$(ver "$R")"; echo doc > "$R/NOTES.md"; ran "$R" "sh tests/ok.sh"; accepted_v "$R" "$v"; reviewed_v "$R" "$v"
try16 "報告の版との違いが文書だけ" ok
save_req "$R"; turn "$R"; echo d > "$R/src/app.py"; ran "$R" "sh tests/ok.sh"; accepted "$R"; reviewed "$R"
try16 "報告の版が今の版" ok

# ---------- AC17: 写しの保存の時点からある未追跡のコードは、変えていなければ指紋から除く ----------
R="$(newrepo base)"; echo mine > "$R/scratch.py"; turn "$R"; save_req "$R"
turn "$R"; is_block "$(stop "$R")" && ng "AC17: 写しの前からある未追跡のコードだけで Stop が差し戻した"
turn "$R"; echo a > "$R/src/app.py"; evidence "$R"; git -C "$R" add src/app.py
commits "$R" -m partial || ng "AC17: 写しの前からある未追跡のコードを残した部分コミットが止まった"
save_req "$R"; turn "$R"; echo b > "$R/src/app.py"; evidence "$R"; git -C "$R" add src/app.py scratch.py
commits "$R" -m withscratch && ng "AC17: 写しの前からある未追跡のコードを証拠なしでコミットに含められた"
git -C "$R" reset -q; turn "$R"; echo changed > "$R/scratch.py"
is_block "$(stop "$R")" || ng "AC17: 写しの後に変えた未追跡のコードを Stop が差し戻さない"
# 写しの前からある未追跡のコードも、ステージしてから証拠をそろえればコミットできる
R="$(newrepo base-staged)"; echo mine > "$R/scratch.py"; turn "$R"; save_req "$R"
turn "$R"; echo a > "$R/src/app.py"; git -C "$R" add src/app.py scratch.py; evidence "$R"
commits "$R" -m withscratch || ng "AC17: 写しの前からある未追跡のコードをステージして証拠をそろえても、コミットが止まった"

# ---------- AC18: テストを走らせるコマンドの失敗を harness-red-log に記録する ----------
R="$(newrepo red)"; save_req "$R"; turn "$R"; LOG="$R/.git/harness-red-log"
logged() { grep -Fqx "  \$ $1" "$LOG" 2>/dev/null; }
for c in 'python manage.py test' 'bin/rails test' 'xcodebuild test -scheme App' 'bazel test //...' 'node tests/x.test.js' 'uv run python tests/x.py' 'stack test'; do
  failed "$R" "$c" >/dev/null; logged "$c" || ng "AC18: テストを走らせるコマンドの失敗を記録しない: $c"
done
for c in 'grep -rn foo tests/' 'find tests -name x' 'ls tests' 'cat tests/x.py' 'git diff tests/' 'wc -l tests/a.py'; do
  failed "$R" "$c" >/dev/null; logged "$c" && ng "AC18: 読むだけのコマンドの失敗を記録した: $c"
done
echo v > "$R/src/app.py"; evidence "$R"; failed "$R" 'node tests/x.test.js' >/dev/null
is_block "$(stop "$R")" && ng "AC18: 検証コマンドでないテストの失敗で「検証済み」が消えた"
failed "$R" 'sh tests/ok.sh' >/dev/null
is_block "$(stop "$R")" || ng "AC18: 宣言した検証の失敗で「検証済み」が消えない"
reset_tree "$R"

# ---------- AC20: 環境の差し替えの git は拒否、読むだけの git config は通す ----------
R="$(newrepo env)"
for c in 'env -i git commit -m x' 'env -i PATH="$PATH" git commit -m x' '/usr/bin/env -i git commit -m x' 'HOME=/tmp git commit -m x' \
  'HOME= git commit -m x' 'env HOME=/tmp git commit -m x' 'XDG_CONFIG_HOME=/tmp git commit -m x' 'XDG_CONFIG_HOME= git commit -m x' \
  'git config --unset core.hooksPath' 'git -c core.hooksPath= commit -m x' 'git config core.hooksPath /tmp/x' 'git config core.hooksPath ""' \
  'env - git commit -m x' 'HOME=/tmp command git commit -m x' 'XDG_CONFIG_HOME=/tmp command git commit -m x'; do
  is_deny "$(guard "$c")" || ng "AC20: 拒否しない: $c"
done
for c in 'git config core.hooksPath' 'git config --get core.hooksPath' 'GIT_CONFIG_NOSYSTEM=1 git status'; do
  is_deny "$(guard "$c")" && ng "AC20: 読むだけのコマンドを拒否した: $c"
done

# ---------- AC21: テストのディレクトリの設定ファイルは「テストの追加」とみなさない ----------
R="$(newrepo tconf)"; save_req "$R"
for f in tests/conftest.py tests/__init__.py tests/pytest.ini tests/jest.config.js tests/unit/conftest.py; do
  turn "$R"; mkdir -p "$R/$(dirname "$f")"; echo x > "$R/$f"; git -C "$R" add -A
  is_block "$(stop "$R")" || ng "AC21: 証拠なしの $f の追加を Stop が差し戻さない"
  commits "$R" -m "$f" && ng "AC21: 証拠なしの $f の追加をコミットできた"
  reset_tree "$R"
done
turn "$R"; echo x > "$R/tests/test_new.py"; git -C "$R" add -A
is_block "$(stop "$R")" && ng "AC21: テストの追加だけで Stop が差し戻した"
commits "$R" -m t || ng "AC21: テストの追加だけのコミットが止まった"

# ---------- AC19・AC22・AC23・AC24: 文書 ----------
step9="$(awk '/^9\. \*\*統合\*\*/ { f = 1 } f && /^$/ { exit } f' "$D/$C/CLAUDE.md")"
case "$step9" in *--ff-only*) ;; *) ng "AC19: CLAUDE.md の統合の手順に fast-forward（--ff-only）が無い" ;; esac
# ARK-51 AC45（ユーザーが「関門で強制する」を選んだ）で、基点の取り込みは rebase と reset --soft でまとめて検証し直す手順に変えた
case "$step9" in *'git rebase <基点>'*作業ブランチの上*'git reset --soft <基点>'*) ;; *) ng "AC19: CLAUDE.md の統合の手順に、基点の上に載せ直し（作業ブランチの上で競合を解消し）、reset --soft でまとめて検証し直す手順が無い" ;; esac
grep -Eq 'fast-forward|ff-only' "$D/README.md" || ng "AC19: README に、統合で fast-forward にならないときの手順が無い"
red="$(awk '/^1\. \*\*RED\*\*/ { f = 1; next } f && /^[0-9]+\. / { exit } f' "$D/$C/skills/tdd/SKILL.md")"
case "$red" in *パイプ*記録*) ;; *) ng "AC22: /tdd の RED に、パイプを付けると失敗が記録されないことが無い" ;; esac
grep -q 'husky)' "$D/tests/e2e-flow.sh" && grep -q 'config core.hooksPath .husky' "$D/tests/e2e-flow.sh" \
  || ng "AC23: tests/e2e-flow.sh に husky の場面（リポジトリ側の core.hooksPath）が無い"
for s in 要件の固定 検証 コミット 統合; do
  awk -v s="$s" '$0 ~ "^[0-9]+\\. \\*\\*" s "\\*\\*" { getline n; exit !(n ~ /^   - /) }' "$D/$C/CLAUDE.md" \
    || ng "AC24: CLAUDE.md の手順「$s」が下位の箇条に分かれていない"
done

[ "$fail" = 0 ] && echo "harness-ark51: ok"
[ "$fail" = 0 ]
