#!/bin/sh
# integrate の受け入れ検査（ARK-89）: 一時ディレクトリの bare とクローンで、関門を 1 つでも満たさなければ
# 統合しない（終了コード 1、notify のログに理由、bare の main は変わらない）こと、すべて満たせば bare は main へ push、
# GitHub（origin の URL に github.com を含む。偽の gh）はブランチを push して PR を作るだけでマージしないこと
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
export XDG_STATE_HOME="$T/state"
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

# setup <bare>: bare の main に scripts/check（通る）と tests/ を置き、クローン $T/w で feature/x を切ってコミット 1 つ
setup() {
  BARE="$1"
  cd "$T" && rm -rf "$T/w" "$T/wt" "$T/o" "$BARE" "$T/pr" "$T/gh.log"
  git init -q --bare -b main "$BARE"
  git clone -q "$BARE" "$T/w" 2>/dev/null
  cd "$T/w"
  mkdir -p scripts tests
  printf '#!/bin/sh\nexit 0\n' > scripts/check; chmod +x scripts/check
  echo t > tests/t.sh; echo j > tests/日本語.sh
  git add -A && git commit -qm base && git push -q origin HEAD:main
  git checkout -q -b feature/x
  add a 1
}
add() { echo "$2" >> "$1"; git add "$1"; git commit -qm "$1"; }
# review <VERDICT> [比較元]: 今のコミットへの codex-review branch の結果（比較元の既定は origin/main）
review() {
  d="$(git rev-parse --path-format=absolute --git-common-dir)/codex-review"
  mkdir -p "$d"
  printf '指摘\nVERDICT: %s\n' "$1" > "$d/20260101-000000-branch-$(git rev-parse "${2:-origin/main}")-$(git rev-parse HEAD).md"
}
logn() { cat "$LOG" 2>/dev/null | wc -l; }
# refused <名前> [integrate の引数]: 終了コード 1、notify のログが増える、bare の main が変わらない
refused() {
  name="$1"; shift
  m0="$(git -C "$BARE" rev-parse main)"; n0="$(logn)"
  integrate "$@" >/dev/null 2>"$T/err"; rc=$?
  [ "$rc" = 1 ] && [ "$(logn)" -gt "$n0" ] && [ "$(git -C "$BARE" rev-parse main)" = "$m0" ] \
    && ok "統合しない: $name" || ng "統合しない: $name（rc=$rc $(cat "$T/err")）"
}
# accepted <名前> [integrate の引数]: 終了コード 0、bare の main が HEAD になる
accepted() {
  name="$1"; shift
  integrate "$@" >/dev/null 2>"$T/err"; rc=$?
  [ "$rc" = 0 ] && [ "$(git -C "$BARE" rev-parse main)" = "$(git rev-parse HEAD)" ] \
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
setup "$T/r.git"; add tests/test_x.py '@pytest.mark.skip'; review PASS; refused "pytest.mark.skip を足した（AC4）"
accepted "--human-approved なら無効化の追加も通す（AC4）" --human-approved
setup "$T/r.git"; add README.md 'skip や noqa の説明'; review PASS; accepted "Markdown の文書の説明は無効化の追加と数えない"
setup "$T/r.git"; git rm -q tests/t.sh; git commit -qm rm; review PASS; refused "tests/ のファイルを削除した（AC5）"
accepted "--human-approved ならテストの削除も通す（AC5）" --human-approved
setup "$T/r.git"; mkdir archive; git mv tests/t.sh archive/t.sh; git commit -qm mv; review PASS; refused "tests/ のファイルを外へ移した（AC5）"
setup "$T/r.git"; git rm -q tests/日本語.sh; git commit -qm rm; review PASS; refused "日本語名のテストを削除した（AC5）"

# ---- AC6: main が進んでいたら通さない
setup "$T/r.git"; review PASS
git clone -q "$BARE" "$T/o" 2>/dev/null && (cd "$T/o" && add b 1 && git push -q origin HEAD:main)
refused "main が進んでいる（AC6）"

# ---- AC7: 未コミットの変更・main の上・scripts/check が無い／失敗する／追跡ファイルを書き換える
setup "$T/r.git"; review PASS
echo dirty >> a; refused "コミットしていない変更がある（AC7）"; git checkout -q a
mkdir -p "$T/statusbin"; printf '#!/bin/sh\n[ "$1" = status ] && exit 128\nexec %s "$@"\n' "$(command -v git)" > "$T/statusbin/git"; chmod +x "$T/statusbin/git"
PATH="$T/statusbin:$PATH" refused "git status が失敗する（変更なしと見なさない）"
grep -q 'git status' "$T/err" && ok "git status の失敗を理由に止まる" || ng "git status の失敗で止まっていない: $(cat "$T/err")"
git checkout -q main; refused "main の上で実行した（AC7）"; git checkout -q feature/x
setup "$T/r.git"; git rm -q scripts/check; git commit -qm rm; review PASS; refused "scripts/check が無い（AC7）"
setup "$T/r.git"; printf '#!/bin/sh\necho check-failed-here\nexit 1\n' > scripts/check; git commit -qam fail; review PASS
refused "scripts/check が失敗する（AC7）"
grep -q check-failed-here "$T/err" && ok "検査の失敗の出力を見せる" || ng "検査の失敗の出力が出ない: $(cat "$T/err")"
setup "$T/r.git"; printf '#!/bin/sh\necho x >> a\n' > scripts/check; git commit -qam dirty; review PASS
refused "scripts/check が追跡ファイルを書き換える"

# ---- 使い方の誤り
setup "$T/r.git"; review PASS
integrate --foo >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 2 ] && grep -q usage "$T/err" && ok "未知の引数は 2 で使い方を出す" || ng "未知の引数: rc=$rc $(cat "$T/err")"

# ---- AC8: すべて満たせば bare の main へ push する。worktree の中でも（レビューは共通ディレクトリ）
accepted "すべて満たす（bare。AC8）"
# 差分を取れなければ、無効化の記述が無いとは言えないので通さない（diff --no-color だけ失敗する git）
setup "$T/r.git"; review PASS; mkdir -p "$T/failbin"
printf '#!/bin/sh\ncase " $* " in *" diff --no-color "*) exit 128 ;; esac\nexec %s "$@"\n' "$(command -v git)" > "$T/failbin/git"; chmod +x "$T/failbin/git"
PATH="$T/failbin:$PATH" refused "差分を取れない"
setup "$T/r.git"; git worktree add -q -b feature/wt "$T/wt" && cd "$T/wt"; add c 1; review PASS
accepted "worktree の中ですべて満たす"

# ---- AC9: GitHub はブランチを push して PR を作るだけ（マージしない）。開いた PR があれば作らない
setup "$T/github.com/o/r.git"; review PASS; m0="$(git -C "$BARE" rev-parse main)"
integrate >"$T/out" 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$BARE" rev-parse feature/x)" = "$(git rev-parse HEAD)" ] && [ "$(git -C "$BARE" rev-parse main)" = "$m0" ] \
  && ok "GitHub: ブランチを push し、main は変えない" || ng "GitHub: rc=$rc $(cat "$T/err")"
[ "$(grep -c '^pr create' "$T/gh.log")" = 1 ] && ! grep -q '^pr merge' "$T/gh.log" && grep -q 'pull/1' "$T/out" \
  && ok "GitHub: PR を作って url を出し、マージしない" || ng "GitHub: gh の呼び出し: $(cat "$T/gh.log")"
# gh の既定のリポジトリ（GH_REPO・gh repo set-default）に関係なく、PR の対象は origin
[ "$(grep -c -- '--repo o/r' "$T/gh.log")" = "$(grep -c '^pr ' "$T/gh.log")" ] \
  && ok "GitHub: PR の検索と作成は origin（--repo o/r）に固定する" || ng "GitHub: gh の呼び出し: $(cat "$T/gh.log")"
add a 2; review PASS; integrate >/dev/null 2>"$T/err"
[ "$(grep -c '^pr create' "$T/gh.log")" = 1 ] && [ "$(git -C "$BARE" rev-parse feature/x)" = "$(git rev-parse HEAD)" ] \
  && ok "GitHub: 開いた PR があれば push だけ" || ng "GitHub: 2 回目: $(cat "$T/gh.log") $(cat "$T/err")"
rm -f "$T/pr"; add a 3; review PASS; integrate >/dev/null 2>"$T/err"
[ "$(grep -c '^pr create' "$T/gh.log")" = 2 ] && ok "GitHub: PR が閉じていれば新しく作る" || ng "GitHub: 閉じた PR: $(cat "$T/gh.log")"
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
