#!/bin/sh
# Claude Code の構成の受け入れ検査: 開発の手順は superpowers、Linear の記録は dotfiles の skill（issue・wrap-up）。
# 自作のハーネス（プラグイン harness）はやめた（ARK-67。経緯は ARK-30・52・63〜66）。
# 検証一式（sh tests/install.sh・DOCKER='ssh nas docker' sh tests/install-nosudo.sh）は別に実行する。
# LIVE=1 のときだけ、本物の claude -p の新しいセッションで、プラグインと skill の見え方と、
# 空の設定の置き場で README の新しい端末の手順が通ること（ARK-64 AC3）も確かめる
# （haiku を 1 回呼び、marketplace を取得するので数十秒・数セントの課金あり）
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

# settings.json: ハーネスの hooks・プラグイン・marketplace が無く、superpowers・tinymemory が有効
S="$ROOT/config/claude/settings.json"
check "settings.json の hooks にハーネスの command が無い" \
  sh -c "! jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -qi harness"
check "settings.json の hooks に agent-status・tinymemory の配線は残る" \
  sh -c "jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q agent-status && jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q tinymemory"
for p in superpowers@claude-plugins-official tinymemory@tinymemory; do
  check "enabledPlugins の $p が true" [ "$(jq -r --arg p "$p" '.enabledPlugins[$p]' "$S")" = true ]
done
check "settings.json に harness のプラグインと marketplace が無い" \
  sh -c "! jq -e '(.enabledPlugins | has(\"harness@harness\")) or (.extraKnownMarketplaces | has(\"harness\"))' '$S'"
check "extraKnownMarketplaces.claude-plugins-official は github の anthropics/claude-plugins-official" \
  [ "$(jq -r '.extraKnownMarketplaces["claude-plugins-official"].source | "\(.source) \(.repo)"' "$S")" = "github anthropics/claude-plugins-official" ]

# skill は issue と wrap-up だけ。旧ハーネスのファイルが無い
check "config/claude/skills は issue と wrap-up だけ" [ "$(ls "$ROOT/config/claude/skills" | tr '\n' ' ')" = "issue wrap-up " ]
for p in bin/harness-hook config/claude/agents config/git/hooks docs/harness.md .harness-verify .harness-code \
         tests/harness-hook.sh tests/e2e-flow.sh tests/skills.sh tests/review-snapshot.sh; do
  check "旧ハーネスの $p が無い" absent "$p"
done
check "tests/acceptance に旧ハーネスの検査（harness-*.sh）が無い" sh -c "! ls '$ROOT'/tests/acceptance/harness-*.sh"
# install.sh の LINKS 表（「リンク元 リンク先」の行）: skill の issue・wrap-up があり、ハーネスのものが無い
links="$(awk '/^(config|bin|shell)\/[^ ]+ +\./' "$ROOT/install.sh")"
check "install.sh の LINKS 表を読めた" [ -n "$links" ]
check "install.sh の LINKS 表に skill の issue と wrap-up がある" \
  sh -c "printf '%s\n' \"\$1\" | grep -q 'skills/issue ' && printf '%s\n' \"\$1\" | grep -q 'skills/wrap-up '" _ "$links"
check "install.sh の LINKS 表にハーネス（harness-hook・agents・git hooks）が無い" \
  sh -c "! printf '%s\n' \"\$1\" | grep -Eq 'harness|agents|git/hooks'" _ "$links"
check "install.sh は uv のリンク（~/.local/libexec/uv）を置かない" sh -c "! grep -q 'libexec' '$ROOT/install.sh'"

# グローバルの CLAUDE.md: 手順は superpowers の skill、Linear の記録は /issue・/wrap-up。harness はやめた 1 文だけ
C="$ROOT/config/claude/CLAUDE.md"
check "グローバルの CLAUDE.md に「作業の進め方」の節が無い" sh -c "! grep -q '^#* *作業の進め方' '$C'"
for h in 作業の哲学 Linear Karpathy Ponytail スクリーンショット; do
  check "グローバルの CLAUDE.md に「$h」の節が残る" grep -Eq "^#+ .*$h" "$C"
done
check "グローバルの CLAUDE.md: 開発の手順は superpowers の skill に従う" grep -q '開発の手順.*superpowers の skill に従う' "$C"
check "グローバルの CLAUDE.md: harness に触れるのは、やめた経緯（ARK-67）の 1 行だけ" \
  sh -c "[ \"\$(grep -c harness '$C')\" = 1 ] && grep harness '$C' | grep -q ARK-67"
check "グローバルの CLAUDE.md: issue は /issue で始める" grep -q '`/issue ARK-nn`' "$C"
check "グローバルの CLAUDE.md: /wrap-up は統合の前に作業ブランチの上で" grep -q '統合の前に、作業ブランチの上で `/wrap-up`' "$C"
check "グローバルの CLAUDE.md: 設計（spec）と計画（plan）は issue の本文に書き、docs/superpowers/ を作らない" \
  sh -c "grep -q '設計（spec）と計画（plan）' '$C' && grep -q 'docs/superpowers/.*作らない' '$C'"
check "グローバルの CLAUDE.md: 検証の行はテストを TDD に従わせる" grep -Eq '^- \*\*検証\*\*.*TDD' "$C"
check "グローバルの CLAUDE.md に規模（S/M/L）の記述が無い" sh -c "! grep -Eq '規模|M / L|S は任意|L の計画' '$C'"
check "グローバルの CLAUDE.md に SessionStart の記述が無い" sh -c "! grep -q SessionStart '$C'"

# dotfiles の文書: /harness: の skill・関門の記述が無く、superpowers の入れ方とコミット前のテストがある
for f in "$ROOT/CLAUDE.md" "$ROOT/README.md" "$ROOT/tests/acceptance.sh"; do
  n="${f#"$ROOT"/}"
  check "$n に /harness: の skill と関門の記述が無い" sh -c "! grep -Eq '/harness:|関門|harness-hook|harness@harness' '$f'"
done
check "dotfiles の CLAUDE.md が手順の担い手として superpowers を書く" grep -q '開発の手順はプラグイン superpowers' "$ROOT/CLAUDE.md"
check "dotfiles の CLAUDE.md がコミットの前に流すテストを書く" sh -c "grep -q 'コミットの前に' '$ROOT/CLAUDE.md' && grep -q 'sh tests/install.sh' '$ROOT/CLAUDE.md'"
check "README の「使わないもの」に superpowers が無い" sh -c "! sed -n '/^### 使わないもの/,/^#/p' '$ROOT/README.md' | grep -q superpowers"
check "README に superpowers の入れ方がある" grep -qF 'claude plugin install superpowers@claude-plugins-official' "$ROOT/README.md"
# README の新しい端末の手順（superpowers を install する行）の `claude plugin …` を順に（LIVE でも使う）
steps="$(grep -F '新しい端末では' "$ROOT/README.md" | grep -m1 -F 'claude plugin install superpowers@claude-plugins-official' | grep -o '`claude plugin [^`]*`' | tr -d '`')"
check "README の新しい端末の手順を読み取れた（claude plugin が 2 つ）" [ "$(printf '%s\n' "$steps" | grep -c .)" = 2 ]
add_before_install() { printf '%s\n' "$steps" | sed -n '/marketplace add anthropics\/claude-plugins-official/,$p' | grep -q 'install superpowers@claude-plugins-official'; }
check "README の新しい端末の手順で、公式の marketplace の add が superpowers の install より前にある" add_before_install

# git の共通 hooks の場所を置かない（各リポジトリの .git/hooks がそのまま効く）。この端末でも効いていない
G="$ROOT/config/git/config"
check "config/git/config に core.hooksPath が無い" sh -c "! git config -f '$G' --get core.hooksPath"
check "この端末で core.hooksPath が効いていない（$(git config --show-scope --get-all core.hooksPath 2>/dev/null | tr '\t\n' '  ')）" \
  sh -c "! git config --get-all core.hooksPath"

# LIVE: 新しいセッションの起動情報（init）のプラグインと skill。README の新しい端末の手順
if [ -n "${LIVE:-}" ]; then
  D="$(mktemp -d)"; L="$D/live.jsonl"
  (cd "$D" && claude -p '何もせず「ok」とだけ答えて。' --model haiku --permission-mode dontAsk --tools '' \
     --strict-mcp-config --no-session-persistence --output-format stream-json --verbose > "$L" 2> "$D/stderr.txt" </dev/null)
  init="$(jq -c 'select(.type == "system" and .subtype == "init")' "$L")"
  has() { printf '%s' "$init" | jq -e --arg x "$2" "$1 | index(\$x)" >/dev/null; }
  check "（LIVE）新しいセッションの起動情報を読めた" [ -n "$init" ]
  check "（LIVE）新しいセッションにプラグイン superpowers がある" has '.plugins | map(.name)' superpowers
  check "（LIVE）新しいセッションにプラグイン harness が無い" sh -c '! printf "%s" "$1" | jq -e ".plugins | map(.name) | index(\"harness\")"' _ "$init"
  for s in superpowers:brainstorming superpowers:test-driven-development issue wrap-up; do
    check "（LIVE）skill $s が見える" has '.skills' "$s"
  done
  check "（LIVE）harness: の skill が見えない" sh -c '! printf "%s" "$1" | jq -e ".skills | map(select(startswith(\"harness:\"))) | length > 0"' _ "$init"
  # README の新しい端末の手順（ARK-64 AC3）: 空の設定の置き場に settings.json の写しを置き、手順の `claude plugin …` を順に実行する
  # 比べる基準は写しを取った時点の内容（実行中に本物の settings.json が書き換わっても誤って落ちないように）
  N="$D/newterm"; mkdir -p "$N"; cp "$S" "$D/settings.before.json"; cp "$D/settings.before.json" "$N/settings.json"
  # 手順の 1 つずつを語に分けて渡す（シェルを通さない）
  ran() { printf '%s\n' "$steps" | while read -r cmd; do CLAUDE_CONFIG_DIR="$N" $cmd </dev/null >> "$N/steps.log" 2>&1 || exit 1; done; }
  check "（LIVE）新しい端末の手順のコマンドがすべて成功する" ran
  check "（LIVE）新しい端末の手順で superpowers が入る" \
    jq -e '.plugins | has("superpowers@claude-plugins-official")' "$N/plugins/installed_plugins.json"
  check "（LIVE）新しい端末の手順で settings.json は変わらない" [ "$(jq -S . "$D/settings.before.json")" = "$(jq -S . "$N/settings.json")" ]
  # 失敗したら、原因（未ログイン・プラグイン未導入など）を見られるように記録を残す
  if [ "$fail" = 0 ]; then rm -rf "$D"; else echo "（LIVE）記録を残した: $L・$D/stderr.txt・$N/steps.log"; fi
fi

[ "$fail" = 0 ] && echo "acceptance plugin-switch: ok"
[ "$fail" = 0 ]
