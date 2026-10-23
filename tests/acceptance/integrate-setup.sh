#!/bin/sh
# integrate setup の受け入れ検査（ARK-98）: 一時 HOME と一時的な bare で、引数で全部渡せば ~/.config/integrate/repos/<鍵> に
# kind・base・test・remote の 4 行を書くこと、既にあれば書かない（上書きは --force を setup の直後に置き、端末からだけ）、
# 改行・不正な kind を拒むこと、引数が足りず端末でなければ推測（kind・base・test）を出して書かないこと、--show、端末での確認
#   sh tests/acceptance/integrate-setup.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/integrate-setup.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_STATE_HOME="$T/state"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mkdir -p "$HOME" "$T/bin"
# 偽の gh: api user は $T/login の中身（無ければ失敗）
cat > "$T/bin/gh" <<SH
#!/bin/sh
[ "\$1 \$2" = "api user" ] && cat "$T/login" 2>/dev/null
SH
chmod +x "$T/bin/gh"
export PATH="$ROOT/bin:$T/bin:$PATH"
D="$HOME/.config/integrate/repos"
cfg() { cat "$D"/* 2>/dev/null; }
nfiles() { ls "$D" 2>/dev/null | wc -l | tr -d ' '; }

# repo <bare のパス> <HEAD が指すブランチ>: develop にコミット 1 つの bare と、そのクローン $T/w（ここに cd）
repo() {
  cd "$T" && rm -rf "$1" "$T/w" "$HOME/.config"
  git init -q --bare -b develop "$1"
  git clone -q "$1" "$T/w" 2>/dev/null && cd "$T/w"
  git commit -q --allow-empty -m base && git push -q origin HEAD:develop
  git -C "$1" symbolic-ref HEAD "refs/heads/$2"
}
# guess <名前> <期待する行>: 引数なし・端末でない → 終了コード 2、何も書かず、標準出力に期待する行
guess() {
  out="$(integrate setup </dev/null 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ "$(nfiles)" = 0 ] && printf '%s\n' "$out" | grep -qx -- "$2" \
    && ok "推測: $1（$2）" || ng "推測: $1: rc=$rc files=$(nfiles) out=$out"
}

# ---- 引数で全部渡せば 4 行を書く
repo "$T/r.git" develop
integrate setup --kind bare --base develop --test 'uv run pytest -q "tests/a b"' </dev/null >/dev/null 2>"$T/err"; rc=$?
want="kind=bare
base=develop
test=uv run pytest -q \"tests/a b\"
remote=$T/r.git"
[ "$rc" = 0 ] && [ "$(cfg)" = "$want" ] && ok "全部の引数で 4 行を書く" || ng "全部の引数: rc=$rc $(cat "$T/err") 中身=$(cfg)"
name="$(ls "$D" 2>/dev/null)"
[ "$(nfiles)" = 1 ] && case "$name" in */*|*:*) false ;; *) true ;; esac \
  && ok "1 リポジトリ 1 ファイル、名前に / と : を含まない" || ng "設定のファイル: $name"
integrate setup --show </dev/null >"$T/out" 2>/dev/null; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$T/out")" = "$want" ] && ok "--show は設定を出す" || ng "--show: rc=$rc $(cat "$T/out")"

# ---- 既にあれば書かない。上書きは --force を setup の直後に置き、端末からだけ
integrate setup --kind pr --base main --test true </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ "$(cfg)" = "$want" ] && ok "既にあれば書かずに 1" || ng "既にある: rc=$rc 中身=$(cfg)"
integrate setup --force --kind pr --base main --test true </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$(cfg)" = "$want" ] && ok "--force は端末でなければ 2 で書かない" || ng "端末でない --force: rc=$rc 中身=$(cfg)"
integrate setup --kind pr --force --base main --test true </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$(cfg)" = "$want" ] && ok "--force が setup の直後でなければ 2" || ng "後ろの --force: rc=$rc 中身=$(cfg)"
LINUX_SCRIPT=""
[ "$(uname)" = Linux ] && command -v script >/dev/null 2>&1 && LINUX_SCRIPT=1 # macOS の script には -c が無い
if [ -n "$LINUX_SCRIPT" ]; then
  script -qec 'integrate setup --force --kind pr --base main --test true' /dev/null </dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(cfg | sed -n 1p)" = kind=pr ] && ok "--force は端末からなら上書きする" || ng "端末の --force: rc=$rc 中身=$(cfg)"
fi

# ---- 不正な値は書かない
rm -rf "$HOME/.config"
integrate setup --kind other --base develop --test true </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$(nfiles)" = 0 ] && ok "不正な kind は 2 で書かない" || ng "不正な kind: rc=$rc files=$(nfiles)"
integrate setup --kind bare --base develop --test "$(printf 'true\nfalse')" </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$(nfiles)" = 0 ] && ok "改行を含む値は 2 で書かない" || ng "改行: rc=$rc files=$(nfiles)"
integrate setup --show </dev/null >/dev/null 2>&1; [ $? = 1 ] && ok "--show は設定が無ければ 1" || ng "--show が設定なしで 1 でない"
XDG_CONFIG_HOME="$T/xdg" integrate setup --kind bare --base develop --test true </dev/null >/dev/null 2>&1
[ ! -e "$T/xdg" ] && [ "$(nfiles)" = 1 ] && ok "XDG_CONFIG_HOME に従わず ~/.config に書く" || ng "XDG_CONFIG_HOME: xdg=$(ls -R "$T/xdg" 2>/dev/null) files=$(nfiles)"

# ---- 記号だけ違う URL（/team/project と /team_project）でも設定は別のファイル
mkdir -p "$T/team"; repo "$T/team/project.git" develop
integrate setup --kind bare --base develop --test true </dev/null >/dev/null 2>&1; a=$?
cd "$T" && rm -rf "$T/w2" && git init -q --bare -b develop "$T/team_project.git" && git clone -q "$T/team_project.git" "$T/w2" 2>/dev/null && cd "$T/w2"
integrate setup --kind pr --base main --test true </dev/null >/dev/null 2>&1; b=$?
[ "$a" = 0 ] && [ "$b" = 0 ] && [ "$(nfiles)" = 2 ] && ok "記号だけ違う URL の設定は衝突しない" || ng "設定の衝突: rc=$a,$b files=$(nfiles)"

# ---- 相対パスの origin（../repo.git）は解決した場所で見分ける。別のリポジトリの設定を使わない
for x in a b; do
  cd "$T" && rm -rf "$T/$x" && mkdir -p "$T/$x" && git init -q --bare -b develop "$T/$x/repo.git"
  git init -q -b develop "$T/$x/work" && git -C "$T/$x/work" remote add origin ../repo.git
done
rm -rf "$HOME/.config"; cd "$T/a/work" && integrate setup --kind bare --base develop --test true </dev/null >/dev/null 2>&1
grep -qx "remote=$T/a/repo.git" "$D"/* 2>/dev/null && ok "相対パスの origin は解決した場所を remote に書く" || ng "相対パスの remote: $(cfg)"
cd "$T/b/work" && integrate setup --show </dev/null >/dev/null 2>&1; [ $? = 1 ] && ok "同じ相対パスでも別のリポジトリの設定は使わない" || ng "別のリポジトリの設定が見えた"

# ---- シンボリックリンクを含む origin は git と同じく物理パスで解決する（b/link → a/sub のとき b/link/../repo.git は a/repo.git）
mkdir -p "$T/a/sub" && ln -s "$T/a/sub" "$T/b/link"
git -C "$T/b/work" remote set-url origin "$T/b/link/../repo.git"
rm -rf "$HOME/.config"; cd "$T/b/work" && integrate setup --kind bare --base develop --test true </dev/null >/dev/null 2>&1
grep -qx "remote=$T/a/repo.git" "$D"/* 2>/dev/null && ok "シンボリックリンクを含む origin は物理パスで解決する" || ng "シンボリックリンクの remote: $(cfg)"

# ---- 長い URL でもファイル名の上限（255 バイト）に収まる
long="$T/$(printf 'x%.0s' $(seq 1 200))/$(printf 'y%.0s' $(seq 1 100)).git"
repo "$long" develop
integrate setup --kind bare --base develop --test true </dev/null >/dev/null 2>"$T/err"; rc=$?
[ "$rc" = 0 ] && [ "$(ls "$D" | wc -c)" -lt 200 ] && ok "長い URL でも設定を書ける" || ng "長い URL: rc=$rc $(cat "$T/err")"

# ---- 書けなければ失敗を返す（root では権限で書けなくならないので省く）
if [ "$(id -u)" != 0 ]; then
  repo "$T/r.git" develop; mkdir -p "$D"; chmod 555 "$D"
  integrate setup --kind bare --base develop --test true </dev/null >"$T/out" 2>"$T/err"; rc=$?
  chmod 755 "$D"
  [ "$rc" = 1 ] && [ "$(nfiles)" = 0 ] && ! grep -q 設定しました "$T/out" && grep -q 書けない "$T/err" \
    && ok "設定を書けなければ 1（成功と言わない）" || ng "書けないとき: rc=$rc out=$(cat "$T/out") err=$(cat "$T/err")"
fi

# ---- 推測（引数なし・端末でない）
repo "$T/r.git" develop
guess "GitHub でなければ bare" kind=bare
guess "base はリモートの HEAD" base=develop
guess "テストのファイルが無ければ空" test=
touch pyproject.toml; guess "pyproject.toml → uv run pytest" 'test=uv run pytest'
mkdir -p scripts && touch scripts/check; guess "scripts/check が先" 'test=sh scripts/check'
repo "$T/r.git" nothere
guess "HEAD の指すブランチが無ければ base は空" base=
repo "$T/github.com/o/r.git" develop
echo o > "$T/login"; guess "GitHub で持ち主が自分なら github" kind=github
echo x > "$T/login"; guess "GitHub で持ち主が他人なら pr" kind=pr
rm -f "$T/login"; guess "gh で自分が分からなければ pr" kind=pr

# ---- 端末: 推測を既定値として尋ね、空の入力で推測を採る
if [ -n "$LINUX_SCRIPT" ]; then
  repo "$T/r.git" develop; touch pyproject.toml
  printf '\n\n\n' | script -qec 'integrate setup' /dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(cfg | sed -n 1,3p)" = "kind=bare
base=develop
test=uv run pytest" ] && ok "端末では推測を既定値に尋ねて書く" || ng "端末: rc=$rc 中身=$(cfg)"
fi

[ "$fail" = 0 ] && echo "acceptance integrate-setup: ok"
[ "$fail" = 0 ]
