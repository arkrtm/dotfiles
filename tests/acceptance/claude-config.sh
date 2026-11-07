#!/bin/sh
# Claude Code の構成の受け入れ検査: settings.json（プラグインの宣言と hook の配線）、skill（issue・wrap-up のリンク）、
# config/claude/README.md の新しい端末の手順。指示や文書の文そのものは見ない（振る舞いの検査が別にある）。
# 検証一式（sh tests/static.sh・sh tests/install.sh・sh tests/install-nosudo.sh）は別に実行する。
# LIVE=1 のときだけ、本物の claude -p の新しいセッションでプラグインと skill の見え方を確かめ、空の設定の置き場で config/claude/README.md の
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
# ---- permissions・statusLine。integrate setup の上書きと設定の直接の編集を禁止
for r in 'Bash(tinymemory:*)' 'Bash(git diff:*)' 'Bash(codex-review:*)'; do
  check "permissions.allow に $r" jq -e --arg r "$r" '.permissions.allow | index($r)' "$S"
done
for r in 'Bash(git push --force:*)' 'Bash(git push -f:*)' 'Bash(git push --force-with-lease:*)' 'Read(./.env)' 'Read(./.env.*)' 'Read(~/.ssh/**)' 'Read(~/.codex/auth.json)' \
  'Bash(git push:*)' 'Bash(gh pr merge:*)' 'Bash(integrate --human-approved:*)' 'Bash(integrate setup --force:*)' 'Edit(~/.config/integrate/**)'; do
  check "permissions.deny に $r" jq -e --arg r "$r" '.permissions.deny | index($r)' "$S"
done
# 既定のモデルは Opus 5.5 high（Opus 5.5 では最上位の effortLevel は無視されるので modelSettings に書く）
check "settings.json の model が opus[1m]（claude plugin が書き換える形。Opus 5.5 では opus と同じ）" [ "$(jq -r '.model' "$S")" = 'opus[1m]' ]
check "settings.json の modelSettings の claude-opus-5-5 の effortLevel が high" [ "$(jq -r '.modelSettings["claude-opus-5-5"].effortLevel' "$S")" = high ]
check "statusLine は ~/.claude/statusline.sh" [ "$(jq -r '.statusLine | "\(.type) \(.command)"' "$S")" = 'command $HOME/.claude/statusline.sh' ]
# check・fmt のフック（scripts/check・scripts/fmt の決まり）と bare の pre-receive はやめた
check "Stop のフックは agent-status だけ（check.sh が無い）" [ "$(jq -r '.hooks.Stop[].hooks[].command' "$S")" = '$HOME/.local/bin/agent-status done' ]
check "settings.json のフックに check.sh・fmt.sh が無い" sh -c "! jq -r '.hooks[][].hooks[].command' '$S' | grep -qE 'check\.sh|fmt\.sh'"
# integrate setup の無いリポジトリでは会話の始まりに案内し、編集を止める
check "SessionStart に integrate-hook session-start" sh -c "jq -r '.hooks.SessionStart[].hooks[].command' '$S' | grep -qx '\$HOME/.local/bin/integrate-hook session-start'"
check "PreToolUse の Edit|Write|NotebookEdit に integrate-hook pre-edit" \
  [ "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|NotebookEdit") | .hooks[].command' "$S")" = '$HOME/.local/bin/integrate-hook pre-edit' ]
check "config/claude/hooks・pre-receive とその検査が無い" \
  sh -c "[ ! -e '$ROOT/config/claude/hooks' ] && [ ! -e '$ROOT/config/git/hooks/pre-receive' ] && [ ! -e '$ROOT/tests/acceptance/pre-receive.sh' ]"

# ---- herdr 連携: モバイルは remote-control を常に、文脈の合図、サブエージェントの pane、clear の後の印と片づけ
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

# ---- pi はやめた: config/pi が無く、pi 向けの記述も無い（パターンの [ ] は、この行自身に当たらないため）
check "config/pi が無い" [ ! -e "$ROOT/config/pi" ]
git -C "$ROOT" grep -q -I -E '\b[P]i\b|\.p[i]/|bigpower[s]|/skil[l]:|pi-tinymemor[y]|yamlfi[x]|ask_user_questio[n]'; rc=$? # 1 = 一致なし、0 = 記述がある、ほかは実行の失敗
check "pi 向けの記述が無い（git grep が一致なしの 1 を返す。rc=$rc）" [ "$rc" = 1 ]

# ---- config/claude/README.md の新しい端末の手順（LIVE が実行する）
# config/claude/README.md の新しい端末の手順（superpowers を install する行）の `claude plugin …` を順に（LIVE でも使う）
steps="$(grep -F '新しい端末では' "$ROOT/config/claude/README.md" | grep -m1 -F 'claude plugin install superpowers@claude-plugins-official' | grep -o '`claude plugin [^`]*`' | tr -d '`')"
check "config/claude/README.md の新しい端末の手順を読み取れた（claude plugin が 6 つ）" [ "$(printf '%s\n' "$steps" | grep -c .)" = 6 ]
add_before_install() { printf '%s\n' "$steps" | sed -n "\|marketplace add $1|,\$p" | grep -q "install $2"; } # $1 = marketplace の repo、$2 = plugin
check "config/claude/README.md の手順で、公式の marketplace の add が superpowers の install より前" add_before_install anthropics/claude-plugins-official superpowers@claude-plugins-official
check "config/claude/README.md の手順で、tinymemory の marketplace の add が tinymemory の install より前" add_before_install arkrtm/tinymemory tinymemory@tinymemory
check "config/claude/README.md の手順で、ponytail の marketplace の add が ponytail の install より前" add_before_install DietrichGebert/ponytail ponytail@ponytail

# ---- git の設定: 共通 hooks の場所は置かない（各リポジトリの .git/hooks がそのまま効く）
check "config/git/config に core.hooksPath が無い" sh -c "! git config -f '$ROOT/config/git/config' --get core.hooksPath"

# ---- LIVE: 新しいセッションの起動情報（init）のプラグインと skill。config/claude/README.md の新しい端末の手順
if [ -n "${LIVE:-}" ]; then
  D=""; trap 'trap "" HUP INT TERM; rm -rf ${D:+"$D"}' EXIT
  trap 'exit 1' HUP INT TERM
  D="$(trap '' HUP INT TERM; mktemp -d)"; L="$D/live.jsonl"; live_fail=0
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
  # リンクの先は元のチェックアウト（worktree list の最初）。元のチェックアウトから流せば $S と同じ
  M="$(git -C "$ROOT" worktree list --porcelain | sed -n '1s/^worktree //p')"
  lcheck "（LIVE）~/.claude/settings.json はリポジトリへのリンクのまま（plugin の操作で実ファイルに置き換わっていない）" \
    [ "$(readlink "$HOME/.claude/settings.json")" = "$M/config/claude/settings.json" ]
  # config/claude/README.md の新しい端末の手順: 空の設定の置き場に settings.json の写しを置き、手順の `claude plugin …` を順に実行する
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
