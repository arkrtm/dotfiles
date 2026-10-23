#!/usr/bin/env bash
# Claude Code のステータスライン（Nerd Font アイコン付き 2 行）。macOS 標準の bash 3.2 でも動く書き方
# 1 行目: モデルとブランチ、2 行目: コンテキスト・5 時間・週の上限のメーター（緑 → 黄 → 赤）
in=$(cat)
get() { jq -r "$1 // empty" <<<"$in"; }

# アイコンは UTF-8 のバイト列で指定（エディタで文字化けしないように）
I_MODEL=$(printf '\xef\x83\xa7')   # nf-fa-bolt      U+F0E7
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

# 1 行目: モデルとブランチ
line1="$I_MODEL $(get .model.display_name)"
br=$(git -C "$(get .workspace.current_dir)" branch --show-current 2>/dev/null)
[ -n "$br" ] && line1+="   ${DIM}${I_BRANCH} ${br}${R}"

# 2 行目: コンテキスト・5 時間・週のメーター
line2=""
ctx=$(get .context_window.used_percentage)
[ -n "$ctx" ] && line2+="$(meter "$I_CTX" "$ctx" 50 70)   "
h5=$(get .rate_limits.five_hour.used_percentage)
if [ -n "$h5" ]; then
  line2+="$(meter "$I_5H" "$h5" 50 80)"
  r5=$(get .rate_limits.five_hour.resets_at)
  [ -n "$r5" ] && line2+=" ${DIM}${I_RESET} $(hm "$r5")${R}"
  line2+="   "
fi
d7=$(get .rate_limits.seven_day.used_percentage)
[ -n "$d7" ] && line2+="$(meter "$I_7D" "$d7" 50 80)"

printf '%s\n%s\n' "$line1" "$line2"
