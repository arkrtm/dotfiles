#!/bin/sh
# integrate の受け入れ検査（ARK-89・ARK-98）: 一時ディレクトリの bare とクローン、integrate setup の設定（一時 HOME）で、
# 関門を 1 つでも満たさなければ統合しない（終了コード 1、notify のログに理由、bare の最上位のブランチは変わらない）こと、
# 設定が無い・壊れている・remote が違えば統合しないこと、すべて満たせば kind=bare・github は base へ push、
# kind=pr（偽の gh）はブランチを push して base に向けた PR を作るだけでマージしないこと
#   sh tests/acceptance/integrate.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/integrate.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export XDG_STATE_HOME="$T/state" HOME="$T/home"
mkdir -p "$HOME"
LOG="$T/state/agent-notify.log"
# 偽の gh: 呼び出しを gh.log に残す。pr list は開いた PR（$T/pr の url）を出し、pr create は $T/pr を作って url を出す
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<SH
#!/bin/sh
echo "\$*" >> "$T/gh.log"
case "\$1 \$2" in
  "pr list") cat "$T/pr" 2>/dev/null ;;
  "pr create") echo https://github.com/o/r/pull/1 | tee "$T/pr" ;;
esac
exit 0
SH
chmod +x "$T/bin/gh"
export PATH="$ROOT/bin:$T/bin:$PATH"
exec </dev/null

# setup <bare> [kind] [base]: bare の <base>（既定 main）に scripts/check（通る）と tests/ を置き、クローン $T/w で feature/x を切って
# コミット 1 つ。integrate setup で kind（既定はパスに github.com を含めば pr、ほかは bare）・base・test=./scripts/check を設定する
setup() {
  BARE="$1"; B="${3:-main}"
  case "$BARE" in *github.com*) K="${2:-pr}" ;; *) K="${2:-bare}" ;; esac
  cd "$T" && rm -rf "$T/w" "$T/wt" "$T/o" "$BARE" "$T/pr" "$T/gh.log" "$HOME/.config"
  git init -q --bare -b "$B" "$BARE"
  git clone -q "$BARE" "$T/w" 2>/dev/null
  cd "$T/w"
  mkdir -p scripts tests
  printf '#!/bin/sh\nexit 0\n' > scripts/check; chmod +x scripts/check
  echo t > tests/t.sh; echo j > tests/日本語.sh
  git add -A && git commit -qm base && git push -q origin "HEAD:$B"
  git checkout -q -b feature/x
  add a 1
  resetup --test ./scripts/check
}
# resetup <setup の引数>: 設定を消して、kind と base は今の K・B で設定し直す
resetup() { rm -rf "$HOME/.config/integrate"; integrate setup --kind "$K" --base "$B" "$@" >/dev/null 2>&1 || ng "integrate setup に失敗: $*"; }
conf() { ls "$HOME"/.config/integrate/repos/*; }
add() { echo "$2" >> "$1"; git add "$1"; git commit -qm "$1"; }
# review <VERDICT> [比較元]: 今のコミットへの codex-review branch の結果（比較元の既定は origin/<base>）
review() {
  d="$(git rev-parse --path-format=absolute --git-common-dir)/codex-review"
  mkdir -p "$d"
  printf '指摘\nVERDICT: %s\n' "$1" > "$d/20260101-000000-branch-$(git rev-parse "${2:-origin/$B}")-$(git rev-parse HEAD).md"
}
logn() { cat "$LOG" 2>/dev/null | wc -l; }
# refused <名前> [integrate の引数]: 終了コード 1、notify のログが増える、bare の <base> が変わらない
refused() {
  name="$1"; shift
  m0="$(git -C "$BARE" rev-parse "$B")"; n0="$(logn)"
  integrate "$@" >/dev/null 2>"$T/err"; rc=$?
  [ "$rc" = 1 ] && [ "$(logn)" -gt "$n0" ] && [ "$(git -C "$BARE" rev-parse "$B")" = "$m0" ] \
    && ok "統合しない: $name" || ng "統合しない: $name（rc=$rc $(cat "$T/err")）"
}
# accepted <名前> [integrate の引数]: 終了コード 0、bare の <base> が HEAD になる
accepted() {
  name="$1"; shift
  integrate "$@" >/dev/null 2>"$T/err"; rc=$?
  [ "$rc" = 0 ] && [ "$(git -C "$BARE" rev-parse "$B")" = "$(git rev-parse HEAD)" ] \
    && ok "統合する: $name" || ng "統合する: $name（rc=$rc $(cat "$T/err")）"
}

# ---- AC1〜AC3: 今のコミットへの、origin/main との差分のレビューが PASS でなければ通さない
setup "$T/r.git"
refused "レビューが無い（AC1）"
review FAIL; refused "レビューが VERDICT: FAIL（AC2）"
review PASS; add a 2; refused "レビューの後にコミットを足した（AC3）"
setup "$T/r.git"; review PASS HEAD; refused "比較元が HEAD（空の差分）のレビューだけ"

# ---- AC4・AC5: テストや検査を弱める変更は、人の承認（--human-approved）なしでは通さない
setup "$T/r.git"; add x.py 'import os  # noqa'; review PASS; refused "noqa を足した（AC4）"
setup "$T/r.git"; git config color.ui always; add x.py 'import os  # noqa'; review PASS; refused "色付きの diff の設定でも noqa を見つける"
setup "$T/r.git"; echo '*.py -diff' > .gitattributes; git add .gitattributes; add x.py 'import os  # noqa'; review PASS
refused "差分を出さない属性（-diff）でも noqa を見つける"
setup "$T/r.git"; add tests/test_x.py '@pytest.mark.skip'; review PASS; refused "pytest.mark.skip を足した（AC4）"
accepted "--human-approved なら無効化の追加も通す（AC4）" --human-approved
setup "$T/r.git"; add README.md 'skip や noqa の説明'; review PASS; accepted "Markdown の文書の説明は無効化の追加と数えない"
setup "$T/r.git"; git rm -q tests/t.sh; git commit -qm rm; review PASS; refused "tests/ のファイルを削除した（AC5）"
accepted "--human-approved ならテストの削除も通す（AC5）" --human-approved
setup "$T/r.git"; mkdir archive; git mv tests/t.sh archive/t.sh; git commit -qm mv; review PASS; refused "tests/ のファイルを外へ移した（AC5）"
setup "$T/r.git"; git rm -q tests/日本語.sh; git commit -qm rm; review PASS; refused "日本語名のテストを削除した（AC5）"
# test/tests の外でも、命名規則でテストと分かるファイル・ディレクトリの削除は通さない（ARK-97）
for f in test_app.py src/app_test.py src/conftest.py src/app_test.go web/a.test.ts web/a.spec.js web/__tests__/a.js spec/a_spec.rb; do
  setup "$T/r.git"; mkdir -p "$(dirname "$f")"; echo t > "$f"; git add "$f"; git commit -qm add
  git push -q origin HEAD:main; git fetch -q; git checkout -q -B feature/x origin/main; add a 1
  git rm -q "$f"; git commit -qm rm; review PASS; refused "テストを削除した: $f"
done

# ---- AC6: main が進んでいたら通さない
setup "$T/r.git"; review PASS
git clone -q "$BARE" "$T/o" 2>/dev/null && (cd "$T/o" && add b 1 && git push -q origin HEAD:main)
refused "main が進んでいる（AC6）"

# ---- AC7: 未コミットの変更・main の上・scripts/check が無い／失敗する／追跡ファイルを書き換える
setup "$T/r.git"; review PASS
echo dirty >> a; refused "コミットしていない変更がある（AC7）"; git checkout -q a
git config status.showUntrackedFiles no; echo x > conftest.py; refused "未追跡のファイルがある（status.showUntrackedFiles=no でも）"
rm -f conftest.py; git config --unset status.showUntrackedFiles
mkdir -p "$T/statusbin"; printf '#!/bin/sh\n[ "$1" = status ] && exit 128\nexec %s "$@"\n' "$(command -v git)" > "$T/statusbin/git"; chmod +x "$T/statusbin/git"
PATH="$T/statusbin:$PATH" refused "git status が失敗する（変更なしと見なさない）"
grep -q 'git status' "$T/err" && ok "git status の失敗を理由に止まる" || ng "git status の失敗で止まっていない: $(cat "$T/err")"
git checkout -q main; refused "main の上で実行した（AC7）"; git checkout -q feature/x
setup "$T/r.git"; git rm -q scripts/check; git commit -qm rm; review PASS; refused "設定の test のコマンドが無い（AC7）"
setup "$T/r.git"; printf '#!/bin/sh\necho check-failed-here\nexit 1\n' > scripts/check; git commit -qam fail; review PASS
refused "設定の test が失敗する（AC7）"
grep -q check-failed-here "$T/err" && ok "テストの失敗の出力を見せる" || ng "テストの失敗の出力が出ない: $(cat "$T/err")"
setup "$T/r.git"; printf '#!/bin/sh\necho x >> a\n' > scripts/check; git commit -qam dirty; review PASS
refused "設定の test が追跡ファイルを書き換える"
setup "$T/r.git"; review PASS; resetup --test false; refused "設定の test が false"

# ---- ARK-98: 設定（integrate setup）が無い・壊れている・remote が origin と違えば統合しない
setup "$T/r.git"; review PASS; rm -rf "$HOME/.config/integrate"; refused "設定が無い"
grep -q 'integrate setup' "$T/err" && ok "設定が無ければ integrate setup を促す" || ng "設定が無いときの案内: $(cat "$T/err")"
setup "$T/r.git"; review PASS; sed -i.bak 's#^remote=.*#remote=/elsewhere/r.git#' "$(conf)"; rm -f "$(conf).bak"; refused "設定の remote が origin と違う"
setup "$T/r.git"; review PASS; echo extra=1 >> "$(conf)"; refused "設定に知らない行がある"
setup "$T/r.git"; review PASS; echo kind=github >> "$(conf)"; refused "設定の kind が重複する"
setup "$T/r.git"; review PASS; sed -i.bak 's#^test=.*#test=#' "$(conf)"; rm -f "$(conf).bak"; refused "設定の test が空"
# scripts/check の決まりは無い: 設定の test だけを走らせる
setup "$T/r.git"; git rm -q scripts/check; printf 'exit 0\n' > run-tests.sh; git add run-tests.sh; git commit -qm runner
resetup --test 'sh run-tests.sh'; review PASS; accepted "scripts/check が無くても設定の test で通す"
setup "$T/r.git"; printf '#!/bin/sh\n[ "$1" = "a b" ]\n' > scripts/check; git commit -qam args
resetup --test 'sh "scripts/check" "a b"'; review PASS; accepted "空白と引用符を含む test をそのまま実行する"
# base=develop の bare: develop へ push し、main は作らない。比較元は origin/develop
setup "$T/d.git" bare develop; review PASS; accepted "base=develop の bare は develop へ push する"
git -C "$BARE" rev-parse -q --verify main >/dev/null && ng "base=develop なのに main ができた" || ok "base=develop では main を作らない"
setup "$T/d.git" bare develop; review PASS
git clone -q "$BARE" "$T/o" 2>/dev/null && (cd "$T/o" && git checkout -q develop && add b 1 && git push -q origin HEAD:develop)
refused "origin/develop が進んでいる"
# kind=github: GitHub のリモートでも PR を作らず base へ push する
setup "$T/github.com/o/g.git" github; review PASS; accepted "kind=github は main へ直接 push する"
[ ! -e "$T/gh.log" ] && ok "kind=github は gh を呼ばない" || ng "kind=github で gh を呼んだ: $(cat "$T/gh.log")"

# ---- 使い方の誤り
setup "$T/r.git"; review PASS
integrate --foo >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 2 ] && grep -q usage "$T/err" && ok "未知の引数は 2 で使い方を出す" || ng "未知の引数: rc=$rc $(cat "$T/err")"

# ---- AC8: すべて満たせば bare の base（main）へ push する。worktree の中でも（レビューは共通ディレクトリ）
accepted "すべて満たす（bare。AC8）"
# 差分を取れなければ、無効化の記述が無いとは言えないので通さない（diff --no-color だけ失敗する git）
setup "$T/r.git"; review PASS; mkdir -p "$T/failbin"
printf '#!/bin/sh\ncase " $* " in *" diff --no-color "*) exit 128 ;; esac\nexec %s "$@"\n' "$(command -v git)" > "$T/failbin/git"; chmod +x "$T/failbin/git"
PATH="$T/failbin:$PATH" refused "差分を取れない"
setup "$T/r.git"; git worktree add -q -b feature/wt "$T/wt" && cd "$T/wt"; add c 1; review PASS
accepted "worktree の中ですべて満たす"

# ---- AC9: kind=pr はブランチを push して base に向けた PR を作るだけ（マージしない）。開いた PR があれば作らない
setup "$T/github.com/o/r.git"; review PASS; m0="$(git -C "$BARE" rev-parse main)"
integrate >"$T/out" 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$BARE" rev-parse feature/x)" = "$(git rev-parse HEAD)" ] && [ "$(git -C "$BARE" rev-parse main)" = "$m0" ] \
  && ok "GitHub: ブランチを push し、main は変えない" || ng "GitHub: rc=$rc $(cat "$T/err")"
[ "$(grep -c '^pr create' "$T/gh.log")" = 1 ] && ! grep -q '^pr merge' "$T/gh.log" && grep -q 'pull/1' "$T/out" \
  && grep -q -- '^pr create .*--base main' "$T/gh.log" && grep -q -- '^pr list .*--base main' "$T/gh.log" \
  && ok "GitHub: PR を作って url を出し、マージしない" || ng "GitHub: gh の呼び出し: $(cat "$T/gh.log")"
# gh の既定のリポジトリ（GH_REPO・gh repo set-default）に関係なく、PR の対象は origin
[ "$(grep -c -- '--repo github.com/o/r' "$T/gh.log")" = "$(grep -c '^pr ' "$T/gh.log")" ] \
  && ok "GitHub: PR の検索と作成は origin（--repo github.com/o/r。GH_HOST にも従わない）に固定する" || ng "GitHub: gh の呼び出し: $(cat "$T/gh.log")"
add a 2; review PASS; integrate >/dev/null 2>"$T/err"
[ "$(grep -c '^pr create' "$T/gh.log")" = 1 ] && [ "$(git -C "$BARE" rev-parse feature/x)" = "$(git rev-parse HEAD)" ] \
  && ok "GitHub: 開いた PR があれば push だけ" || ng "GitHub: 2 回目: $(cat "$T/gh.log") $(cat "$T/err")"
rm -f "$T/pr"; add a 3; review PASS; integrate >/dev/null 2>"$T/err"
[ "$(grep -c '^pr create' "$T/gh.log")" = 2 ] && ok "GitHub: PR が閉じていれば新しく作る" || ng "GitHub: 閉じた PR: $(cat "$T/gh.log")"
# base=develop の pr: PR の検索と作成の両方が develop に向く。2 回目は PR を作らない
setup "$T/github.com/o/d.git" pr develop; review PASS; integrate >/dev/null 2>"$T/err"; rc=$?
add a 2; review PASS; integrate >/dev/null 2>>"$T/err"
[ "$rc" = 0 ] && [ "$(grep -c '^pr create' "$T/gh.log")" = 1 ] && [ "$(grep -c -- '--base develop' "$T/gh.log")" = "$(grep -c '^pr ' "$T/gh.log")" ] \
  && ok "GitHub: base=develop の PR は検索も作成も develop、2 回目は作らない" || ng "GitHub: base=develop: rc=$rc $(cat "$T/err") $(cat "$T/gh.log")"
# ポート付きの ssh の URL（ssh://git@ssh.github.com:443/o/r.git の形）でも、PR の対象は o/r
setup "$T/ssh.github.com:443/o/r.git"; review PASS; integrate >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && grep -q -- '^pr create --repo github.com/o/r ' "$T/gh.log" && ok "GitHub: ポート付きの URL でも PR の対象は o/r" || ng "GitHub: ポート付きの URL: rc=$rc $(cat "$T/err") $(cat "$T/gh.log" 2>/dev/null)"
# integrate.bare が無ければ main へは push しない。GitHub のリポジトリは、展開した URL か書いたままの URL から
# 大文字小文字を問わず求める（実際の送り先は insteadOf で一時的な bare に向ける）
github_like() {
  name="$1" url="$2" to="$3" prefix="${4:-$2}"
  setup "$to" pr; git remote set-url origin "$url"; git config url."${5:-$BARE}".insteadOf "$prefix"; resetup --test ./scripts/check
  review PASS; m0="$(git -C "$BARE" rev-parse main)"
  integrate >/dev/null 2>"$T/err"; rc=$?
  [ "$rc" = 0 ] && [ "$(git -C "$BARE" rev-parse main)" = "$m0" ] && grep -q -- '^pr create --repo github.com/o/r ' "$T/gh.log" \
    && ok "GitHub: $name は PR を作るだけ" || ng "GitHub: $name: rc=$rc $(cat "$T/err") $(cat "$T/gh.log" 2>/dev/null)"
}
github_like "大文字の URL" https://GitHub.com/o/r.git "$T/r.git"
github_like "省略形（insteadOf で github.com の URL に展開）" gh:r.git "$T/github.com/o/r.git" gh: "$T/github.com/o/"
# kind=pr でも GitHub のリポジトリと分からないリモート（ssh の別名・core.sshCommand など）では、PR の対象が決まらないので止まる
setup "$T/r.git" pr; git remote set-url origin ghalias:o/r.git; git config url."$BARE".insteadOf ghalias:o/r.git; resetup --test ./scripts/check; review PASS
refused "kind=pr で GitHub のリポジトリと分からない"
[ ! -e "$T/gh.log" ] && ok "GitHub か分からなければ PR も作らない" || ng "GitHub か分からないのに gh を呼んだ: $(cat "$T/gh.log")"
# push 先が複数あると、どこへ送るか決められないので通さない（GitHub に混ざっていても main を直接変えない）
setup "$T/r.git"; G="$T/github.com/p.git"; rm -rf "$G"; git clone -q --bare "$BARE" "$G"
git remote set-url --add --push origin "$BARE"; git remote set-url --add --push origin "$G"; review PASS; g0="$(git -C "$G" rev-parse main)"
refused "push 先（pushurl）が複数ある"
[ "$(git -C "$G" rev-parse main)" = "$g0" ] && ok "push 先が複数でも GitHub の main を変えない" || ng "push 先が複数で GitHub の main が変わった"
# push 先が取得先と違う（pushurl）と、main の判定と PR の対象が push 先とずれるので通さない
setup "$T/r.git"; G="$T/github.com/p.git"; rm -rf "$G"; git clone -q --bare "$BARE" "$G"
git remote set-url --push origin "$G"; review PASS; g0="$(git -C "$G" rev-parse main)"
refused "push 先（pushurl）が取得先と違う"
[ "$(git -C "$G" rev-parse main)" = "$g0" ] && [ ! -e "$T/gh.log" ] && ok "push 先が取得先と違えば GitHub を変えない" || ng "pushurl が違うのに GitHub を変えた: $(cat "$T/gh.log" 2>/dev/null)"

[ "$fail" = 0 ] && echo "acceptance integrate: ok"
[ "$fail" = 0 ]
