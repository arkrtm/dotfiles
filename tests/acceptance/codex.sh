#!/bin/sh
# codex-review の受け入れ検査（ARK-87）: 偽の codex を PATH の先頭に置き、使い方の誤りは終了コード 2、
# plan と branch は codex exec を読み取り専用の sandbox・effort high で、計画書のパス／<ベース>...HEAD と VERDICT を含むプロンプトで呼ぶこと
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
# 偽の codex: 引数を 1 行ずつ args に、標準入力を stdin に書く（codex exec は標準入力が端末でないと入力の終わりを待つ）
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done > "%s/args"\ncat > "%s/stdin"\n' "$T" "$T" > "$T/bin/codex"; chmod +x "$T/bin/codex"
export PATH="$T/bin:$PATH"
cd "$T"
exec </dev/null # 偽の codex が呼んだ側の端末を待たないように（標準入力を渡すかは下の echo leaked で確かめる）

for args in "" foo plan "plan missing.md"; do
  # shellcheck disable=SC2086 # 語に分けて渡す
  sh "$CR" $args 2>"$T/err" >/dev/null; rc=$?
  [ "$rc" = 2 ] && grep -q usage "$T/err" && [ ! -e "$T/args" ] && ok "codex-review ${args:-（引数なし）} は 2 で使い方を出す" || ng "codex-review ${args:-（引数なし）}: rc=$rc err=$(cat "$T/err")"
done

has() { grep -qx -- "$1" "$T/args"; }
# フックを止める（tinymemory の記憶を入れず、差分と計画書だけでレビューさせる）
common() { has exec && has --sandbox && has read-only && has model_reasoning_effort=high && has features.hooks=false; }
echo plan > "$T/x.md"
sh "$CR" plan x.md; rc=$?
[ "$rc" = 0 ] && common && grep -q 'x.md' "$T/args" && ok "plan は計画書のパスを読み取り専用・effort high で渡す" || ng "plan: rc=$rc $(cat "$T/args" 2>/dev/null)"
has --skip-git-repo-check && ok "plan は git のリポジトリの外でも動く（--skip-git-repo-check）" || ng "plan に --skip-git-repo-check が無い"
rm -f "$T/args"; sh "$CR" branch
common && grep -q 'main\.\.\.HEAD' "$T/args" && grep -q 'VERDICT: PASS' "$T/args" && ok "branch は main...HEAD と VERDICT を渡す" || ng "branch: $(cat "$T/args" 2>/dev/null)"
rm -f "$T/args"; echo leaked | sh "$CR" branch
[ -e "$T/stdin" ] && [ ! -s "$T/stdin" ] && ok "codex に標準入力を渡さない（入力の終わりを待って止まらない）" || ng "codex に標準入力が渡る: $(cat "$T/stdin" 2>/dev/null)"
rm -f "$T/args"; sh "$CR" branch dev
grep -q 'dev\.\.\.HEAD' "$T/args" && ok "branch <ベース> はそのベースを使う" || ng "branch dev: $(cat "$T/args" 2>/dev/null)"

[ "$fail" = 0 ] && echo "acceptance codex: ok"
[ "$fail" = 0 ]
