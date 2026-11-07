#!/bin/sh
# codex-review の受け入れ検査: 偽の codex を PATH の先頭に置き、使い方の誤りは終了コード 2、
# plan と branch は codex exec を読み取り専用の sandbox・effort xhigh で、計画書のパス／<ベース>...HEAD と VERDICT を含むプロンプトで呼ぶこと、
# branch は結果を <共通ディレクトリ>/codex-review/<日時>-branch-<merge-base>-<HEAD>.md に保存すること、
# 依頼文に「直す」と「参考」の仕分けの規則を含めること、
# 2 回目からは、同じ merge-base への結果のうち今の HEAD の祖先で最新のものの本文と <その HEAD>...<HEAD> で再レビューを依頼し、無ければ全体。前回を読めなければ止まること
#   sh tests/acceptance/codex.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/codex.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CR="$ROOT/bin/codex-review"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
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
# 仕分けの規則（「直す」と「参考」）を依頼文に含む
triage() { grep -qF '「直す」と「参考」に分けて' "$T/args" && grep -qF '実際には起こりにくい入力や環境は「参考」' "$T/args"; }
# 全体のレビュー: 再レビューの語が無く、仕分けの規則と「直す」が無ければ PASS
full() { ! grep -qF '前回の「直す」' "$T/args" && triage && grep -qF '「直す」の指摘がなければ「VERDICT: PASS」' "$T/args"; }
# フックを止める（tinymemory の記憶を入れず、差分と計画書だけでレビューさせる）
common() { has exec && has --sandbox && has read-only && has model_reasoning_effort=xhigh && has features.hooks=false; }
echo plan > "$T/x.md"
sh "$CR" plan x.md; rc=$?
[ "$rc" = 0 ] && common && grep -q 'x.md' "$T/args" && ok "plan は計画書のパスを読み取り専用・effort xhigh で渡す" || ng "plan: rc=$rc $(cat "$T/args" 2>/dev/null)"
has --skip-git-repo-check && ok "plan は git のリポジトリの外でも動く（--skip-git-repo-check）" || ng "plan に --skip-git-repo-check が無い"
triage && ok "plan は仕分けの規則を渡す" || ng "plan に仕分けの規則が無い: $(cat "$T/args" 2>/dev/null)"
rm -f "$T/args"; sh "$CR" branch
common && grep -qF "$(git merge-base main HEAD)...$(git rev-parse HEAD)" "$T/args" && grep -q 'VERDICT: PASS' "$T/args" \
  && ok "branch は <merge-base>...<HEAD> を SHA で固定して VERDICT と渡す" || ng "branch: $(cat "$T/args" 2>/dev/null)"
full && ok "branch の初回は全体のレビューを、仕分けの規則と「直す」が無ければ PASS で依頼する" || ng "branch の初回: $(cat "$T/args" 2>/dev/null)"
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

# 2 回目から: 同じ比較元への結果のうち、今の HEAD の祖先で最新のもの（今の HEAD の結果は除く）を前回とし、その本文と <前回の HEAD>...<HEAD> だけを見させる。
# 保存先は codex-review と同じく git に聞く
d="$(git rev-parse --path-format=absolute --git-common-dir)/codex-review"; from="$(git merge-base main HEAD)"
rm -rf "$d"; mkdir -p "$d"
# 前回は「直す」「参考」の分けが無い形の FAIL（分ける前の版で作った結果）
printf '前回の指摘 A\nVERDICT: FAIL\n' > "$d/20000101-000000-branch-$from-$h0.md"
# 共通ディレクトリはほかの worktree と共有する: 別のブランチのもっと新しい結果は使わない
other="$(git commit-tree -p "$from" -m other "$from^{tree}")"
printf '別のブランチの指摘\nVERDICT: PASS\n' > "$d/20991231-235959-branch-$from-$other.md"
git commit -q --allow-empty -m fix; h1="$(git rev-parse HEAD)"
# again <前回の本文の 1 行> <前回の HEAD> <今の HEAD>: 再レビューの依頼（前回の本文を依頼文に入れ、分けが無い前回は仕分け直させる）
again() { grep -qxF "$1" "$T/args" && grep -qF "$2...$3" "$T/args" && ! grep -qF "$from...$3" "$T/args" && ! grep -qF '別のブランチの指摘' "$T/args" \
  && grep -qF '前回の「直す」' "$T/args" && grep -qF '仕分け直して' "$T/args" && triage && grep -qF 'VERDICT: PASS' "$T/args"; }
rm -f "$T/args"; sh "$CR" branch
again '前回の指摘 A' "$h0" "$h1" && ok "2 回目は前回の本文と <前回の HEAD>...<HEAD> の再レビュー（別のブランチの新しい結果は使わない）" || ng "2 回目: $(cat "$T/args" 2>/dev/null)"
rm -f "$T/args"; sh "$CR" branch
again '前回の指摘 A' "$h0" "$h1" && ok "同じ HEAD でやり直しても、今の HEAD の結果は前回に使わない" || ng "同じ HEAD でやり直し: $(cat "$T/args" 2>/dev/null)"
git commit -q --allow-empty -m fix2; h2="$(git rev-parse HEAD)"
rm -f "$T/args"; sh "$CR" branch
again '指摘なし' "$h1" "$h2" && ok "3 回目は、保存された再レビューの結果（祖先で最新）を前回にする" || ng "3 回目: $(cat "$T/args" 2>/dev/null)"
# 最後の行が VERDICT: PASS/FAIL でない結果（空・途中で終わった本文）は前回にしない: より古い VERDICT 付きの祖先の結果で再レビューする
printf 'レビューを完了できませんでした\n' > "$d/20991231-235957-branch-$from-$h1.md"; : > "$d/20991231-235958-branch-$from-$h1.md"
rm -f "$T/args"; sh "$CR" branch
again '指摘なし' "$h1" "$h2" && ok "最後の行に VERDICT が無い（空を含む）結果は前回にせず、古い VERDICT 付きの結果で再レビューする" || ng "VERDICT 無しの前回: $(cat "$T/args" 2>/dev/null)"
rm -f "$d/20991231-235957-branch-$from-$h1.md" "$d/20991231-235958-branch-$from-$h1.md"
# VERDICT 付きの祖先の結果が無ければ全体のレビュー
mkdir -p "$d.keep"; mv "$d"/*-branch-"$from"-"$h0".md "$d"/*-branch-"$from"-"$h1".md "$d.keep/"
printf '本文だけ\n' > "$d/20991231-235957-branch-$from-$h1.md"
rm -f "$T/args"; sh "$CR" branch
full && grep -qF "$from...$h2" "$T/args" && ok "VERDICT 付きの祖先の結果が無ければ全体のレビュー" || ng "VERDICT 付きが無い: $(cat "$T/args" 2>/dev/null)"
rm -f "$d/20991231-235957-branch-$from-$h1.md"; mv "$d".keep/* "$d/"; rmdir "$d.keep"
# 前回の結果を読めない（ここではディレクトリ）なら、codex を呼ばず、保存もせずに失敗する
mkdir "$d/20991231-235958-branch-$from-$h1.md"; n0="$(ls -A "$d" | wc -l)"
rm -f "$T/args"; sh "$CR" branch 2>"$T/err"; rc=$?
[ "$rc" != 0 ] && [ ! -e "$T/args" ] && [ "$(ls -A "$d" | wc -l)" = "$n0" ] && ok "前回の結果を読めなければ、codex を呼ばず保存もしない" || ng "前回を読めない: rc=$rc $(cat "$T/err") $(ls -A "$d")"
rmdir "$d/20991231-235958-branch-$from-$h1.md"
# 比較元（merge-base）が変われば、前回の結果があっても全体のレビュー
rm -f "$T/args"; sh "$CR" branch "$h0"
full && grep -qF "$h0...$h2" "$T/args" && ok "比較元が変われば全体のレビュー" || ng "比較元が変わった: $(cat "$T/args" 2>/dev/null)"
# 履歴を書き換えて（rebase など）、保存のどの HEAD も祖先でなくなれば全体のレビュー
git reset -q --hard "$from"; git commit -q --allow-empty -m rewritten; h3="$(git rev-parse HEAD)"
rm -f "$T/args"; sh "$CR" branch
full && grep -qF "$from...$h3" "$T/args" && ok "履歴を書き換えて前回の HEAD が祖先でなくなれば全体のレビュー" || ng "履歴の書き換え: $(cat "$T/args" 2>/dev/null)"

[ "$fail" = 0 ] && echo "acceptance codex: ok"
[ "$fail" = 0 ]
