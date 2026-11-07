#!/bin/sh
# ssh・git・tmux と herdr の既定の受け入れ検査。
# ssh は ssh/config の Include を絶対パスにした合成で ssh -G を見る（相対の Include は ~/.ssh で解決され、リポジトリのファイルを読まない）。
# mac / linux（config.mux あり）は多重化と keepalive、Windows と同じ形（config.mux なし）は keepalive だけで多重化もソケットのパスも無い。
# config.local（先に読む）でホストの多重化を止められる
#   sh tests/acceptance/tool-defaults.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/tool-defaults.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
chk() { n="$1"; shift; if "$@"; then ok "$n"; else ng "$n"; fi; }

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"

# ssh
L="$T/config.local"; printf 'Host pinned\n  ControlMaster no\n  ControlPath none\n' > "$L" # README に書く止め方と同じ
sed -e "s|^Include config.local\$|Include $L|" -e "s|^Include config.mux\$|Include $ROOT/ssh/config.mux|" "$ROOT/ssh/config" > "$T/unix"
chk "ssh/config は config.local と config.mux を Include する" test "$(grep -c '^Include /' "$T/unix")" = 2
g="$(ssh -G -F "$T/unix" example.invalid 2>/dev/null)"
for w in 'controlmaster auto' 'controlpersist 600' 'serveraliveinterval 60' 'addkeystoagent true'; do
  chk "mac / linux の ssh -G: $w" sh -c 'printf "%s\n" "$1" | grep -qx "$2"' sh "$g" "$w"
done
chk "mac / linux の ssh -G: ControlPath は ~/.ssh/cm-%C" sh -c 'printf "%s\n" "$1" | grep -qE "^controlpath .*/\.ssh/cm-[0-9a-f]{40}\$"' sh "$g"
p="$(ssh -G -F "$T/unix" pinned 2>/dev/null)"
chk "config.local で止めたホストは既定より勝ち、使い回すソケットのパスも無い（ControlMaster no だけでは残る接続を使う）" \
  sh -c 'printf "%s\n" "$1" | grep -qx "controlmaster false" && printf "%s\n" "$1" | grep -q "^serveraliveinterval " && ! printf "%s\n" "$1" | grep -q "^controlpath "' sh "$p"
sed -e '/^Include config.mux$/d' -e "s|^Include config.local\$|Include $L|" "$ROOT/ssh/config" > "$T/win"
w="$(ssh -G -F "$T/win" example.invalid 2>/dev/null)"
chk "config.mux の無い端末（Windows）は多重化せずソケットのパスも無く、keepalive は効く" \
  sh -c 'printf "%s\n" "$1" | grep -qx "controlmaster false" && ! printf "%s\n" "$1" | grep -q "^controlpath " && printf "%s\n" "$1" | grep -qx "serveraliveinterval 60"' sh "$w"
chk "install.sh が config.mux をリンクする" grep -q '^ssh/config\.mux  *\.ssh/config\.mux$' "$ROOT/install.sh"
chk "install.sh が config.mux を 600 にする" grep -q '^chmod 600 .*ssh/config\.mux' "$ROOT/install.sh"

# git
G="$ROOT/config/git/config"
for kv in merge.conflictStyle=diff3 diff.algorithm=histogram rebase.autoSquash=true rebase.updateRefs=true transfer.fsckObjects=true rebase.autoStash=true; do
  chk "git: ${kv%%=*} = ${kv#*=}" test "$(git config --file "$G" --get "${kv%%=*}" || true)" = "${kv#*=}"
done
R="$ROOT/config/git/README.md"
chk "config/git/README.md の業務の例に SSH 署名がある" sh -c 'grep -q "format = ssh" "$1" && grep -q "gpgSign = true" "$1" && grep -q signingKey "$1"' sh "$R"

[ "$fail" = 0 ] && echo "acceptance tool-defaults: ok"
[ "$fail" = 0 ]
