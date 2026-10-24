#!/usr/bin/env bash
# Claude Code のステータスライン（Nerd Font アイコン付き 2 行）。macOS 標準の bash 3.2 でも動く書き方
# 1 行目: Claude のモデルと effort → Codex（レビュー役）のモデルと effort → ブランチ、2 行目: コンテキスト・5 時間・週の上限のメーター（緑 → 黄 → 赤）→ Codex の 5 時間・週の上限のメーター（ARK-95）
in=$(cat)
get() { jq -r "$1 // empty" <<<"$in"; }

# アイコンは UTF-8 のバイト列で指定（エディタで文字化けしないように）
I_CLAUDE=$(printf '\xee\xb2\x82')  # nf-cod-claude   U+EC82（Nerd Fonts 3.5.0 以降）
I_OPENAI=$(printf '\xee\xb2\x81')  # nf-cod-openai   U+EC81（同上）
I_BRANCH=$(printf '\xee\x82\xa0')  # branch          U+E0A0
I_CTX=$(printf '\xef\x87\x80')     # nf-fa-database  U+F1C0
I_5H=$(printf '\xef\x80\x97')      # nf-fa-clock_o   U+F017
I_7D=$(printf '\xef\x81\xb3')      # nf-fa-calendar  U+F073
I_RESET=$(printf '\xef\x80\xa1')   # nf-fa-refresh   U+F021
R=$(printf '\033[0m'); DIM=$(printf '\033[2m')

hm()  { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }
# 値 黄のしきい値 赤のしきい値 → 色
col() { if (($1 >= $3)); then printf '\033[31m'; elif (($1 >= $2)); then printf '\033[33m'; else printf '\033[32m'; fi; }
# 10 マスのバー
bar() { local n=$((($1 + 5) / 10)) s="" i; for ((i = 0; i < 10; i++)); do if ((i < n)); then s+="█"; else s+="░"; fi; done; printf '%s' "$s"; }
# アイコン 値 黄 赤
meter() { local p=${2%.*}; printf '%s%s %s %3d%%%s' "$(col "$p" "$3" "$4")" "$1" "$(bar "$p")" "$p" "$R"; }

# 1 行目: Claude のモデル・effort（対応していないモデルでは入力に無い）→ Codex → ブランチ
line1="$I_CLAUDE $(get .model.display_name)"
eff=$(get .effort.level)
[ -n "$eff" ] && line1+=" ${DIM}${eff}${R}"
# Codex の設定の先頭（最初の表より前）の model と model_reasoning_effort
cx() { awk -F'"' -v k="$1" '/^\[/ { exit } $1 ~ "^" k " *= *$" { print $2 }' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null; }
cm=$(cx model); ce=$(cx model_reasoning_effort)
[ -n "$cm" ] && line1+="   ${I_OPENAI} ${cm}" && [ -n "$ce" ] && line1+=" ${DIM}${ce}${R}"
br=$(git -C "$(get .workspace.current_dir)" branch --show-current 2>/dev/null)
[ -n "$br" ] && line1+="   ${DIM}${I_BRANCH} ${br}${R}"

# 2 行目: コンテキスト・5 時間・週のメーター
line2=""
ctx=$(get .context_window.used_percentage)
# 使用率を context-nudge（PostToolUse のフック。入力に使用率が無い）に渡す（ARK-90）
sid=$(get .session_id)
case "$sid" in ''|.|..|*/*) ;; *) [ -n "$ctx" ] && d="${XDG_STATE_HOME:-$HOME/.local/state}/claude-context" && mkdir -p "$d" 2>/dev/null && printf '%s\n' "${ctx%.*}" > "$d/$sid" 2>/dev/null ;; esac
[ -n "$ctx" ] && line2+="$(meter "$I_CTX" "$ctx" 50 70)   "
h5=$(get .rate_limits.five_hour.used_percentage)
if [ -n "$h5" ]; then
  line2+="$(meter "$I_5H" "$h5" 50 80)"
  r5=$(get .rate_limits.five_hour.resets_at)
  [ -n "$r5" ] && line2+=" ${DIM}${I_RESET} $(hm "$r5")${R}"
  line2+="   "
fi
d7=$(get .rate_limits.seven_day.used_percentage)
[ -n "$d7" ] && line2+="$(meter "$I_7D" "$d7" 50 80)   "

# Codex の使用量（ARK-95）: 更新の新しいセッションから遡り、rate_limits のある最新の記録（ファイルが数 MB あるので jq には grep で絞った行だけを渡す）
# 更新の新しいファイルから、記録のある 2 ファイルの最後の 5 行ずつを古い順に集める（再開したセッションは古いファイルに追記されるので、名前でなく更新時刻で選ぶ）
# shortcut: 2 ファイルとも最後の 5 行が途切れた行だけなら出さない。Codex を並列で何本も動かす使い方になったら増やす
l=""; n=0
while ((n < 2)) && IFS= read -r f; do
  # 読めないファイルがあると grep は 2 を返すので、終了コードでなく出力で決める
  m=$(grep -F '"rate_limits":{"limit_id":"codex"' "$f" 2>/dev/null | tail -n 5); [ -n "$m" ] || continue
  l="$m"$'\n'"$l"; n=$((n + 1))
done < <(ls -t "${CODEX_HOME:-$HOME/.codex}/sessions"/*/*/*/*.jsonl 2>/dev/null | head -n 20)
cr=""
# 窓は位置（primary・secondary）でなく長さ（分）で見分ける。リセット時刻を過ぎた窓は 0%（時刻は出さない）
[ -n "$l" ] && cr=$(jq -Rnr 'last(inputs | fromjson? | .payload.rate_limits) // empty | [.primary, .secondary] | map(select(.)) | sort_by(.window_minutes)[]
  | if .resets_at < now then "\(.window_minutes) 0" else "\(.window_minutes) \(.used_percent) \(.resets_at)" end' <<<"$l" 2>/dev/null)
cx=""
[ -n "$cr" ] && while read -r w p r; do
  case "$w" in
    300) cx+="$(meter "$I_5H" "$p" 50 80)"; [ -n "$r" ] && cx+=" ${DIM}${I_RESET} $(hm "$r")${R}"; cx+="   " ;;
    10080) cx+="$(meter "$I_7D" "$p" 50 80)   " ;;
  esac
done <<<"$cr"
[ -n "$cx" ] && line2+="${I_OPENAI} ${cx}"

printf '%s\n%s\n' "$line1" "$line2"
