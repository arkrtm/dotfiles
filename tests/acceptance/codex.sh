#!/bin/sh
# codex-review の受け入れ検査: 偽の codex を PATH の先頭に置き、使い方の誤りは終了コード 2、
# plan と branch は codex exec を読み取り専用の sandbox・effort xhigh で、計画書のパス／<ベース>...HEAD と VERDICT を含むプロンプトで呼ぶこと、
# branch は結果を <共通ディレクトリ>/codex-review/<日時>-branch-<merge-base>-<HEAD>.md に保存すること
#   sh tests/acceptance/codex.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/codex.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CR="$ROOT/bin/codex-review"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# 偽の codex: 引数を 1 行ずつ args に、標準入力を stdin に書く（codex exec は標準入力が端末でないと入力の終わりを待つ）。
# -o <file> を受けたら、そのファイルに最後のメッセージとして VERDICT: PASS を書く
cat > "$T/bin/codex" <<SH
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done > "$T/args"
cat > "$T/stdin"
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && printf '指摘なし\nVERDICT: PASS\n' > "\$2"; shift; done
# MOVE があれば、レビューの途中で HEAD を動かす
[ -z "\${MOVE:-}" ] || git commit -q --allow-empty -m moved
# FAILRC があれば、結果を書いた後に異常終了する
[ -z "\${FAILRC:-}" ] || exit 1
SH
chmod +x "$T/bin/codex"
export PATH="$T/bin:$PATH"
cd "$T"
# branch は git のリポジトリの中で使う: main と、そこから 1 コミット進めた作業ブランチ（dev は別のベース）
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git init -q -b main && git commit -q --allow-empty -m base && git branch dev && git checkout -q -b feature/x && git commit -q --allow-empty -m work
printf '%s\n' bin args stdin x.md err >> .git/info/exclude # 検査の道具は作業ツリーの変更に数えない
exec </dev/null # 偽の codex が呼んだ側の端末を待たないように（標準入力を渡すかは下の echo leaked で確かめる）

for args in "" foo plan "plan missing.md"; do
  # shellcheck disable=SC2086 # 語に分けて渡す
  sh "$CR" $args 2>"$T/err" >/dev/null; rc=$?
  [ "$rc" = 2 ] && grep -q usage "$T/err" && [ ! -e "$T/args" ] && ok "codex-review ${args:-（引数なし）} は 2 で使い方を出す" || ng "codex-review ${args:-（引数なし）}: rc=$rc err=$(cat "$T/err")"
done

has() { grep -qx -- "$1" "$T/args"; }
# フックを止める（tinymemory の記憶を入れず、差分と計画書だけでレビューさせる）
common() { has exec && has --sandbox && has read-only && has model_reasoning_effort=xhigh && has features.hooks=false; }
echo plan > "$T/x.md"
sh "$CR" plan x.md; rc=$?
[ "$rc" = 0 ] && common && grep -q 'x.md' "$T/args" && ok "plan は計画書のパスを読み取り専用・effort xhigh で渡す" || ng "plan: rc=$rc $(cat "$T/args" 2>/dev/null)"
has --skip-git-repo-check && ok "plan は git のリポジトリの外でも動く（--skip-git-repo-check）" || ng "plan に --skip-git-repo-check が無い"
rm -f "$T/args"; sh "$CR" branch
common && grep -qF "$(git merge-base main HEAD)...$(git rev-parse HEAD)" "$T/args" && grep -q 'VERDICT: PASS' "$T/args" \
  && ok "branch は <merge-base>...<HEAD> を SHA で固定して VERDICT と渡す" || ng "branch: $(cat "$T/args" 2>/dev/null)"
saved="$(ls "$T/.git/codex-review/"*-branch-"$(git merge-base main HEAD)-$(git rev-parse HEAD)".md 2>/dev/null)"
[ "$(printf '%s\n' "$saved" | grep -c .)" = 1 ] && [ "$(tail -n 1 "$saved")" = 'VERDICT: PASS' ] \
  && ok "branch は結果を codex-review/<日時>-branch-<merge-base>-<HEAD>.md に保存する" || ng "branch の結果の保存: $(ls -R "$T/.git/codex-review" 2>&1)"
rm -f "$T/args"; echo leaked | sh "$CR" branch
[ -e "$T/stdin" ] && [ ! -s "$T/stdin" ] && ok "codex に標準入力を渡さない（入力の終わりを待って止まらない）" || ng "codex に標準入力が渡る: $(cat "$T/stdin" 2>/dev/null)"
rm -f "$T/args"; sh "$CR" branch dev
grep -q 'dev との差分' "$T/args" && ok "branch <ベース> はそのベースを使う" || ng "branch dev: $(cat "$T/args" 2>/dev/null)"

# Codex が結果を書いた後に異常終了したら、結果を残さない（統合に使わせない）
rm -rf "$T/.git/codex-review"; FAILRC=1 sh "$CR" branch 2>"$T/err"; rc=$?
[ "$rc" != 0 ] && [ -z "$(ls -A "$T/.git/codex-review" 2>/dev/null)" ] \
  && ok "Codex が異常終了したら結果を残さない" || ng "異常終了: rc=$rc $(ls -A "$T/.git/codex-review" 2>&1)"
# 未コミットの変更があると、レビューする内容がコミットと違うので実行しない
git config status.showUntrackedFiles no
echo dirty > d; rm -f "$T/args"; sh "$CR" branch 2>"$T/err"; rc=$?
[ "$rc" != 0 ] && [ ! -e "$T/args" ] && ok "未追跡のファイルがあれば branch のレビューをしない（status.showUntrackedFiles=no でも）" || ng "未追跡のファイル: rc=$rc $(cat "$T/err")"
rm -f d; git config --unset status.showUntrackedFiles
# レビューの途中で HEAD が変わったら、結果を元のコミットの名前で残さない
rm -rf "$T/.git/codex-review"; h0="$(git rev-parse HEAD)"
MOVE=1 sh "$CR" branch 2>"$T/err"; rc=$?
[ "$rc" != 0 ] && ! ls "$T/.git/codex-review/"*"-$h0.md" >/dev/null 2>&1 \
  && ok "レビューの途中で HEAD が変わったら結果を保存しない" || ng "途中で HEAD が変わった: rc=$rc $(ls "$T/.git/codex-review" 2>&1)"
git reset -q --hard "$h0"

[ "$fail" = 0 ] && echo "acceptance codex: ok"
[ "$fail" = 0 ]
