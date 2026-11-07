#!/bin/sh
# WSL の PATH とリンクの受け入れ検査。WSL（WSL_DISTRO_NAME がある）では、zsh と bash が PATH の Windows の場所を system32 と WINDOWS だけにし
# （大文字小文字は問わない。/mnt/wsl のような Linux の場所は残す）、mise が PATH を作り直す元の __MISE_ORIG_PATH も同じにする。WSL でなければ PATH を変えない。
# install.sh は WSL で Windows の powershell.exe・win32yank.exe を ~/.local/bin にリンクし、win32yank.exe が無ければリンクせず warning
# （powershell.exe はリンクする）、2 回目は何も出さない。WSL でなければリンクも warning も無い（偽の cmd.exe・wslpath で走らせる）
#   sh tests/acceptance/wsl.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/wsl.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
skip() { echo "省いた $1"; }
chk() { n="$1"; shift; if "$@"; then ok "$n"; else ng "$n"; fi; }
ZSH="$(command -v zsh || true)" # env -i の前に決める。無い端末では zsh の項目を省く（tests/static.sh と同じ）

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"

# PATH: shell/ の 5 つを一時 HOME に直接リンクする（install.sh に依らない）
H="$T/h"; mkdir "$H"
for f in zshenv zprofile zshrc bashrc bash_profile; do ln -s "$ROOT/shell/$f" "$H/.$f"; done
IN='/usr/bin:/bin:/mnt/c/WINDOWS/system32:/mnt/c/WINDOWS:/mnt/c/Windows/System32:/mnt/c/Windows/System32/OpenSSH:/mnt/c/Program Files/Git/cmd:/mnt/d/tools:/mnt/wsl/x'
mnt() { printf '%s\n' "$1" | tr ':' '\n' | grep '^/mnt/' | tr '\n' '|'; } # /mnt の項目を順に（空白を含む項目があるので | でつなぐ）
WANT='/mnt/c/WINDOWS/system32|/mnt/c/WINDOWS|/mnt/c/Windows/System32|/mnt/wsl/x|'
if [ -n "$ZSH" ]; then
  out="$(env -i HOME="$H" PATH="$IN" WSL_DISTRO_NAME=Test __MISE_ORIG_PATH="$IN" "$ZSH" -c 'print -r -- "$PATH"; print -r -- "$__MISE_ORIG_PATH"' 2>&1)"
  chk "WSL の zsh: PATH の /mnt は Windows の system32 と WINDOWS だけ（大文字小文字を問わない。/mnt/wsl は残す）" \
    test "$(mnt "$(printf '%s\n' "$out" | sed -n 1p)")" = "$WANT"
  chk "WSL の zsh: 受け継いだ __MISE_ORIG_PATH も絞る（mise が Windows の PATH を戻さない）" \
    test "$(mnt "$(printf '%s\n' "$out" | sed -n 2p)")" = "$WANT"
  n="$(env -i HOME="$H" PATH="$IN" "$ZSH" -c 'print -r -- "$PATH"' 2>&1)"
  case "$n" in *":$IN") ok "WSL でない zsh の PATH は変えない" ;; *) ng "WSL でない zsh の PATH は変えない: $n" ;; esac
else skip "WSL の zsh の PATH の検査（zsh が無い）"
fi
b="$(env -i HOME="$H" PATH="$IN" WSL_DISTRO_NAME=Test bash -lc 'echo "P=$PATH"' 2>/dev/null | sed -n 's/^P=//p')"
chk "WSL の bash（bash_profile → bashrc → zshenv）も同じに絞る" test "$(mnt "$b")" = "$WANT"
nb="$(env -i HOME="$H" PATH="$IN" bash -lc 'echo "P=$PATH"' 2>/dev/null | sed -n 's/^P=//p')"
chk "WSL でない bash の PATH は変えない" test "$(mnt "$nb")" = "$(mnt "$IN")"

# install.sh のリンク: 偽の Windows を $T/c に作る
WIN="$T/c/WINDOWS/system32"; YANK="$T/c/Users/t/AppData/Local/Microsoft/WinGet/Links/win32yank.exe"
mkdir -p "$T/bin" "$WIN/WindowsPowerShell/v1.0" "$(dirname "$YANK")"
cat > "$WIN/cmd.exe" <<'SH'
#!/bin/sh
printf '%s\r\n' 'C:\Users\t\AppData\Local'
SH
printf '#!/bin/sh\n[ "$1" = -u ] || exit 1\nprintf "%%s\\n" "$2" | sed -e "s|^C:|%s/c|" -e "s|\\\\\\\\|/|g"\n' "$T" > "$T/bin/wslpath"
chmod 755 "$WIN/cmd.exe" "$T/bin/wslpath"
: > "$WIN/WindowsPowerShell/v1.0/powershell.exe"; : > "$YANK"
run() { env -i HOME="$1" PATH="$T/bin:$WIN:/usr/bin:/bin" ${2:+WSL_DISTRO_NAME=$2} DOTFILES_LINKS_ONLY=1 DOTFILES_ALLOW_WORKTREE=1 sh "$ROOT/install.sh" 2>&1; }
run "$T/h1" Test >/dev/null
chk "WSL: powershell.exe を ~/.local/bin にリンクする" \
  test "$(readlink "$T/h1/.local/bin/powershell.exe")" = "$WIN/WindowsPowerShell/v1.0/powershell.exe"
chk "WSL: winget の win32yank.exe を ~/.local/bin にリンクする" test "$(readlink "$T/h1/.local/bin/win32yank.exe")" = "$YANK"
o2="$(run "$T/h1" Test)"
case "$o2" in *link:*|*warning*) ng "WSL: 2 回目は何も出さない: $o2" ;; *) ok "WSL: 2 回目は何も出さない" ;; esac
rm "$YANK"
o3="$(run "$T/h2" Test)"
case "$o3" in *warning:*win32yank*winget*) w=1 ;; *) w= ;; esac
chk "WSL: win32yank.exe が無ければリンクせず warning（powershell.exe はリンクする）" \
  test -n "$w" -a ! -e "$T/h2/.local/bin/win32yank.exe" -a ! -L "$T/h2/.local/bin/win32yank.exe" -a -L "$T/h2/.local/bin/powershell.exe"
o4="$(run "$T/h3" "")"
case "$o4" in *warning*) w=; ;; *) w=1 ;; esac
chk "WSL でなければリンクも warning も無い" test -n "$w" -a ! -L "$T/h3/.local/bin/powershell.exe" -a ! -L "$T/h3/.local/bin/win32yank.exe"

[ "$fail" = 0 ] && echo "acceptance wsl: ok"
[ "$fail" = 0 ]
