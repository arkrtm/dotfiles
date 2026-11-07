#!/bin/sh
# シェルの起動ファイルの受け入れ検査。端末ごとの上書き（リポジトリの外）: ~/.zshenv.local は全ての zsh と bash、~/.zshrc.local は対話の zsh、~/.bashrc.local は対話の bash が読み、
# 無くてもエラーを出さない。zsh の補完は、install.sh が作る置き場（umask 002 でも compinit が拒まない）と、システムの vendor-completions を読む
#   sh tests/acceptance/shell.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/shell.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
chk() { n="$1"; shift; if "$@"; then ok "$n"; else ng "$n"; fi; }
ZSH="$(command -v zsh || true)" # env -i の前に決める。無い端末では zsh の項目を省く（tests/static.sh と同じ）

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"

# 一時 HOME: shell/ の 5 つを直接リンクする（install.sh に依らない）
H="$T/h"; mkdir "$H"
for f in zshenv zprofile zshrc bashrc bash_profile; do ln -s "$ROOT/shell/$f" "$H/.$f"; done
# 無いとき
if [ -n "$ZSH" ]; then
  e="$(env -i HOME="$H" PATH=/usr/bin:/bin "$ZSH" -i -c true 2>&1 </dev/null)"
  chk "*.local が無くても対話 zsh はエラーを出さない" test -z "$e"
fi
eb="$(env -i HOME="$H" PATH=/usr/bin:/bin NO_ZSH=1 bash -i -c true 2>&1 </dev/null)"
case "$eb" in *.local*) ng "*.local が無くても対話 bash はその読み込みでエラーを出さない: $eb" ;; *) ok "*.local が無くても対話 bash はその読み込みでエラーを出さない" ;; esac
# あるとき
printf 'export DOTFILES_T_ENV=env\n' > "$H/.zshenv.local"; printf 'DOTFILES_T_RC=rc\n' > "$H/.zshrc.local"; printf 'DOTFILES_T_BRC=brc\n' > "$H/.bashrc.local"
if [ -n "$ZSH" ]; then
  chk "非対話 zsh は ~/.zshenv.local を読む" \
    test "$(env -i HOME="$H" PATH=/usr/bin:/bin "$ZSH" -c 'print -r -- "$DOTFILES_T_ENV"' 2>&1)" = env
  chk "対話 zsh は ~/.zshenv.local と ~/.zshrc.local を読む" \
    test "$(env -i HOME="$H" PATH=/usr/bin:/bin "$ZSH" -i -c 'print -r -- "$DOTFILES_T_ENV/$DOTFILES_T_RC"' 2>/dev/null </dev/null)" = env/rc
fi
chk "対話 bash は ~/.zshenv.local と ~/.bashrc.local を読む" \
  test "$(env -i HOME="$H" PATH=/usr/bin:/bin NO_ZSH=1 bash -i -c 'echo "R=$DOTFILES_T_ENV/$DOTFILES_T_BRC"' 2>/dev/null </dev/null | sed -n 's/^R=//p')" = env/brc
R="$ROOT/shell/README.md"
chk "shell/README.md に端末ごとの設定と秘密の置き場がある" \
  sh -c 'for f in .zshenv.local .zshrc.local .bashrc.local; do grep -qF "~/$f" "$1" || exit 1; done; grep -q 秘密 "$1"' sh "$R"

# 補完: install.sh（リンクだけ）に umask 002 で一時 HOME を作らせる。対話 zsh には LOGNAME=dotfiles-nogroup を渡し、
# compaudit の「自分だけのグループなら group が書けてもよい」例外を外す（端末に依らず厳しい条件にする）
if [ -n "$ZSH" ]; then
  H2="$T/h2"; mkdir "$H2"
  (umask 002; env -i HOME="$H2" PATH=/usr/bin:/bin DOTFILES_LINKS_ONLY=1 DOTFILES_ALLOW_WORKTREE=1 sh "$ROOT/install.sh" >/dev/null 2>&1)
  chk "install.sh（リンクだけ）が補完の置き場を作る" test -d "$H2/.local/share/zsh/site-functions"
  printf '#compdef dotfilesprobe\n_dotfilesprobe() { _files }\n' 2>/dev/null > "$H2/.local/share/zsh/site-functions/_dotfilesprobe"
  zi() { env -i HOME="$H2" LOGNAME=dotfiles-nogroup PATH=/usr/bin:/bin "$ZSH" -i -c "$1" </dev/null 2>&1; }
  chk "umask 002 で作った補完の置き場とその親を compaudit が危ないとみなさず、対話 zsh が補完を読む（打ち切りや問いの文も出ない）" \
    test "$(zi 'autoload -Uz compaudit; compaudit >/dev/null 2>&1; print -r -- "A=$? R=${_comps[dotfilesprobe]-なし}"')" = 'A=0 R=_dotfilesprobe'
  if [ -f /usr/share/zsh/vendor-completions/_docker ]; then
    chk "対話 zsh はシステムの vendor-completions（docker）を読む" test "$(zi 'print -r -- "${_comps[docker]-なし}"')" = _docker
  fi
fi

[ "$fail" = 0 ] && echo "acceptance shell: ok"
[ "$fail" = 0 ]
