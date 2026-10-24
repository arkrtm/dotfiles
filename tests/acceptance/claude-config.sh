#!/bin/sh
# Claude Code の構成の受け入れ検査: settings.json（プラグインの宣言と hook の配線）、skill（issue・wrap-up のリンク）、
# グローバル指示（config/agents/AGENTS.md。CC・Codex 共通）と dotfiles の文書（手順は superpowers に任せ、Linear の規則が揃っていること）、README の新しい端末の手順。
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
for p in superpowers@claude-plugins-official tinymemory@tinymemory ponytail@ponytail; do
  check "enabledPlugins の $p が true" [ "$(jq -r --arg p "$p" '.enabledPlugins[$p]' "$S")" = true ]
done
check "extraKnownMarketplaces.claude-plugins-official は github の anthropics/claude-plugins-official" \
  [ "$(jq -r '.extraKnownMarketplaces["claude-plugins-official"].source | "\(.source) \(.repo)"' "$S")" = "github anthropics/claude-plugins-official" ]
check "extraKnownMarketplaces.tinymemory は github の arkrtm/tinymemory" \
  [ "$(jq -r '.extraKnownMarketplaces.tinymemory.source | "\(.source) \(.repo)"' "$S")" = "github arkrtm/tinymemory" ]
check "extraKnownMarketplaces.ponytail は github の DietrichGebert/ponytail" \
  [ "$(jq -r '.extraKnownMarketplaces.ponytail.source | "\(.source) \(.repo)"' "$S")" = "github DietrichGebert/ponytail" ]
# ---- permissions・statusLine（ARK-86）。integrate setup の上書きと設定の直接の編集を禁止（ARK-98）
for r in 'Bash(tinymemory:*)' 'Bash(git diff:*)' 'Bash(codex-review:*)'; do
  check "permissions.allow に $r" jq -e --arg r "$r" '.permissions.allow | index($r)' "$S"
done
for r in 'Bash(git push --force:*)' 'Bash(git push -f:*)' 'Bash(git push --force-with-lease:*)' 'Read(./.env)' 'Read(./.env.*)' 'Read(~/.ssh/**)' 'Read(~/.codex/auth.json)' \
  'Bash(git push:*)' 'Bash(gh pr merge:*)' 'Bash(integrate --human-approved:*)' 'Bash(integrate setup --force:*)' 'Edit(~/.config/integrate/**)'; do
  check "permissions.deny に $r" jq -e --arg r "$r" '.permissions.deny | index($r)' "$S"
done
# 既定のモデルは Opus 5.5 high（ARK-101。Opus 5.5 では最上位の effortLevel は無視されるので modelSettings に書く）
check "settings.json の model が opus" [ "$(jq -r '.model' "$S")" = opus ]
check "settings.json の modelSettings の claude-opus-5-5 の effortLevel が high" [ "$(jq -r '.modelSettings["claude-opus-5-5"].effortLevel' "$S")" = high ]
check "statusLine は ~/.claude/statusline.sh" [ "$(jq -r '.statusLine | "\(.type) \(.command)"' "$S")" = 'command $HOME/.claude/statusline.sh' ]
# check・fmt のフック（scripts/check・scripts/fmt の決まり）と bare の pre-receive はやめた（ARK-98）
check "Stop のフックは agent-status だけ（check.sh が無い）" [ "$(jq -r '.hooks.Stop[].hooks[].command' "$S")" = '$HOME/.local/bin/agent-status done' ]
check "settings.json のフックに check.sh・fmt.sh が無い" sh -c "! jq -r '.hooks[][].hooks[].command' '$S' | grep -qE 'check\.sh|fmt\.sh'"
# integrate setup の無いリポジトリでは会話の始まりに案内し、編集を止める（ARK-99）
check "SessionStart に integrate-hook session-start" sh -c "jq -r '.hooks.SessionStart[].hooks[].command' '$S' | grep -qx '\$HOME/.local/bin/integrate-hook session-start'"
check "PreToolUse の Edit|Write|NotebookEdit に integrate-hook pre-edit" \
  [ "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|NotebookEdit") | .hooks[].command' "$S")" = '$HOME/.local/bin/integrate-hook pre-edit' ]
check "config/claude/hooks・pre-receive とその検査が無い" \
  sh -c "[ ! -e '$ROOT/config/claude/hooks' ] && [ ! -e '$ROOT/config/git/hooks/pre-receive' ] && [ ! -e '$ROOT/tests/acceptance/pre-receive.sh' ]"

# ---- herdr 連携（ARK-90）: モバイルは remote-control を常に、文脈の合図、サブエージェントの pane、clear の後の印と片づけ
hk() { jq -r --arg e "$1" '.hooks[$e][]? | .hooks[].command' "$S"; }
check "remoteControlAtStartup が true" [ "$(jq -r '.remoteControlAtStartup' "$S")" = true ]
check "PostToolUse（全ツール）に context-nudge" [ "$(jq -r '.hooks.PostToolUse[] | select(.matcher == null) | .hooks[].command' "$S" | grep -c '^\$HOME/.local/bin/context-nudge$')" = 1 ]
check "SubagentStart に agent-pane start" sh -c "printf '%s\n' \"\$1\" | grep -qx '\$HOME/.local/bin/agent-pane start'" _ "$(hk SubagentStart)"
check "SubagentStop に agent-pane stop" sh -c "printf '%s\n' \"\$1\" | grep -qx '\$HOME/.local/bin/agent-pane stop'" _ "$(hk SubagentStop)"
check "SessionStart（startup・resume・clear・fork）に handoff --session-start（compact は同じセッションなので含めない）" \
  sh -c "jq -r '.hooks.SessionStart[] | select(.matcher == \"startup|resume|clear|fork\") | .hooks[].command' '$S' | grep -qx '\$HOME/.local/bin/handoff --session-start'"
check "SessionStart（clear）に agent-pane cleanup" [ "$(jq -r '.hooks.SessionStart[] | select(.matcher == "clear") | .hooks[].command' "$S")" = '$HOME/.local/bin/agent-pane cleanup' ]
check "SessionEnd に agent-pane cleanup" sh -c "printf '%s\n' \"\$1\" | grep -qx '\$HOME/.local/bin/agent-pane cleanup'" _ "$(hk SessionEnd)"

# ---- skill は issue・wrap-up・handoff。install.sh の LINKS（tests/install.sh と同じ読み方）にある。グローバルの gitignore も
check "config/agents/skills は handoff・issue・wrap-up だけ" [ "$(ls "$ROOT/config/agents/skills" | tr '\n' ' ')" = "handoff issue wrap-up " ]
links="$(sed -n '/^LINKS="/,/^"/p' "$ROOT/install.sh" | grep -vE '^(LINKS="|")$')"
check "install.sh の LINKS 表を読めた" [ -n "$links" ]
for s in issue wrap-up; do
  for d in .claude/skills .agents/skills; do
    check "install.sh の LINKS 表に skill の $s（$d）がある" sh -c "printf '%s\n' \"\$1\" | grep -q '^config/agents/skills/$s  *$d/$s\$'" _ "$links"
  done
done
# handoff は Claude Code の skill（herdr と Claude Code の clear に依る）なので ~/.claude/skills だけ
check "install.sh の LINKS 表に skill の handoff（.claude/skills）があり、.agents/skills には無い" \
  sh -c "printf '%s\n' \"\$1\" | grep -q '^config/agents/skills/handoff  *.claude/skills/handoff\$' && ! printf '%s\n' \"\$1\" | grep -qF ' .agents/skills/handoff'" _ "$links"
for d in .claude/CLAUDE.md .codex/AGENTS.md; do
  check "install.sh の LINKS 表にグローバル指示（$d）がある" sh -c "printf '%s\n' \"\$1\" | grep -q '^config/agents/AGENTS.md  *$d\$'" _ "$links"
done
check "install.sh の LINKS 表にグローバルの gitignore（config/git/ignore）がある" sh -c "printf '%s\n' \"\$1\" | grep -q '^config/git/ignore  *\.config/git/ignore\$'" _ "$links"
check "config/git/ignore は .superpowers/ を除外する" grep -qx '\.superpowers/' "$ROOT/config/git/ignore"

# ---- pi はやめた（ARK-94）: config/pi が無く、pi 向けの記述も無い（パターンの [ ] は、この行自身に当たらないため）
check "config/pi が無い" [ ! -e "$ROOT/config/pi" ]
git -C "$ROOT" grep -q -I -E '\b[P]i\b|\.p[i]/|bigpower[s]|/skil[l]:|pi-tinymemor[y]|yamlfi[x]|ask_user_questio[n]'; rc=$? # 1 = 一致なし、0 = 記述がある、ほかは実行の失敗
check "pi 向けの記述が無い（AC1 の git grep が一致なしの 1 を返す。rc=$rc）" [ "$rc" = 1 ]

# ---- グローバルの CLAUDE.md: 手順は superpowers、Linear の記録は /issue・/wrap-up、plan の置き場所
C="$ROOT/config/agents/AGENTS.md"
for h in 作業の哲学 規約 Linear スクリーンショット; do
  check "グローバルの CLAUDE.md に「$h」の節がある" grep -Eq "^#+ .*$h" "$C"
done
# Karpathy と Ponytail は全文を取り込まず要約にする（ponytail はプラグインが毎ターン入れる。ARK-86）
for h in 'Karpathy guidelines' 'Ponytail, lazy senior dev mode'; do
  check "グローバルの CLAUDE.md に「$h」の全文が無い" sh -c "! grep -q '$h' '$C'"
done
# レビューは Codex（ARK-87）: 計画は codex-review plan、最終は codex-review branch を VERDICT: PASS まで、2 往復で通らなければ notify
for w in 'codex-review plan' 'codex-review branch' 'VERDICT: PASS' '2 往復' 'notify'; do
  check "グローバルの CLAUDE.md の「レビュー」に「$w」" sh -c "sed -n '/^## レビュー/,/^## /p' '$C' | grep -qF '$w'"
done
# フェーズごとのモデル（ARK-101）: 各役の Agent ツールの model・effort
for w in '| 設計・計画 | サブエージェント | `opus`・`xhigh` |' '| 実装（plan のタスクごと） | サブエージェント | `sonnet`・`high` |' \
  '| 検証（受け入れ条件を実際に動かす） | 実装と別のサブエージェント | `opus`・`high` |' '`model: haiku`'; do
  check "グローバルの CLAUDE.md の「モデルの割り当て」に「$w」" sh -c "sed -n '/^## モデルの割り当て/,/^## /p' '$C' | grep -qF -- '$w'"
done
check "グローバルの CLAUDE.md: 作業の哲学に優先順位がある" grep -q '正しさと堅牢さ > 読みやすさ > コードの少なさ > 速さ' "$C"
check "グローバルの CLAUDE.md: 開発の手順は superpowers の skill に従う" grep -q '開発の手順.*superpowers の skill に従う' "$C"
check "グローバルの CLAUDE.md: 経緯（harness）は書かず README に任せる" [ "$(grep -c harness "$C")" = 0 ]
check "グローバルの CLAUDE.md: issue は /issue で始める" grep -q '`/issue ARK-nn`' "$C"
check "グローバルの CLAUDE.md: /wrap-up は統合の前に作業ブランチの上で" grep -q '統合の前に、作業ブランチの上で `/wrap-up`' "$C"
check "グローバルの CLAUDE.md: plan のファイルは .superpowers/plans/ に置き、本文が正本" sh -c "grep -q '\.superpowers/plans/' '$C' && grep -q '本文が正本' '$C'"
check "グローバルの CLAUDE.md: docs/superpowers/ は作らない" grep -q 'docs/superpowers/.*作らない' "$C"
check "グローバルの CLAUDE.md: 検証の行はテストを TDD に従わせる" grep -Eq '^- \*\*検証\*\*.*TDD' "$C"
# スクショは WSL で Windows のピクチャの Screenshots の最新を見る（ARK-73。転送はやめた）。ユーザー名は glob で書き、固定しない
ss="$(sed -n '/^## スクリーンショット/,/^## /p' "$C")"
for w in 'ls -t /mnt/c/Users/*/Pictures/Screenshots/*.png | head' 'WSL 以外'; do
  check "グローバルの CLAUDE.md の「スクリーンショット」に「$w」" sh -c 'printf "%s\n" "$1" | grep -qF -- "$2"' _ "$ss" "$w"
done
check "グローバルの CLAUDE.md の「スクリーンショット」に転送の記述（~/screenshots・ss-YYYYmmdd）と固定のユーザー名（/mnt/c/Users/<名前>）が無い" \
  sh -c '! printf "%s\n" "$1" | grep -qE "~/screenshots|ss-YYYYmmdd|/mnt/c/Users/[^*]"' _ "$ss"
check "グローバルの CLAUDE.md: 会話の区切りは CC は /clear（herdr の中では handoff skill）、Codex は /new" \
  grep -qxF -- '- 会話の区切り: CC は `/clear`（herdr の中では handoff skill で自分で clear して続ける）、Codex は `/new`' "$C"
for w in 'この指示は Claude Code と Codex の共通' 'Codex での読み替え:' '- skill の呼び出し: CC は `/issue`、Codex は `$issue`' \
  '- 選択肢での質問: CC は AskUserQuestion、Codex は選択肢に番号を付けて尋ねる'; do
  check "グローバルの CLAUDE.md: 読み替えは Codex だけ（$w）" grep -qF -- "$w" "$C"
done

# ---- skill: issue はコメントの規則をグローバル指示に委ねる
check "issue のコメントの節目はグローバル指示の Linear の節に従う（書き写さない）" grep -q 'コメントの節目はグローバル指示の Linear の節に従う' "$ROOT/config/agents/skills/issue/SKILL.md"

# ---- Git の運用（ARK-88）: 1 issue = 1 ブランチ = 1 worktree、統合は origin で決める、relay は統合の後に片づける。
#      統合は integrate だけ（ARK-89）。テストを弱めるときは人が --human-approved。
#      最上位のブランチ・種類・テストはリポジトリごとの integrate setup（ARK-98）
for w in 'feature/' '.worktrees/' '--no-track' 'origin/<最上位>' 'refactor:' 'issue 番号' 'PR を出す前だけ' \
  'integrate setup' 'git rebase origin/<最上位>' '強制 push' 'codex-review branch origin/<最上位>' '`integrate`' 'integrate --human-approved'; do
  check "グローバルの CLAUDE.md の「Git」に「$w」" sh -c "sed -n '/^## Git/,/^## /p' '$C' | grep -qF -- '$w'"
done
check "グローバルの CLAUDE.md: 作業中の保存は relay のタグ" grep -qF -- '--tags relay' "$C"
I="$ROOT/config/agents/skills/issue/SKILL.md"
for w in '.worktrees/' 'git worktree list' 'ブランチ: feature/' 'origin/<最上位>'; do
  check "issue の SKILL.md に「$w」" grep -qF -- "$w" "$I"
done
W="$ROOT/config/agents/skills/wrap-up/SKILL.md"
check "wrap-up の SKILL.md に「## 5. 統合の後」の節がある" grep -qx '## 5. 統合の後' "$W"
check "wrap-up は git branch -d を使わない（base と元のブランチが違うと拒むため）" sh -c "! grep -qF 'git branch -d' '$W'"
for w in 'origin/<base>' 'baseRefName' 'integrate setup --show' 'ブランチが `<base>` なら' 'git branch -D feature/<作業内容>'; do
  check "wrap-up の SKILL.md に「$w」" grep -qF -- "$w" "$W"
done
for w in Done relay 'tinymemory archive' 'git worktree remove' headRefOid '--ff-only'; do
  check "wrap-up の「統合の後」に「$w」" sh -c "sed -n '/^## 5. 統合の後/,\$p' '$W' | grep -qF -- '$w'"
done

# ---- 統合の後に次の issue を始める（ARK-106）: wrap-up の 5 の最後と handoff skill の使い方
W5="$(sed -n '/^## 5. 統合の後/,$p' "$W" | sed -n '/^5\. /,$p')" # 5 の最後の項目（5.）とその下の行
check "wrap-up の 5 の最後の項目（5.）を読めた" [ -n "$W5" ]
for w in 'ユーザーが示した作業' '続きの指示に書かれたもの' 'そのリポジトリで新しいセッションを開いて続きの指示の文' '同じリポジトリ' '優先度の高い順' '番号の小さい順' 'Todo・Backlog' 'ほかのリポジトリの Todo' '新しいセッション' '選択肢' '答えを待つ' 'handoff skill' 'herdr の中なら' '`/clear`' '`/new`' '続きの指示' '`/issue ARK-nn`'; do
  check "wrap-up の 5 の最後の項目に「$w」" sh -c 'printf "%s\n" "$1" | grep -qF -- "$2"' _ "$W5" "$w"
done
check "wrap-up の 5 の最後: 次の作業は 示された作業 → 同じリポジトリの Todo → 尋ねて待つ の順（1 行）" \
  sh -c 'printf "%s\n" "$1" | grep -q "ユーザーが示した作業.*同じリポジトリ.*Todo.*答えを待つ"' _ "$W5"
H="$ROOT/config/agents/skills/handoff/SKILL.md"
check "handoff の description に「統合の後に次の issue を始める」" \
  sh -c "sed -n '2,/^---\$/p' '$H' | grep '^description:' | grep -qF '統合の後に次の issue を始める'"
for w in '統合の後に次の issue を始める' 'relay の記憶のタイトルと Linear のコメントを次の issue の番号で書き' '`/issue ARK-nn` から始める'; do
  check "handoff の「使う条件」に「$w」" sh -c "sed -n '/^## 使う条件/,/^## /p' '$H' | grep -qF -- '$w'"
done

# ---- dotfiles の文書
check "dotfiles の CLAUDE.md が手順の担い手として superpowers を書く" grep -q '開発の手順はプラグイン superpowers' "$ROOT/CLAUDE.md"
check "dotfiles の CLAUDE.md がコミットの前に流すテストを書く（static・install・acceptance）" \
  sh -c "grep -q 'sh tests/static.sh' '$ROOT/CLAUDE.md' && grep -q 'sh tests/install.sh' '$ROOT/CLAUDE.md' && grep -q 'sh tests/acceptance.sh' '$ROOT/CLAUDE.md'"
check "README に superpowers の入れ方がある" grep -qF 'claude plugin install superpowers@claude-plugins-official' "$ROOT/README.md"
check "README に tests/ の説明がある" grep -q '`tests/`' "$ROOT/README.md"
# README の新しい端末の手順（superpowers を install する行）の `claude plugin …` を順に（LIVE でも使う）
steps="$(grep -F '新しい端末では' "$ROOT/README.md" | grep -m1 -F 'claude plugin install superpowers@claude-plugins-official' | grep -o '`claude plugin [^`]*`' | tr -d '`')"
check "README の新しい端末の手順を読み取れた（claude plugin が 6 つ）" [ "$(printf '%s\n' "$steps" | grep -c .)" = 6 ]
add_before_install() { printf '%s\n' "$steps" | sed -n "\|marketplace add $1|,\$p" | grep -q "install $2"; } # $1 = marketplace の repo、$2 = plugin
check "README の手順で、公式の marketplace の add が superpowers の install より前" add_before_install anthropics/claude-plugins-official superpowers@claude-plugins-official
check "README の手順で、tinymemory の marketplace の add が tinymemory の install より前" add_before_install arkrtm/tinymemory tinymemory@tinymemory
check "README の手順で、ponytail の marketplace の add が ponytail の install より前" add_before_install DietrichGebert/ponytail ponytail@ponytail

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
  for p in superpowers tinymemory ponytail; do lcheck "（LIVE）新しいセッションにプラグイン $p がある" has '.plugins | map(.name)' "$p"; done
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
  lcheck "（LIVE）新しい端末の手順で superpowers・tinymemory・ponytail が入る" \
    jq -e '.plugins | has("superpowers@claude-plugins-official") and has("tinymemory@tinymemory") and has("ponytail@ponytail")' "$N/plugins/installed_plugins.json"
  lcheck "（LIVE）新しい端末の手順で settings.json は変わらない" [ "$(jq -S . "$D/settings.before.json")" = "$(jq -S . "$N/settings.json")" ]
  # LIVE が落ちたら、原因（未ログイン・プラグイン未導入など）を見られるように記録を残す
  if [ "$live_fail" != 0 ]; then trap - EXIT; echo "（LIVE）記録を残した: $L・$D/stderr.txt・$N/steps.log"; fi
fi

[ "$fail" = 0 ] && echo "acceptance claude-config: ok"
[ "$fail" = 0 ]
