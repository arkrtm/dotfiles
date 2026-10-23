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
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done > "%s/args"\n' "$T" > "$T/bin/codex"; chmod +x "$T/bin/codex"
export PATH="$T/bin:$PATH"
cd "$T"

for args in "" foo plan "plan missing.md"; do
  # shellcheck disable=SC2086 # 語に分けて渡す
  sh "$CR" $args 2>"$T/err" >/dev/null; rc=$?
  [ "$rc" = 2 ] && grep -q usage "$T/err" && [ ! -e "$T/args" ] && ok "codex-review ${args:-（引数なし）} は 2 で使い方を出す" || ng "codex-review ${args:-（引数なし）}: rc=$rc err=$(cat "$T/err")"
done

has() { grep -qx -- "$1" "$T/args"; }
common() { has exec && has --sandbox && has read-only && has model_reasoning_effort=high; }
echo plan > "$T/x.md"
sh "$CR" plan x.md; rc=$?
[ "$rc" = 0 ] && common && grep -q 'x.md' "$T/args" && ok "plan は計画書のパスを読み取り専用・effort high で渡す" || ng "plan: rc=$rc $(cat "$T/args" 2>/dev/null)"
rm -f "$T/args"; sh "$CR" branch
common && grep -q 'main\.\.\.HEAD' "$T/args" && grep -q 'VERDICT: PASS' "$T/args" && ok "branch は main...HEAD と VERDICT を渡す" || ng "branch: $(cat "$T/args" 2>/dev/null)"
rm -f "$T/args"; sh "$CR" branch dev
grep -q 'dev\.\.\.HEAD' "$T/args" && ok "branch <ベース> はそのベースを使う" || ng "branch dev: $(cat "$T/args" 2>/dev/null)"

[ "$fail" = 0 ] && echo "acceptance codex: ok"
[ "$fail" = 0 ]
