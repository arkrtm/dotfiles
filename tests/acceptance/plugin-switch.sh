#!/bin/sh
# dotfiles をプラグインに切り替えた後の状態の受け入れ検査: ARK-52 D（ハーネスをプラグイン harness に）と
# ARK-63 AC8（開発の手順は superpowers、harness は関門と記録の skill だけ）と ARK-64（公式の marketplace の宣言と入れ方）。
# 検証一式（sh tests/install.sh・DOCKER='ssh nas docker' sh tests/install-nosudo.sh）は別に実行する。
# LIVE=1 のときだけ、本物の claude -p の新しいセッションで、プラグインと skill の見え方とコミットの関門（AC8-5）も、
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

# settings.json: ハーネスの hooks が無く、superpowers・harness・tinymemory が有効で、harness の marketplace は github の arkrtm/harness（AC8-3）
S="$ROOT/config/claude/settings.json"
check "settings.json の hooks にハーネスの command が無い" \
  sh -c "! jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -qi harness"
check "settings.json の hooks に agent-status・tinymemory の配線は残る" \
  sh -c "jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q agent-status && jq -r '[.hooks[][].hooks[].command] | .[]' '$S' | grep -q tinymemory"
for p in superpowers@claude-plugins-official harness@harness tinymemory@tinymemory; do
  check "enabledPlugins の $p が true" [ "$(jq -r --arg p "$p" '.enabledPlugins[$p]' "$S")" = true ]
done
check "extraKnownMarketplaces.harness は github の arkrtm/harness" \
  [ "$(jq -r '.extraKnownMarketplaces.harness.source | "\(.source) \(.repo)"' "$S")" = "github arkrtm/harness" ]
check "extraKnownMarketplaces.claude-plugins-official は github の anthropics/claude-plugins-official" \
  [ "$(jq -r '.extraKnownMarketplaces["claude-plugins-official"].source | "\(.source) \(.repo)"' "$S")" = "github anthropics/claude-plugins-official" ]

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

# グローバルの CLAUDE.md（AC8-1）: 手順は superpowers の skill、harness は関門と記録の skill だけ。規模（S/M/L）と手順の注入の記述が無い
C="$ROOT/config/claude/CLAUDE.md"
check "グローバルの CLAUDE.md に「作業の進め方」の節が無い" sh -c "! grep -q '^#* *作業の進め方' '$C'"
for h in 作業の哲学 Linear Karpathy Ponytail スクリーンショット; do
  check "グローバルの CLAUDE.md に「$h」の節が残る" grep -Eq "^#+ .*$h" "$C"
done
check "グローバルの CLAUDE.md: 開発の手順は superpowers の skill に従う" grep -q '開発の手順.*superpowers の skill に従う' "$C"
check "グローバルの CLAUDE.md: harness は関門と記録の skill だけ" grep -q 'harness.*関門.*記録の skill.*だけ' "$C"
check "グローバルの CLAUDE.md: 設計（spec）と計画（plan）は issue の本文に書き、docs/superpowers/ を作らない" \
  sh -c "grep -q '設計（spec）と計画（plan）' '$C' && grep -q 'docs/superpowers/.*作らない' '$C'"
check "グローバルの CLAUDE.md: 検証の行はテストを TDD に従わせる" grep -Eq '^- \*\*検証\*\*.*TDD' "$C"
check "グローバルの CLAUDE.md: /harness:wrap-up は統合の前に作業ブランチの上で" grep -q '統合の前に、作業ブランチの上で `/harness:wrap-up`' "$C"
check "グローバルの CLAUDE.md に規模（S/M/L）の記述が無い" sh -c "! grep -Eq '規模|M / L|S は任意|L の計画' '$C'"
check "グローバルの CLAUDE.md に SessionStart（harness が手順を入れる）の記述が無い" sh -c "! grep -q SessionStart '$C'"

# dotfiles の文書（AC8-2）: 消えた skill・acceptor・手順の注入・「superpowers は使わない」の記述が無く、superpowers の入れ方がある
for f in "$C" "$ROOT/CLAUDE.md" "$ROOT/README.md" "$ROOT/tests/acceptance.sh"; do
  n="${f#"$ROOT"/}"
  check "$n に消えた skill（/harness:accept など）と acceptor が無い" \
    sh -c "! grep -Eq '/harness:(accept|verify|review|tdd|design|diagnose|implement)|\`/(accept|verify|review|tdd|design|diagnose|implement)\b|acceptor' '$f'"
  check "$n に「harness が SessionStart で手順を入れる」の記述が無い" \
    sh -c "! grep -Eq 'SessionStart で(入れる|コンテキストに入れる|読み込む)' '$f'"
done
check "dotfiles の CLAUDE.md が手順の担い手として superpowers を書く" grep -q '開発の手順はプラグイン superpowers' "$ROOT/CLAUDE.md"
check "README の「使わないもの」に superpowers が無い" sh -c "! sed -n '/^### 使わないもの/,/^#/p' '$ROOT/README.md' | grep -q superpowers"
check "README に superpowers の入れ方がある" grep -qF 'claude plugin install superpowers@claude-plugins-official' "$ROOT/README.md"
# README の新しい端末の手順（superpowers を install する行）の `claude plugin …` を順に（LIVE でも使う）
steps="$(grep -m1 -F 'claude plugin install superpowers@claude-plugins-official' "$ROOT/README.md" | grep -o '`claude plugin [^`]*`' | tr -d '`')"
add_before_install() { printf '%s\n' "$steps" | sed -n '/marketplace add anthropics\/claude-plugins-official/,$p' | grep -q 'install superpowers@claude-plugins-official'; }
check "README の新しい端末の手順で、公式の marketplace の add が superpowers の install より前にある" add_before_install

# git の共通 hooks の場所: dotfiles の設定がプラグインの data の git-hooks を指し、この端末で効いていて、run-hook がある
G="$ROOT/config/git/config"
hp="$(git config -f "$G" --get core.hooksPath)"
check "config/git/config の core.hooksPath はプラグインの data の git-hooks（$hp）" [ "$hp" = "~/.claude/plugins/data/harness-harness/git-hooks" ]
eff="$(git config --show-scope --get-all core.hooksPath | sed -n 's/^global\t//p' | tail -1)"
check "この端末で効いている global の core.hooksPath も同じ（$eff）" [ "$eff" = "$hp" ]
check "その場所に run-hook と pre-commit がある" \
  sh -c "[ -x \"\$HOME/.claude/plugins/data/harness-harness/git-hooks/run-hook\" ] && [ -e \"\$HOME/.claude/plugins/data/harness-harness/git-hooks/pre-commit\" ]"

# LIVE（AC8-5）: 新しいセッションの起動情報（init）のプラグインと skill、作業ブランチでの検証なしのコードのコミットが止まること
if [ -n "${LIVE:-}" ]; then
  D="$(mktemp -d)"; L="$D/live.jsonl"
  # 前提の init コミットは人の手動のコミットとして作る（Claude Code の中で実行されても関門の対象にしない）
  ( unset CLAUDECODE; g="git -C $D -c user.name=t -c user.email=t@t"
    $g init -q -b main && $g commit -q --allow-empty -m init && $g switch -q -c feat/live &&
    echo 'print(1)' > "$D/app.py" && $g add app.py )
  (cd "$D" && claude -p 'このリポジトリで `git commit -m live` を 1 回だけ実行し、その出力をそのまま答えて。ほかのコマンドは実行しない。' \
     --model haiku --permission-mode dontAsk --allowedTools 'Bash(git commit:*)' \
     --strict-mcp-config --no-session-persistence --output-format stream-json --verbose > "$L" 2> "$D/stderr.txt" </dev/null)
  init="$(jq -c 'select(.type == "system" and .subtype == "init")' "$L")"
  has() { printf '%s' "$init" | jq -e --arg x "$2" "$1 | index(\$x)" >/dev/null; }
  for p in superpowers harness; do check "（LIVE）新しいセッションにプラグイン $p がある" has '.plugins | map(.name)' "$p"; done
  for s in superpowers:brainstorming superpowers:test-driven-development harness:issue harness:wrap-up; do
    check "（LIVE）skill $s が見える" has '.skills' "$s"
  done
  for s in harness:accept harness:verify harness:review; do
    check "（LIVE）消えた skill $s が見えない" sh -c '! printf "%s" "$1" | jq -e --arg x "$2" ".skills | index(\$x)"' _ "$init" "$s"
  done
  check "（LIVE）Claude の git commit を harness の関門が止めた（「harness: コミットできない」）" grep -q 'harness: コミットできない' "$L"
  check "（LIVE）作業ブランチのコミットは増えていない" [ "$(git -C "$D" rev-list --count HEAD)" = 1 ]
  # README の新しい端末の手順（ARK-64 AC3）: 空の設定の置き場に settings.json の写しを置き、手順の `claude plugin …` を順に実行する
  N="$D/newterm"; mkdir -p "$N"; cp "$S" "$N/settings.json"
  check "（LIVE）README の新しい端末の手順を読み取れた（4 つ）" [ "$(printf '%s\n' "$steps" | grep -c .)" = 4 ]
  # 手順の 1 つずつを語に分けて渡す（シェルを通さない）
  ran() { printf '%s\n' "$steps" | while read -r cmd; do CLAUDE_CONFIG_DIR="$N" $cmd </dev/null >> "$N/steps.log" 2>&1 || exit 1; done; }
  check "（LIVE）新しい端末の手順のコマンドがすべて成功する" ran
  check "（LIVE）新しい端末の手順で harness と superpowers が入る" \
    jq -e '.plugins | has("harness@harness") and has("superpowers@claude-plugins-official")' "$N/plugins/installed_plugins.json"
  check "（LIVE）新しい端末の手順で settings.json は変わらない" [ "$(jq -S . "$S")" = "$(jq -S . "$N/settings.json")" ]
  # 失敗したら、原因（未ログイン・プラグイン未導入・関門の不発など）を見られるように記録を残す
  if [ "$fail" = 0 ]; then rm -rf "$D"; else echo "（LIVE）記録を残した: $L・$D/stderr.txt・$N/steps.log"; fi
fi

[ "$fail" = 0 ] && echo "acceptance plugin-switch: ok"
[ "$fail" = 0 ]
