#!/bin/sh
# ステータスラインの受け入れ検査（ARK-86）: サンプルの入力で 2 行を出し、1 行目にモデル・effort・ブランチ、2 行目にコンテキスト・5 時間（リセット時刻）・週の %。
# Codex の設定（CODEX_HOME/config.toml の先頭の model と model_reasoning_effort）があれば 1 行目の右に出す（ARK-87）。
# rate_limits・effort・Codex の設定が無く git でないディレクトリでも終了コード 0 で、1 行目はモデルだけ、2 行目はコンテキストだけ
#   sh tests/acceptance/statusline.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/statusline.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SL="$ROOT/config/claude/statusline.sh"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git init -q -b feature/x "$T/repo"
reset=1792738800
mkdir -p "$T/codex"; printf 'model = "gpt-6.1-sol"\nmodel_reasoning_effort = "xhigh"\n\n[profiles.x]\nmodel = "other"\n' > "$T/codex/config.toml"
export CODEX_HOME="$T/codex"
hm="$(date -d "@$reset" +%H:%M 2>/dev/null || date -r "$reset" +%H:%M)"

out="$(printf '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":43},"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":%s},"seven_day":{"used_percentage":31}}}' "$T/repo" "$reset" | bash "$SL")"; rc=$?
l1="$(printf '%s\n' "$out" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | sed -n 2p)"
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && ok "サンプルの入力で 2 行を出す" || ng "rc=$rc 出力: $out"
case "$l1" in *"Opus 5.5"*high*feature/x*"codex gpt-6.1-sol xhigh"*) ok "1 行目にモデル・effort・ブランチ・Codex のモデルと effort" ;; *) ng "1 行目: $l1" ;; esac
case "$l1" in *other*) ng "Codex のモデルを表（profiles）から読んだ: $l1" ;; esac
case "$l2" in *43%*62%*"$hm"*31%*) ok "2 行目にコンテキスト・5 時間とリセット時刻・週" ;; *) ng "2 行目: $l2" ;; esac

out="$(printf '{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":12.6}}' "$T" | CODEX_HOME="$T/none" bash "$SL")"; rc=$?
l1="$(printf '%s\n' "$out" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | sed -n 2p)"
[ "$rc" = 0 ] && ok "rate_limits が無く git でなくても 0" || ng "rate_limits が無いとき rc=$rc"
case "$l1" in *"Opus 5.5") ok "effort が無いと 1 行目はモデルだけ" ;; *) ng "effort が無いときの 1 行目: $l1" ;; esac
[ "$(printf '%s' "$l2" | tr -cd '%' | wc -c | tr -d ' ')" = 1 ] && case "$l2" in *12%*) true ;; *) false ;; esac \
  && ok "rate_limits が無いと 2 行目はコンテキストだけ" || ng "rate_limits が無いときの 2 行目: $l2"

[ "$fail" = 0 ] && echo "acceptance statusline: ok"
[ "$fail" = 0 ]
