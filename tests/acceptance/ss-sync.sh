#!/bin/sh
# ss-sync の受け入れ検査（ARK-68 I1・M1・M2）: 本物の ssh / scp は使わず、呼び出しを記録するスタブを PATH の先頭に置き、HOME を一時ディレクトリにする
#   送信先が 2 行なら両方に送る（ssh が標準入力の targets の残りを飲まない）、同じ秒の 2 枚目は -2 の添字、
#   一部の送信先が失敗したら既読位置（last）を進めない、targets が読めなければ何もせず last も進めない
#   sh tests/acceptance/ss-sync.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/ss-sync.sh  通った項目も
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
mkdir -p "$H/Screenshots" "$H/.config/ss-sync" "$H/.local/state/ss-sync" "$H/bin"
printf '# 送信先\nnas\nnas2\n' > "$H/.config/ss-sync/targets"
# スタブ: 本物の ssh と同じく -n が無ければ標準入力を読み切る。呼び出しを 1 行ずつ記録。FAIL_HOST を含む呼び出しは失敗する
cat > "$H/bin/ssh" <<'EOF'
#!/bin/sh
case " $* " in *" -n "*) ;; *) cat >/dev/null ;; esac
echo "ssh $*" >> "$STUB_LOG"
case " $* " in *" ${FAIL_HOST:-__none__} "*) exit 255 ;; esac
exit 0
EOF
cat > "$H/bin/scp" <<'EOF'
#!/bin/sh
echo "scp $*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$H/bin/ssh" "$H/bin/scp"
LAST="$H/.local/state/ss-sync/last"
LOG="$H/.local/state/ss-sync/log"
run() { : > "$H/calls"; HOME="$H" PATH="$H/bin:$PATH" STUB_LOG="$H/calls" FAIL_HOST="${1:-}" sh "$ROOT/bin/ss-sync"; }
reset() { touch -t 202001010000 "$LAST"; rm -f "$H/.local/state/ss-sync/next"; }

# 既読位置を古い時刻にして、同じ秒の 2 枚を置く
reset
touch -t 202601021112.33 "$H/Screenshots/a.png" "$H/Screenshots/b.png"
run
grep -q '^ssh .* nas ' "$H/calls" && grep -q '^ssh .* nas2 ' "$H/calls" && ok "送信先の 2 行とも ssh を呼ぶ（ssh が targets の残りを飲まない）" \
  || ng "送信先の 2 行目に送られない: $(cat "$H/calls")"
[ "$(grep -c '^scp ' "$H/calls")" = 2 ] && ok "送信先の 2 行とも scp を呼ぶ" || ng "scp の回数が 2 でない: $(grep -c '^scp ' "$H/calls")"
grep -q 'ss-20260102-111233\.png' "$H/calls" && grep -q 'ss-20260102-111233-2\.png' "$H/calls" \
  && ok "名前は ss-YYYYmmdd-HHMMSS.png、同じ秒の 2 枚目は -2 の添字" || ng "名前が違う: $(grep '^scp' "$H/calls" | head -1)"
[ "$LAST" -nt "$H/Screenshots/a.png" ] && ok "全送信先に送れたので既読位置が進む" || ng "既読位置が進まない"

# 一部の送信先が失敗
reset; touch "$H/Screenshots/c.png"
run nas2
grep -q 'FAILED to nas2' "$LOG" && ok "失敗した送信先を log に書く" || ng "失敗が log に無い"
[ ! "$LAST" -nt "$H/Screenshots/c.png" ] && [ -f "$H/.local/state/ss-sync/next" ] && ok "一部の送信先が失敗したら既読位置を進めない（次回再送）" || ng "失敗したのに既読位置が進んだ"

# targets が読めない
reset; touch "$H/Screenshots/d.png"; mv "$H/.config/ss-sync/targets" "$H/targets.away"
run
[ ! "$LAST" -nt "$H/Screenshots/d.png" ] && ok "targets が読めなければ既読位置を進めない" || ng "targets が無いのに既読位置が進んだ（そのスクショは二度と送られない）"
grep -q 'no targets' "$LOG" && ok "targets が無いことを log に書く" || ng "targets が無いことが log に無い"

[ "$fail" = 0 ] && echo "acceptance ss-sync: ok"
[ "$fail" = 0 ]
