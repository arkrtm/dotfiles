#!/bin/sh
# Claude Code の構成の受け入れ検査: settings.json（プラグインの宣言と hook の配線）、skill（issue・wrap-up のリンク）、
# グローバル CLAUDE.md と dotfiles の文書（手順は superpowers に任せ、Linear の規則が揃っていること）、README の新しい端末の手順。
# 検証一式（sh tests/static.sh・sh tests/install.sh・DOCKER='ssh nas docker' sh tests/install-nosudo.sh）は別に実行する。
# LIVE=1 のときだけ、本物の claude -p の新しいセッションでプラグインと skill の見え方を確かめ、空の設定の置き場で README の
# 新しい端末の手順が通ることも確かめる（haiku を 1 回呼ぶ。課金あり。marketplace の取得にネットワークが要る。
# 本物の設定で claude を動かすので、tmux の中では hook がウィンドウ名と通知に副作用を出す）
#   sh tests/acceptance/claude-config.sh        失敗した項目と要約だけ
#   V=1 sh tests/acceptance/claude-config.sh    通った項目も
#   LIVE=1 sh tests/acceptance/claude-config.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
check() { d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi; }
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }

# ---- settings.json: プラグインの宣言と hook の配線（JSON の妥当性と event 名は tests/static.sh）
S="$ROOT/config/claude/settings.json"
check "settings.json の hooks に agent-status・tinymemory の配線がある" \
  sh -c "jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q agent-status && jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q tinymemory"
for p in superpowers@claude-plugins-official tinymemory@tinymemory; do
  check "enabledPlugins の $p が true" [ "$(jq -r --arg p "$p" '.enabledPlugins[$p]' "$S")" = true ]
done
check "extraKnownMarketplaces.claude-plugins-official は github の anthropics/claude-plugins-official" \
  [ "$(jq -r '.extraKnownMarketplaces["claude-plugins-official"].source | "\(.source) \(.repo)"' "$S")" = "github anthropics/claude-plugins-official" ]
check "extraKnownMarketplaces.tinymemory は github の arkrtm/tinymemory" \
  [ "$(jq -r '.extraKnownMarketplaces.tinymemory.source | "\(.source) \(.repo)"' "$S")" = "github arkrtm/tinymemory" ]

# ---- skill は issue と wrap-up だけ。install.sh の LINKS（tests/install.sh と同じ読み方）にある。グローバルの gitignore も
check "config/claude/skills は issue と wrap-up だけ" [ "$(ls "$ROOT/config/claude/skills" | tr '\n' ' ')" = "issue wrap-up " ]
links="$(sed -n '/^LINKS="/,/^"/p' "$ROOT/install.sh" | grep -vE '^(LINKS="|")$')"
check "install.sh の LINKS 表を読めた" [ -n "$links" ]
for s in issue wrap-up; do
  check "install.sh の LINKS 表に skill の $s がある" sh -c "printf '%s\n' \"\$1\" | grep -q '^config/claude/skills/$s  *\.claude/skills/$s\$'" _ "$links"
done
check "install.sh の LINKS 表にグローバルの gitignore（config/git/ignore）がある" sh -c "printf '%s\n' \"\$1\" | grep -q '^config/git/ignore  *\.config/git/ignore\$'" _ "$links"
check "config/git/ignore は .superpowers/ を除外する" grep -qx '\.superpowers/' "$ROOT/config/git/ignore"

# ---- グローバルの CLAUDE.md: 手順は superpowers、Linear の記録は /issue・/wrap-up、plan の置き場所
C="$ROOT/config/claude/CLAUDE.md"
for h in 作業の哲学 Linear Karpathy Ponytail スクリーンショット; do
  check "グローバルの CLAUDE.md に「$h」の節がある" grep -Eq "^#+ .*$h" "$C"
done
check "グローバルの CLAUDE.md: 開発の手順は superpowers の skill に従う" grep -q '開発の手順.*superpowers の skill に従う' "$C"
check "グローバルの CLAUDE.md: 経緯（harness）は書かず README に任せる" [ "$(grep -c harness "$C")" = 0 ]
check "グローバルの CLAUDE.md: issue は /issue で始める" grep -q '`/issue ARK-nn`' "$C"
check "グローバルの CLAUDE.md: /wrap-up は統合の前に作業ブランチの上で" grep -q '統合の前に、作業ブランチの上で `/wrap-up`' "$C"
check "グローバルの CLAUDE.md: plan のファイルは .superpowers/plans/ に置き、本文が正本" sh -c "grep -q '\.superpowers/plans/' '$C' && grep -q '本文が正本' '$C'"
check "グローバルの CLAUDE.md: docs/superpowers/ は作らない" grep -q 'docs/superpowers/.*作らない' "$C"
check "グローバルの CLAUDE.md: 検証の行はテストを TDD に従わせる" grep -Eq '^- \*\*検証\*\*.*TDD' "$C"
check "グローバルの CLAUDE.md: スクショの名前の時刻は保存時刻" grep -q 'HHMMSS.png`（保存時刻' "$C"

# ---- skill: wrap-up は統合の前に /clear を促さない。issue はコメントの規則を CLAUDE.md に委ねる
check "wrap-up の締めは、統合して Done にしてから /clear" grep -q 'Done にしてから `/clear`' "$ROOT/config/claude/skills/wrap-up/SKILL.md"
check "issue のコメントの節目は CLAUDE.md の Linear の節に従う（書き写さない）" grep -q 'コメントの節目は CLAUDE.md の Linear の節に従う' "$ROOT/config/claude/skills/issue/SKILL.md"

# ---- dotfiles の文書
check "dotfiles の CLAUDE.md が手順の担い手として superpowers を書く" grep -q '開発の手順はプラグイン superpowers' "$ROOT/CLAUDE.md"
check "dotfiles の CLAUDE.md がコミットの前に流すテストを書く（static・install・acceptance）" \
  sh -c "grep -q 'sh tests/static.sh' '$ROOT/CLAUDE.md' && grep -q 'sh tests/install.sh' '$ROOT/CLAUDE.md' && grep -q 'sh tests/acceptance.sh' '$ROOT/CLAUDE.md'"
check "README に superpowers の入れ方がある" grep -qF 'claude plugin install superpowers@claude-plugins-official' "$ROOT/README.md"
check "README に tests/ の説明がある" grep -q '`tests/`' "$ROOT/README.md"
# README の新しい端末の手順（superpowers を install する行）の `claude plugin …` を順に（LIVE でも使う）
steps="$(grep -F '新しい端末では' "$ROOT/README.md" | grep -m1 -F 'claude plugin install superpowers@claude-plugins-official' | grep -o '`claude plugin [^`]*`' | tr -d '`')"
check "README の新しい端末の手順を読み取れた（claude plugin が 4 つ）" [ "$(printf '%s\n' "$steps" | grep -c .)" = 4 ]
add_before_install() { printf '%s\n' "$steps" | sed -n "\|marketplace add $1|,\$p" | grep -q "install $2"; } # $1 = marketplace の repo、$2 = plugin
check "README の手順で、公式の marketplace の add が superpowers の install より前" add_before_install anthropics/claude-plugins-official superpowers@claude-plugins-official
check "README の手順で、tinymemory の marketplace の add が tinymemory の install より前" add_before_install arkrtm/tinymemory tinymemory@tinymemory

# ---- git の設定: 共通 hooks の場所は置かない（ARK-67 の結果。各リポジトリの .git/hooks がそのまま効く）
check "config/git/config に core.hooksPath が無い" sh -c "! git config -f '$ROOT/config/git/config' --get core.hooksPath"

# ---- LIVE: 新しいセッションの起動情報（init）のプラグインと skill。README の新しい端末の手順
if [ -n "${LIVE:-}" ]; then
  D="$(mktemp -d)"; L="$D/live.jsonl"; live_fail=0
  trap 'rm -rf "$D"' EXIT
  (cd "$D" && claude -p '何もせず「ok」とだけ答えて。' --model haiku --permission-mode dontAsk --tools '' \
     --strict-mcp-config --no-session-persistence --output-format stream-json --verbose > "$L" 2> "$D/stderr.txt" </dev/null)
  init="$(jq -c 'select(.type == "system" and .subtype == "init")' "$L")"
  lcheck() { d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; live_fail=1; fi; }
  has() { printf '%s' "$init" | jq -e --arg x "$2" "$1 | index(\$x)" >/dev/null; }
  lcheck "（LIVE）新しいセッションの起動情報を読めた" [ -n "$init" ]
  for p in superpowers tinymemory; do lcheck "（LIVE）新しいセッションにプラグイン $p がある" has '.plugins | map(.name)' "$p"; done
  for s in superpowers:brainstorming superpowers:test-driven-development tinymemory:remember issue wrap-up; do
    lcheck "（LIVE）skill $s が見える" has '.skills' "$s"
  done
  lcheck "（LIVE）~/.claude/settings.json はリポジトリへのリンクのまま（plugin の操作で実ファイルに置き換わっていない）" \
    [ "$(readlink "$HOME/.claude/settings.json")" = "$S" ]
  # README の新しい端末の手順（ARK-64 AC3）: 空の設定の置き場に settings.json の写しを置き、手順の `claude plugin …` を順に実行する
  # 比べる基準は写しを取った時点の内容（実行中に本物の settings.json が書き換わっても誤って落ちないように）
  N="$D/newterm"; mkdir -p "$N"; cp "$S" "$D/settings.before.json"; cp "$D/settings.before.json" "$N/settings.json"
  # 手順の 1 つずつを語に分けて渡す（シェルを通さない）
  ran() { printf '%s\n' "$steps" | while read -r cmd; do CLAUDE_CONFIG_DIR="$N" $cmd </dev/null >> "$N/steps.log" 2>&1 || exit 1; done; }
  lcheck "（LIVE）新しい端末の手順のコマンドがすべて成功する" ran
  lcheck "（LIVE）新しい端末の手順で superpowers と tinymemory が入る" \
    jq -e '.plugins | has("superpowers@claude-plugins-official") and has("tinymemory@tinymemory")' "$N/plugins/installed_plugins.json"
  lcheck "（LIVE）新しい端末の手順で settings.json は変わらない" [ "$(jq -S . "$D/settings.before.json")" = "$(jq -S . "$N/settings.json")" ]
  # LIVE が落ちたら、原因（未ログイン・プラグイン未導入など）を見られるように記録を残す
  if [ "$live_fail" != 0 ]; then trap - EXIT; echo "（LIVE）記録を残した: $L・$D/stderr.txt・$N/steps.log"; fi
fi

[ "$fail" = 0 ] && echo "acceptance claude-config: ok"
[ "$fail" = 0 ]
