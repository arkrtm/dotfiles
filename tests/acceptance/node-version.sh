#!/bin/sh
# Node の版の受け入れ検査: プロジェクトが .node-version・.nvmrc・mise.toml で決めた版を、非対話の zsh・bash -lc・対話の zsh が使い、
# 指定の無い場所は mise の lts。npm・npx・corepack も同じ版の node で動く。
# 一時 HOME に shell/ と config/mise/config.toml をリンクし、本物の mise と、版を出すだけの偽の node（ネットワークを使わない）で確かめる。
# mise か zsh が無い端末（CI）では省く。本物の Node は tests/install-nosudo.sh が確かめる
#   sh tests/acceptance/node-version.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/node-version.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
skip() { echo "省いた $1"; }
chk() { n="$1"; shift; if "$@"; then ok "$n"; else ng "$n"; fi; }
ZSH="$(command -v zsh || true)"; MISE="$(command -v mise || true)" # env -i の前に決める
if [ -z "$ZSH" ] || [ -z "$MISE" ]; then skip "Node の版の検査（mise か zsh が無い）"; echo "acceptance node-version: ok"; exit 0; fi

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"

H="$T/h"; mkdir -p "$H/.config/mise" "$H/.local/bin" "$H/p" "$H/nv" "$H/nr" "$H/mt" "$H/miss"
for f in zshenv zprofile zshrc bashrc bash_profile; do ln -s "$ROOT/shell/$f" "$H/.$f"; done
ln -s "$ROOT/config/mise/config.toml" "$H/.config/mise/config.toml"
ln -s "$MISE" "$H/.local/bin/mise"
echo 22 > "$H/nv/.node-version"; echo v22 > "$H/nr/.nvmrc"; printf '[tools]\nnode = "20"\n' > "$H/mt/mise.toml"; echo 18 > "$H/miss/.node-version"
# r <ディレクトリ> <PATH> <コマンド…>: 一時 HOME のそのディレクトリで、空の環境から動かす。標準出力だけを返す（mise の警告は標準エラー）。
# MISE_OFFLINE: ほかの道具の版を探しにネットワークへ行かない
r() { r_d="$1"; r_p="$2"; shift 2; (cd "$H/$r_d" && env -i HOME="$H" PATH="$r_p" TERM=dumb MISE_OFFLINE=1 "$@" 2>/dev/null </dev/null); }
P0=/usr/bin:/bin
L="$(r p "$P0" "$MISE" alias get node lts)"
[ -n "$L" ] || ng "mise が node の lts の版を答えない"
# 偽の node は版を出すだけ。npm・npx・corepack は PATH の node の版を出す（本物も #!/usr/bin/env node で PATH の node を使う）
for v in 22.99.0 20.99.0 "$L.99.0"; do
  b="$H/.local/share/mise/installs/node/$v/bin"; mkdir -p "$b"
  printf '#!/bin/sh\necho v%s\n' "$v" > "$b/node"
  for t in npm npx corepack; do printf '#!/bin/sh\nexec node -v\n' > "$b/$t"; done
  chmod +x "$b"/*
done
r p "$P0" "$MISE" reshim >/dev/null

for c in nv:v22.99.0 nr:v22.99.0 mt:v20.99.0 "p:v$L.99.0"; do
  d="${c%%:*}"; want="${c#*:}"
  chk "$d: 非対話の zsh（zsh -c）の node は $want" test "$(r "$d" "$P0" "$ZSH" -c 'node -v')" = "$want"
  chk "$d: bash -lc の node は $want" test "$(r "$d" "$P0" bash -lc 'node -v')" = "$want"
  chk "$d: 対話の zsh（zsh -i -c）の node は $want" test "$(r "$d" "$P0" "$ZSH" -i -c 'node -v')" = "$want"
done
chk "npm・npx・corepack は .node-version の版の node で動く" test "$(r nv "$P0" "$ZSH" -c 'npm; npx; corepack' | tr '\n' ' ')" = "v22.99.0 v22.99.0 v22.99.0 "
chk "入っていない版を指定した場所では、ほかの版で黙って動かない" test -z "$(r miss "$P0" "$ZSH" -c 'node -v')"
# 対話の zsh（mise activate が起動した場所の node を PATH の先頭に置く）から起動したもの
act="$(r p "$P0" "$ZSH" -i -c 'print -r -- "$PATH"')"
chk "対話の zsh から起動した非対話の zsh・bash -lc も、場所の版を使う（mise activate が置いた node より shims が先）" \
  test "$(r nv "$act" "$ZSH" -c 'node -v')/$(r nv "$act" bash -lc 'node -v')" = v22.99.0/v22.99.0

[ "$fail" = 0 ] && echo "acceptance node-version: ok"
[ "$fail" = 0 ]
