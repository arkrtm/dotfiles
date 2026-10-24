#!/bin/sh
# ステータスラインの受け入れ検査（ARK-86）: サンプルの入力で 2 行を出し、1 行目に Claude（アイコン・モデル・effort）→ Codex（アイコン・モデル・effort）→ ブランチの順、2 行目にコンテキスト・5 時間（リセット時刻）・週の %。
# Codex の設定（CODEX_HOME/config.toml の先頭の model と model_reasoning_effort）があれば 1 行目の右に出す（ARK-87）。
# session_id があれば文脈の使用率を $XDG_STATE_HOME/claude-context/<session_id> に整数で書く（ARK-90。context-nudge が読む）。
# Codex のセッションの記録（CODEX_HOME/sessions の rate_limits のある更新の新しいファイルの最後の記録）があれば 2 行目の右に Codex のアイコンと 5 時間（リセット時刻）・週のメーター。窓は window_minutes で見分け、リセット時刻を過ぎた窓は 0%（ARK-95）。
# rate_limits・effort・Codex の設定と記録が無く git でないディレクトリでも終了コード 0 で、1 行目はモデルだけ、2 行目はコンテキストだけ
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
export XDG_STATE_HOME="$T/state" # 文脈の使用率の書き出し先（ARK-90）
git init -q -b feature/x "$T/repo"
reset=1792738800
I_CLAUDE=$(printf '\356\262\202')  # nf-cod-claude U+EC82
I_OPENAI=$(printf '\356\262\201')  # nf-cod-openai U+EC81
mkdir -p "$T/codex"; printf 'model = "gpt-6.1-sol"\nmodel_reasoning_effort = "xhigh"\n\n[profiles.x]\nmodel = "other"\n' > "$T/codex/config.toml"
export CODEX_HOME="$T/codex"
hm="$(date -d "@$reset" +%H:%M 2>/dev/null || date -r "$reset" +%H:%M)"

in1="$(printf '{"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":43},"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":%s},"seven_day":{"used_percentage":31}}}' "$T/repo" "$reset")"
out="$(printf '%s' "$in1" | bash "$SL")"; rc=$?
l1="$(printf '%s\n' "$out" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | sed -n 2p)"
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && ok "サンプルの入力で 2 行を出す" || ng "rc=$rc 出力: $out"
printf '{"session_id":"s-1","model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":43.7}}' | bash "$SL" >/dev/null
[ "$(cat "$T/state/claude-context/s-1" 2>/dev/null)" = 43 ] && ok "session_id があれば使用率を整数で書く（ARK-90）" || ng "使用率の書き出し: $(cat "$T/state/claude-context/s-1" 2>/dev/null)"
printf '{"session_id":"../x","context_window":{"used_percentage":50}}' | bash "$SL" >/dev/null
[ ! -e "$T/state/x" ] && ok "session_id に / があれば書かない" || ng "session_id の / で外に書いた"
case "$l1" in "$I_CLAUDE Opus 5.5"*high*"$I_OPENAI gpt-6.1-sol"*xhigh*feature/x*) ok "1 行目は Claude・Codex・ブランチの順で、公式のアイコン付き" ;; *) ng "1 行目: $l1" ;; esac
case "$l1" in *other*) ng "Codex のモデルを表（profiles）から読んだ: $l1" ;; esac
case "$l2" in *43%*62%*"$hm"*31%*) ok "2 行目にコンテキスト・5 時間とリセット時刻・週" ;; *) ng "2 行目: $l2" ;; esac

out="$(printf '{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":12.6}}' "$T" | CODEX_HOME="$T/none" bash "$SL")"; rc=$?
l1="$(printf '%s\n' "$out" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | sed -n 2p)"
[ "$rc" = 0 ] && ok "rate_limits が無く git でなくても 0" || ng "rate_limits が無いとき rc=$rc"
case "$l1" in *"Opus 5.5") ok "effort が無いと 1 行目はモデルだけ" ;; *) ng "effort が無いときの 1 行目: $l1" ;; esac
[ "$(printf '%s' "$l2" | tr -cd '%' | wc -c | tr -d ' ')" = 1 ] && case "$l2" in *12%*) true ;; *) false ;; esac \
  && ok "rate_limits が無いと 2 行目はコンテキストだけ" || ng "rate_limits が無いときの 2 行目: $l2"

# Codex の使用量（ARK-95）: CODEX_HOME/sessions/YYYY/MM/DD/*.jsonl の token_count の rate_limits
now=$(date +%s); f5=$((now + 3600)); f7=$((now + 86400)); past=$((now - 60))
hm5="$(date -d "@$f5" +%H:%M 2>/dev/null || date -r "$f5" +%H:%M)"
I_RESET=$(printf '\357\200\241') # nf-fa-refresh U+F021
win() { printf '{"used_percent":%s,"window_minutes":%s,"resets_at":%s}' "$1" "$2" "$3"; }
rl() { printf '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"%s","limit_name":null,"primary":%s,"secondary":%s,"plan_type":"prolite"}}}\n' "${3:-codex}" "$1" "$2"; }
cx2() { printf '%s' "$in1" | CODEX_HOME="$1" bash "$SL" | sed -n 2p; } # 2 行目
d="$T/u1/sessions/2026/10/24"; mkdir -p "$d"
rl "$(win 40.0 10080 "$f7")" "$(win 20.0 300 "$f5")" > "$d/rollout-a.jsonl" # primary が週: 位置でなく window_minutes で見分ける
l2="$(cx2 "$T/u1")"
case "$l2" in *31%*"$I_OPENAI"*" 20%"*"$hm5"*" 40%"*) ok "Codex は Claude のメーターの後に、アイコン・5 時間とリセット時刻・週の順" ;; *) ng "Codex の 5 時間と週: $l2" ;; esac
d="$T/u2/sessions/2026/10/24"; mkdir -p "$d"
rl "$(win 7.0 10080 "$f7")" null > "$d/rollout-a.jsonl"
c="$(cx2 "$T/u2")"; c="${c##*"$I_OPENAI"}"
[ "$(printf '%s' "$c" | tr -cd '%' | wc -c | tr -d ' ')" = 1 ] && case "$c" in *"  7%"*) true ;; *) false ;; esac \
  && ok "週の窓だけなら Codex は週のメーターだけ" || ng "Codex の週だけ: $c"
d="$T/u3/sessions/2026/10/24"; mkdir -p "$d"
rl "$(win 90.0 300 "$past")" "$(win 40.0 10080 "$f7")" > "$d/rollout-a.jsonl"
c="$(cx2 "$T/u3")"; c="${c##*"$I_OPENAI"}"
case "$c" in *"$I_RESET"*) ng "リセット済みの窓にリセット時刻を出した: $c" ;; *"  0%"*" 40%"*) ok "リセット時刻を過ぎた窓は 0% で、時刻は出さない" ;; *) ng "リセット済みの窓: $c" ;; esac
d="$T/u4/sessions/2026/10/24"; mkdir -p "$d"
printf '{"type":"session_meta","payload":{}}\n{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}\n' > "$d/rollout-a.jsonl"
printf '%s' "$in1" | CODEX_HOME="$T/u4" bash "$SL" >/dev/null && [ "$(cx2 "$T/u4")" = "$(cx2 "$T/none")" ] \
  && case "$(cx2 "$T/none")" in *"$I_OPENAI"*) false ;; *) true ;; esac \
  && ok "Codex のセッションや rate_limits が無ければ 2 行目は今までどおりで 0" || ng "Codex の使用量が無いときの 2 行目: $(cx2 "$T/u4")"
d="$T/u5/sessions/2026/10"; mkdir -p "$d/22" "$d/23" "$d/24"
rl "$(win 77.0 10080 "$f7")" null > "$d/22/rollout-2026-10-22T10-00-00-z.jsonl"
{ rl "$(win 10.0 10080 "$f7")" null; printf '{"type":"response_item","payload":{}}\n'; rl "$(win 33.0 10080 "$f7")" null; } > "$d/23/rollout-2026-10-23T10-00-00-a.jsonl"
printf '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}\n' > "$d/24/rollout-2026-10-24T09-00-00-b.jsonl"
rl null null premium > "$d/24/rollout-2026-10-24T10-00-00-c.jsonl"
touch -t 202610220900 "$d/22/"*.jsonl; touch -t 202610231000 "$d/23/"*.jsonl # 更新時刻: 22 日 < 23 日 < 24 日の 2 ファイル
touch -t 202610240900 "$d/24/rollout-2026-10-24T09-00-00-b.jsonl"; touch -t 202610241000 "$d/24/rollout-2026-10-24T10-00-00-c.jsonl"
c="$(cx2 "$T/u5")"; c="${c##*"$I_OPENAI"}"
case "$c" in *" 33%"*) ok "rate_limits の無い新しいファイルは飛ばし、その前のファイルの最後の記録を出す" ;; *) ng "前のファイルの最後の記録: $c" ;; esac
cut() { printf '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":'; } # 書き込み途中の行
d="$T/u6/sessions/2026/10/24"; mkdir -p "$d"
rl "$(win 33.0 10080 "$f7")" null > "$d/rollout-a.jsonl"
for x in b c d; do cut > "$d/rollout-$x.jsonl"; done
touch -t 202610240900 "$d/rollout-a.jsonl"; touch -t 202610241000 "$d/rollout-b.jsonl" "$d/rollout-c.jsonl" "$d/rollout-d.jsonl"
c="$(cx2 "$T/u6")"; c="${c##*"$I_OPENAI"}"
case "$c" in *" 33%"*) ok "書き込み途中の新しいファイルが続いても、その前の読める記録を出す" ;; *) ng "途切れた行が複数: $c" ;; esac
d="$T/u7/sessions/2026/10"; mkdir -p "$d/23" "$d/24"
rl "$(win 33.0 10080 "$f7")" null > "$d/23/rollout-a.jsonl"
cut > "$d/24/rollout-b.jsonl"
touch -t 202610230900 "$d/23/rollout-a.jsonl"; touch -t 202610240900 "$d/24/rollout-b.jsonl"
c="$(cx2 "$T/u7")"; c="${c##*"$I_OPENAI"}"
case "$c" in *" 33%"*) ok "最新の日に読める記録が無ければ前の日の記録を出す" ;; *) ng "日をまたぐ途切れ: $c" ;; esac
d="$T/u8/sessions/2026/10/24"; mkdir -p "$d"
rl "$(win 90.0 10080 "$f7")" null > "$d/rollout-2026-10-24T09-00-00-a.jsonl" # 名前は古いが、再開して追記されたので更新が新しい
rl "$(win 20.0 10080 "$f7")" null > "$d/rollout-2026-10-24T10-00-00-b.jsonl"
touch -t 202610241100 "$d/rollout-2026-10-24T09-00-00-a.jsonl"; touch -t 202610241000 "$d/rollout-2026-10-24T10-00-00-b.jsonl"
c="$(cx2 "$T/u8")"; c="${c##*"$I_OPENAI"}"
case "$c" in *" 90%"*) ok "再開したセッション（名前は古いが更新が新しいファイル）の記録を出す" ;; *) ng "再開したセッション: $c" ;; esac

[ "$fail" = 0 ] && echo "acceptance statusline: ok"
[ "$fail" = 0 ]
