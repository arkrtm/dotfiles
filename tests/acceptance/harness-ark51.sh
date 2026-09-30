#!/bin/sh
# 受け入れ検査（ARK-51）: 厳しい採点の指摘を直したもの（AC1〜AC13）。
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
accepted() { ev review-done "$1" SubagentStop "{\"agent_type\": \"acceptor\", \"last_assistant_message\": $(js '受け入れ検証した版: x
## 条件ごとの結果
- [AC1] 合格 — a → b
## 判定
受け入れ: 合格')}"; }
reviewed() { ev review-done "$1" SubagentStop "{\"agent_type\": \"reviewer\", \"last_assistant_message\": $(js '## 判定
仕様適合: 承認
テスト: 承認
品質・保守性: 承認')}"; }
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

[ "$fail" = 0 ] && echo "harness-ark51: ok"
[ "$fail" = 0 ]
