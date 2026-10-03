#!/bin/sh
# ARK-52 D の受け入れ検査: dotfiles をプラグイン harness に切り替えた後の状態（AC9 の静的な部分）。
# 検証一式（sh tests/install.sh・DOCKER='ssh nas docker' sh tests/install-nosudo.sh）は別に実行する。
# LIVE=1 のときだけ、本物の claude のセッションで SessionStart の注入（AC5）も確かめる（モデルを呼ぶので数十秒・課金あり）
#   sh tests/acceptance/plugin-switch.sh
#   LIVE=1 sh tests/acceptance/plugin-switch.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
check() { d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi; }
absent() { [ ! -e "$ROOT/$1" ] && [ ! -L "$ROOT/$1" ]; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い"; exit 1; }

# settings.json: ハーネスの hooks が無く、harness@harness が有効で、marketplace は github の arkrtm/harness
S="$ROOT/config/claude/settings.json"
check "settings.json の hooks にハーネスの command が無い" \
  sh -c "! jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -qi harness"
check "settings.json の hooks に agent-status・tinymemory の配線は残る" \
  sh -c "jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q agent-status && jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q tinymemory"
check "enabledPlugins の harness@harness が true" [ "$(jq -r '.enabledPlugins["harness@harness"]' "$S")" = true ]
check "extraKnownMarketplaces.harness は github の arkrtm/harness" \
  [ "$(jq -r '.extraKnownMarketplaces.harness.source | "\(.source) \(.repo)"' "$S")" = "github arkrtm/harness" ]

# 旧ハーネスのファイルが無い
for p in bin/harness-hook config/claude/skills config/claude/agents config/git/hooks docs/harness.md \
         tests/harness-hook.sh tests/e2e-flow.sh tests/skills.sh tests/review-snapshot.sh; do
  check "旧ハーネスの $p が無い" absent "$p"
done
check "tests/acceptance に旧ハーネスの検査（harness-*.sh）が無い" sh -c "! ls '$ROOT'/tests/acceptance/harness-*.sh"
# install.sh の LINKS 表（ヒアドキュメントの「リンク元 リンク先」の行）にハーネスのものが無い
links="$(awk '/^(config|bin|shell)\/[^ ]+ +\./' "$ROOT/install.sh")"
check "install.sh の LINKS 表を読めた" [ -n "$links" ]
check "install.sh の LINKS 表にハーネス（harness-hook・skills・agents・git hooks）が無い" \
  sh -c "! printf '%s\n' \"\$1\" | grep -Eq 'harness|skills|agents|git/hooks'" _ "$links"

# グローバルの CLAUDE.md: 「作業の進め方」が無く、個人の規則の節は残る
C="$ROOT/config/claude/CLAUDE.md"
check "グローバルの CLAUDE.md に「作業の進め方」の節が無い" sh -c "! grep -q '^#* *作業の進め方' '$C'"
for h in 作業の哲学 Linear Karpathy Ponytail スクリーンショット; do
  check "グローバルの CLAUDE.md に「$h」の節が残る" grep -Eq "^#+ .*$h" "$C"
done
check "グローバルの CLAUDE.md の skill 名はプラグインの形（/harness:x）" \
  sh -c "! grep -Eo '\`/(accept|verify|review|issue|wrap-up|design|implement|diagnose|tdd)\b' '$C' | grep -q ."

# git の共通 hooks の場所: dotfiles の設定がプラグインの data の git-hooks を指し、この端末で効いていて、run-hook がある
G="$ROOT/config/git/config"
hp="$(git config -f "$G" --get core.hooksPath)"
check "config/git/config の core.hooksPath はプラグインの data の git-hooks（$hp）" [ "$hp" = "~/.claude/plugins/data/harness-harness/git-hooks" ]
eff="$(git config --show-scope --get-all core.hooksPath | sed -n 's/^global\t//p' | tail -1)"
check "この端末で効いている global の core.hooksPath も同じ（$eff）" [ "$eff" = "$hp" ]
check "その場所に run-hook と pre-commit がある" \
  sh -c "[ -x \"\$HOME/.claude/plugins/data/harness-harness/git-hooks/run-hook\" ] && [ -e \"\$HOME/.claude/plugins/data/harness-harness/git-hooks/pre-commit\" ]"

if [ -n "${LIVE:-}" ]; then
  MARK='# harness: 作業の手順（プラグイン harness が SessionStart で読み込む）'
  D="$(mktemp -d)"; git -C "$D" init -q
  ans="$(cd "$D" && claude -p '「# harness:」で始まる行がコンテキストにあれば、その行だけをそのまま 1 行で答えて。無ければ「なし」。ツールは使わない。' \
          --output-format json --debug-file "$D/start.txt" | jq -r '.result, .session_id')"
  sid="$(printf '%s\n' "$ans" | tail -1)"
  check "（LIVE）startup のセッションが印の行を答える" sh -c "printf '%s' \"\$1\" | grep -Fq \"\$2\"" _ "$ans" "$MARK"
  (cd "$D" && claude -p '/compact' --resume "$sid" --output-format json --debug-file "$D/compact.txt" >/dev/null)
  (cd "$D" && claude -p '/clear' --resume "$sid" --output-format json --debug-file "$D/clear.txt" >/dev/null)
  cat "$D"/start.txt "$D"/compact.txt "$D"/clear.txt > "$D/all.txt"
  for src in startup resume compact clear; do
    check "（LIVE）SessionStart:$src でプラグインの hook が動く" grep -q "Hook SessionStart:$src (SessionStart) success" "$D/all.txt"
  done
  P="$(jq -r '.plugins["harness@harness"][0].installPath' "$HOME/.claude/plugins/installed_plugins.json")"
  n="$(printf '%s\n\n' "$MARK" | cat - "$P/rules/workflow.md" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')"
  check "（LIVE）注入した長さが、印の行と rules/workflow.md の全文の長さ（$n 字）と同じ" \
    grep -q "harness-hook\" session-start) provided additionalContext ($n chars)" "$D/all.txt"
fi

[ "$fail" = 0 ] && echo "acceptance plugin-switch: ok"
[ "$fail" = 0 ]
