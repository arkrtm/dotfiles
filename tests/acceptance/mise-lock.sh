#!/bin/sh
# mise.lock の受け入れ検査: lock のプラットフォームがちょうど 4 つで、どの項目にも url と checksum がある。
# mise がある端末は、各プラットフォームで lock だけから入れられるか（ネットワーク無しの mise install --locked --dry-run）も見る。CI（mise 無し）は省く。
#   sh tests/acceptance/mise-lock.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/mise-lock.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
skip() { echo "省いた $1"; }
chk() { n="$1"; shift; if "$@"; then ok "$n"; else ng "$n"; fi; }

K="$ROOT/config/mise/mise.lock"
chk "lock がある" test -s "$K"
p="$(sed -n 's/^\[tools\..*\."platforms\.\([a-z0-9-]*\)"\]$/\1/p' "$K" 2>/dev/null | sort -u | tr '\n' ' ')"
chk "lock のプラットフォームは linux-arm64・linux-x64・macos-arm64・windows-x64（${p:-なし}）" test "$p" = "linux-arm64 linux-x64 macos-arm64 windows-x64 "
# 項目（[tools.<名前>."platforms.<p>"]）ごとに url と checksum（<算法>:<16 進>）がある。無い項目の見出しを出す
bad="$(awk '
  function flush() { if (h != "" && !(u && c)) print h; h = "" }
  /^\[/ { flush(); if ($0 ~ /"platforms\.[a-z0-9-]+"\]$/) { h = $0; u = 0; c = 0 } next }
  h != "" && /^url = "https:\/\// { u = 1 }
  h != "" && /^checksum = "[a-z0-9]+:[0-9a-f]+"$/ { c = 1 }
  END { flush() }' "$K" 2>&1)"
chk "lock のどの項目にも url と checksum がある${bad:+（無い: $bad）}" test -z "$bad"

MISE="$(command -v mise || true)" # env -i の前に決める
if [ -z "$MISE" ]; then
  skip "各プラットフォームで lock だけから入れられるかの検査（mise が無い）"
else
  T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
  trap 'exit 1' HUP INT TERM
  T="$(trap '' HUP INT TERM; mktemp -d)"
  mkdir -p "$T/c" "$T/n" "$T/h"
  cp "$ROOT/config/mise/config.toml" "$K" "$T/c/"
  cp "$ROOT/config/mise/config.toml" "$T/n/"
  awk '/^\[tools\.jq\."platforms\.linux-x64"\]$/ { t = 1 } t && /^checksum = / { t = 0; next } { print }' "$K" > "$T/n/mise.lock"

  # plan <設定の置き場> <os> <arch> <除く道具>: 空の置き場に lock だけから入れる計画（入れない・ネットワーク無し）。
  # config.toml の os は本当の OS を見るので、その OS で入れない道具は MISE_DISABLE_TOOLS で除く
  plan() { (cd "$T/h" && env -i HOME="$T/h" PATH=/usr/bin:/bin MISE_CONFIG_DIR="$1" MISE_DATA_DIR="$T/d" MISE_CACHE_DIR="$T/cache" \
    MISE_STATE_DIR="$T/s" MISE_OFFLINE=1 MISE_OS="$2" MISE_ARCH="$3" MISE_DISABLE_TOOLS="$4" "$MISE" install --locked --dry-run 2>&1 </dev/null); }
  node="$(sed -n '/^\[\[tools\.node\]\]$/{n;s/^version = "\(.*\)"$/\1/p;}' "$K")"
  for e in linux:x64: linux:arm64: macos:arm64:aqua:eza-community/eza windows:x64:aqua:tmux/tmux-builds; do
    os="${e%%:*}"; r="${e#*:}"; arch="${r%%:*}"; dis="${r#*:}"
    out="$(plan "$T/c" "$os" "$arch" "$dis")"; rc=$?
    case "$rc:$out" in
      0:*"node@$node "*"would install"*) ok "$os-$arch: lock の URL と checksum だけで入れられる（node $node を含む）" ;;
      *) ng "$os-$arch: lock だけでは入れられない: $(printf '%s\n' "$out" | grep -v 'would install')" ;;
    esac
  done
  out="$(plan "$T/n" linux x64 "")"; rc=$?
  case "$rc:$out" in
    0:*) ng "検査そのもの: checksum を消した lock でも通ってしまう" ;;
    *"No lockfile checksum"*) ok "検査そのもの: checksum の無い項目があれば落ちる" ;;
    *) ng "検査そのもの: 理由の違う失敗: $out" ;;
  esac
fi

[ "$fail" = 0 ] && echo "acceptance mise-lock: ok"
[ "$fail" = 0 ]
