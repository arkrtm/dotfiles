#!/usr/bin/env bash
# Claude Code のステータスライン（Nerd Font アイコン付き 2 行）。macOS 標準の bash 3.2 でも動く書き方
# 1 行目: Claude のモデルと effort → Codex（レビュー役）のモデルと effort → ブランチ、2 行目: コンテキスト・5 時間・週の上限のメーター（緑 → 黄 → 赤。それぞれの前に Claude のアイコン）→ Codex のアイコンと 5 時間・週の上限のメーター。アイコンは Claude を橙、Codex を白
# herdr の中では、この pane の名前を main · モデル effort にする（agent-pane のサブエージェントの pane と見分ける）
in=$(cat)
# jq は mise の shim を通すと 1 回 約 0.1 秒かかるので、実体を直接呼ぶ（mise が無い・失敗したら PATH の jq）
JQ=$(mise which jq 2>/dev/null) && [ -x "$JQ" ] || JQ=jq
get() { "$JQ" -r "$1 // empty" <<<"$in"; }

# アイコンは UTF-8 のバイト列で指定（エディタで文字化けしないように）
I_CLAUDE=$(printf '\033[38;5;173m\xee\xb2\x82\033[0m')  # nf-cod-claude   U+EC82（Nerd Fonts 3.5.0 以降）。橙
I_OPENAI=$(printf '\033[97m\xee\xb2\x81\033[0m')  # nf-cod-openai   U+EC81（同上）。白
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

# 2 行目: コンテキスト・5 時間・週のメーター。それぞれの前に Claude のアイコン
line2=""
ctx=$(get .context_window.used_percentage)
# 使用率を context-nudge（PostToolUse のフック。入力に使用率が無い）に渡す
sid=$(get .session_id)
case "$sid" in ''|.|..|*/*) ;; *) [ -n "$ctx" ] && d="${XDG_STATE_HOME:-$HOME/.local/state}/claude-context" && mkdir -p "$d" 2>/dev/null && printf '%s\n' "${ctx%.*}" > "$d/$sid" 2>/dev/null ;; esac
[ -n "$ctx" ] && line2+="$I_CLAUDE $(meter "$I_CTX" "$ctx" 50 70)   "
h5=$(get .rate_limits.five_hour.used_percentage)
if [ -n "$h5" ]; then
  line2+="$I_CLAUDE $(meter "$I_5H" "$h5" 50 80)"
  r5=$(get .rate_limits.five_hour.resets_at)
  [ -n "$r5" ] && line2+=" ${DIM}${I_RESET} $(hm "$r5")${R}"
  line2+="   "
fi
d7=$(get .rate_limits.seven_day.used_percentage)
[ -n "$d7" ] && line2+="$I_CLAUDE $(meter "$I_7D" "$d7" 50 80)   "

# Codex の使用量: 更新の新しいセッションから、記録のある 2 ファイルの最後の 5 行ずつを古い順に集める（ファイルが数 MB あるので jq には grep で絞った行だけを渡す。
# 再開したセッションは古いファイルに追記されるので、名前でなく更新時刻で選ぶ）
# shortcut: 2 ファイルとも最後の 5 行が読めない行（} で終わるのに JSON でない）だけなら出さない。Codex を並列で何本も動かす使い方になったら増やす
days=("${CODEX_HOME:-$HOME/.codex}/sessions"/*/*/*/); files=()
# shortcut: 新しい 7 日分の日のディレクトリだけを見る（引数が多すぎて ls が失敗しないように。7 日より前に始めて再開したセッションは見ない）
for dd in "${days[@]:$((${#days[@]} > 7 ? ${#days[@]} - 7 : 0))}"; do files+=("$dd"*.jsonl); done
l=""; n=0
while ((n < 2)) && IFS= read -r f; do
  # 読めないファイルがあると grep は 2 を返すので、終了コードでなく出力で決める。書き込み途中の行は } で終わらないことが多いので、途切れた行だけのファイルは数えない
  m=$(grep -F '"rate_limits":{"limit_id":"codex"' "$f" 2>/dev/null | grep '}$' | tail -n 5); [ -n "$m" ] || continue
  l="$m"$'\n'"$l"; n=$((n + 1))
done < <(ls -t "${files[@]}" 2>/dev/null | head -n 20)
cr=""
# 窓は位置（primary・secondary）でなく長さ（分）で見分ける。リセット時刻を過ぎた窓は 0%（時刻は出さない）
[ -n "$l" ] && cr=$("$JQ" -Rnr 'last(inputs | fromjson? | .payload.rate_limits) // empty | [.primary, .secondary] | map(select(.)) | sort_by(.window_minutes)[]
  | if .resets_at < now then "\(.window_minutes) 0" else "\(.window_minutes) \(.used_percent) \(.resets_at)" end' <<<"$l" 2>/dev/null)
cx=""
[ -n "$cr" ] && while read -r w p r; do
  case "$w" in
    300) cx+="$(meter "$I_5H" "$p" 50 80)"; [ -n "$r" ] && cx+=" ${DIM}${I_RESET} $(hm "$r")${R}"; cx+="   " ;;
    10080) cx+="$(meter "$I_7D" "$p" 50 80)   " ;;
  esac
done <<<"$cr"
[ -n "$cx" ] && line2+="${I_OPENAI} ${cx}"

# herdr の中では、この pane の名前を「main · モデルの正式な名前 effort」にする（agent-pane のサブエージェントの pane と見分ける）。
# 今の名前と違うときだけ付ける（herdr を立ち上げ直して名前が消えても付け直せるよう、覚えずに毎回聞く。pane get は 2 ms ほど）
if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] && mid=$(get .model.id) && [ -n "$mid" ]; then
  pn="main · ${mid%%\[*}${eff:+ $eff}"
  [ "$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | "$JQ" -r '.result.pane.label // empty' 2>/dev/null)" = "$pn" ] || herdr pane rename "$HERDR_PANE_ID" "$pn" >/dev/null 2>&1
fi

printf '%s\n%s\n' "$line1" "$line2"
