#!/bin/sh
# Claude Code の構成の受け入れ検査: settings.json（プラグインの宣言と hook の配線）、skill（issue・wrap-up のリンク）、
# config/claude/README.md の新しい端末の手順、指示と skill に残る安全な手順の要（コマンド・オプション・確かめの名前の語。文の言い回しは見ない）。
# 検証一式（sh tests/static.sh・sh tests/install.sh・sh tests/install-nosudo.sh）は別に実行する。
# LIVE=1 のときだけ、本物の claude -p の新しいセッションでプラグインと skill の見え方を確かめ、空の設定の置き場で config/claude/README.md の
# 新しい端末の手順が通ることも確かめる。permissions の deny が効くこと（haiku をもう 1 回）と、claude doctor が settings.json を読めることも
# 確かめる（haiku を 2 回呼ぶ。課金あり。marketplace の取得にネットワークが要る。
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
for r in 'Bash(git push --force:*)' 'Bash(git push -f:*)' 'Bash(git push --force-with-lease:*)' 'Read(~/.ssh/**)' 'Read(~/.codex/auth.json)' \
  'Bash(git push:*)' 'Bash(gh pr merge:*)' 'Bash(integrate --human-approved:*)' 'Bash(integrate setup --force:*)' 'Edit(~/.config/integrate/**)' \
  'Read(//**/.env)' 'Read(.env.*)' 'Read(!.env.example)' 'Read(!.env.sample)' 'Read(!.env.template)' \
  'Read(//**/*.pem)' 'Read(//**/*.key)' 'Read(//**/*.p12)' 'Read(//**/*.pfx)' \
  'Read(~/.aws/**)' 'Read(~/.config/gh/**)' 'Read(~/.kube/**)' 'Edit(//**/.git/codex-review/**)'; do
  check "permissions.deny に $r" jq -e --arg r "$r" '.permissions.deny | index($r)' "$S"
done
# 除外の !規則は、除く側の Read(.env.*) より後に置かないと効かない
check "permissions.deny で、見本の除外（.env.example・.env.sample・.env.template）は Read(.env.*) より後" \
  jq -e '.permissions.deny as $d | ($d | index("Read(.env.*)")) as $a
    | ["Read(!.env.example)", "Read(!.env.sample)", "Read(!.env.template)"] | all(. as $x | ($d | index($x)) > $a)' "$S"
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

# ---- 指示と skill の規則が残っている。規則 1 つごとに、その規則の行だけにある語（コマンド・オプション・名前）を 2〜4 つ選び、
#      どれか 1 行にすべてがそろうかを見る（ほかの行の語で通らない）。文の言い回しは見ない（言い換えでは落ちず、規則の行ごと消えたら落ちる）。
#      規則を変えたら、ここの語も変える
C="$ROOT/config/agents/AGENTS.md"; WU="$ROOT/config/agents/skills/wrap-up/SKILL.md"; IS="$ROOT/config/agents/skills/issue/SKILL.md"
HO="$ROOT/config/agents/skills/handoff/SKILL.md"
# rule <説明> <ファイル> <語>…: ファイルのどれか 1 行に、語がすべてある
rule() {
  rd="$1" rf="$2"; shift 2
  # ファイルは awk の引数で読む（開けなければ awk が失敗し、検査も落ちる）
  check "$rd（$(printf '「%s」' "$@") が 1 行に）" awk 'BEGIN { for (i = 2; i < ARGC; i++) w[i] = ARGV[i]; n = ARGC - 1; ARGC = 2 }
    { for (i = 2; i <= n; i++) if (index($0, w[i]) == 0) next; found = 1; exit }
    END { exit !found }' "$rf" "$@"
}
# absent <説明> <ファイル> <語>: 消した規則や古い記述が戻っていない
absent() { check "$1" sh -c '! grep -qF -- "$2" "$1"' _ "$2" "$3"; }
for h in 作業の哲学 規約 レビュー モデルの割り当て Git Linear スクリーンショット; do check "グローバル指示に「$h」の節がある" grep -Eq "^#+ .*$h" "$C"; done
# 作業の哲学・規約・読み替え
rule "グローバル指示: 優先順位" "$C" '正しさと堅牢さ' '読みやすさ' 'コードの少なさ'
rule "グローバル指示: 開発の手順は superpowers の skill" "$C" '開発の手順' 'superpowers の skill に従う'
rule "グローバル指示: 検証はテストを TDD で" "$C" '**検証**' 'superpowers の TDD'
rule "グローバル指示の読み替え: skill の呼び出し" "$C" 'skill の呼び出し' '`/issue`' '`$issue`'
rule "グローバル指示の読み替え: 選択肢での質問" "$C" '選択肢での質問' AskUserQuestion '番号'
rule "グローバル指示の読み替え: 会話の区切り" "$C" '会話の区切り' '`/clear`' 'handoff skill' '`/new`'
rule "グローバル指示: Python は uv" "$C" 'Python' '`uv`' '`uv run`'
rule "グローバル指示: 作業中の保存は relay" "$C" 'remember skill' '--tags relay' '`ARK-nn` で始める'
# レビュー
rule "グローバル指示: 指摘は「直す」と「参考」に分け、FAIL は「直す」だけ" "$C" 'codex-review' '「直す」と「参考」に分ける' 'FAIL の理由になるのは「直す」だけ'
rule "グローバル指示: 起こりにくい入力は「参考」" "$C" '実際には起こりにくい' '「参考」'
rule "グローバル指示: 計画のレビュー" "$C" 'codex-review plan <計画書>' '反映してから実装'
rule "グローバル指示: ブランチのレビューは PASS まで、2 回目からは前回の指摘と差分" "$C" 'codex-review branch [ベース]' 'VERDICT: PASS' '前回の「直す」が直ったか' 'その後の修正の差分だけ'
rule "グローバル指示: 「参考」は issue の本文に" "$C" '「参考」の指摘は直さず' 'issue の本文に書く'
rule "グローバル指示: 2 往復で通らなければ notify" "$C" '2 往復で PASS にならなければ' 'notify'
# モデルの割り当て
rule "グローバル指示: 設計・計画のモデル" "$C" '| 設計・計画 |' '`opus`・`xhigh`'
rule "グローバル指示: 実装のモデル" "$C" '| 実装（plan のタスクごと） |' '`sonnet`・`high`'
rule "グローバル指示: 検証のモデル（実装と別の担当）" "$C" '| 検証（受け入れ条件' '実装と別のサブエージェント' '`opus`・`high`'
rule "グローバル指示: 広い検索のモデル" "$C" '| 広い検索 |' '`model: haiku`'
rule "グローバル指示: Agent の description は役割名" "$C" 'Agent の description は役割名' '`plan`' '`impl`' '`verify`' '`explore`'
# Git
rule "グローバル指示: integrate setup" "$C" '`integrate setup`' '`integrate setup --show`' '`--force`'
rule "グローバル指示: kind=pr は PR を出した後 rebase しない" "$C" '`pr`' 'PR を出した後は rebase せず'
rule "グローバル指示: ブランチと worktree の作り方" "$C" 'feature/<作業内容>' 'worktree add --no-track' '.worktrees/' 'origin/<最上位>'
rule "グローバル指示: コミットは構造と振る舞いを分ける" "$C" '`refactor:`' '`feat:`' 'テストと実装は同じコミット'
rule "グローバル指示: Linear と superpowers の情報はリポジトリに書かない" "$C" 'Linear と superpowers の情報は' 'リポジトリに入るもの' 'ブランチ名' '書かない'
rule "グローバル指示: 理由は番号やパスで指さず文を書く" "$C" '番号や spec・plan のパスで指さずに'
rule "グローバル指示: Linear の情報（すべて）" "$C" '- Linear:' 'issue 番号' '受け入れ条件の番号' 'すべて'
rule "グローバル指示: superpowers の情報（すべて）" "$C" '- superpowers:' 'spec・plan' 'skill の名前' 'すべて'
rule "グローバル指示: .superpowers/ の中は対象外" "$C" '対象外' '`.superpowers/`'
rule "グローバル指示: dotfiles の例外" "$C" 'dotfiles の例外' '実際の情報は dotfiles にも書かない'
rule "グローバル指示: 統合の前の順番" "$C" '統合の前の順番' 'git rebase origin/<最上位>' 'PR を出す前だけ' 'codex-review branch origin/<最上位>'
rule "グローバル指示: 統合は integrate だけ" "$C" '統合は `integrate` だけ' '`gh pr merge`' 'integrate --human-approved'
rule "グローバル指示: 強制 push はしない" "$C" '強制 push はしない'
# Linear
rule "グローバル指示: issue は /issue で始める" "$C" '`/issue ARK-nn` で始める'
rule "グローバル指示: 本文が正本、plan は .superpowers/plans/" "$C" '本文が正本' '.superpowers/plans/' 'docs/superpowers/' '作らない'
rule "グローバル指示: 状態" "$C" 'In Progress' '未マージ' 'Done'
rule "グローバル指示: wrap-up は統合の前に作業ブランチの上で" "$C" '統合の前に、作業ブランチの上で `/wrap-up`'
rule "グローバル指示: 将来やること・見送ったことは Backlog" "$C" '見送った' 'Backlog'
rule "グローバル指示: Linear が使えないときは .superpowers/tasks/" "$C" 'Linear が使えない' '.superpowers/tasks/<短い名前>.md'
# スクリーンショット
rule "グローバル指示: スクショは Windows の Screenshots の最新" "$C" 'ls -t /mnt/c/Users/*/Pictures/Screenshots/*.png | head'
rule "グローバル指示: WSL 以外ではスクショを見られない" "$C" 'WSL 以外' 'そう伝える'
absent "グローバル指示に経緯（harness）が無い" "$C" harness
absent "グローバル指示に Karpathy の全文が無い" "$C" 'Karpathy guidelines'
# shellcheck disable=SC2088 # 文字の ~ を探す（展開しない）
absent "グローバル指示に古いスクショの転送が無い" "$C" '~/screenshots'
# skill
rule "issue: worktree は .worktrees/ に origin/<最上位> から" "$IS" '.worktrees/<作業内容>' 'origin/<最上位>' '--no-track' 'ブランチ: feature/<作業内容>'
rule "issue: 登録済みの worktree へ移る" "$IS" 'git worktree list' '登録済み'
rule "issue: コメントの節目はグローバル指示に従う" "$IS" 'コメントの節目' 'グローバル指示の Linear の節'
rule "wrap-up: 「参考」を Backlog に起こすか決める" "$WU" '「参考」' 'Backlog の issue に起こすか'
rule "wrap-up: リポジトリには Linear・superpowers の情報を書かない" "$WU" 'Linear・superpowers の情報を書かない' 'グローバル指示の Git の節'
rule "wrap-up: README に理由や経緯は書かない" "$WU" '**README・設計メモ**' '理由や経緯は書かない'
rule "wrap-up: 5 は統合の後に" "$WU" '## 5. 統合の後'
rule "wrap-up: bare・github の統合の確認" "$WU" 'git merge-base --is-ancestor' 'origin/<base>'
rule "wrap-up: pr の統合の確認" "$WU" 'MERGED' 'baseRefName' 'headRefOid'
rule "wrap-up: Done にする" "$WU" 'Linear にコメントして Done'
rule "wrap-up: relay を archive する" "$WU" 'index("relay")' 'tinymemory archive'
rule "wrap-up: kind と base は integrate setup --show から" "$WU" '`<kind>`・`<base>`' 'integrate setup --show'
rule "wrap-up: worktree とブランチの片づけ（pull は元のブランチが base のときだけ）" "$WU" 'ブランチが `<base>` なら' 'git pull --ff-only' 'git worktree remove' 'git branch -D feature/<作業内容>'
rule "wrap-up: 次の作業の決め方（示された作業 → 同じリポジトリの Todo → 尋ねて待つ）" "$WU" 'ユーザーが示した作業' '同じリポジトリ' 'Todo' '優先度の高い順' '番号の小さい順' 'ほかのリポジトリの Todo' '選択肢で示して尋ね' '答えを待つ'
rule "wrap-up: 次の作業の始め方" "$WU" 'handoff skill' '`/clear`' '`/new`' '`/issue ARK-nn`' 'herdr の中なら' 'そのリポジトリで新しいセッション'
absent "wrap-up は git branch -d を使わない（base と元のブランチが違うと拒むため）" "$WU" 'git branch -d'
rule "handoff: description に統合の後の次の issue" "$HO" 'description:' '統合の後に次の issue を始める'
rule "handoff: 次の issue は /issue から" "$HO" '次の issue の番号' '`/issue ARK-nn` から始める'
rule "handoff: 保存は relay" "$HO" 'remember skill' '--tags relay'
# 文書
rule "dotfiles の CLAUDE.md: 開発の手順は superpowers" "$ROOT/CLAUDE.md" '開発の手順はプラグイン superpowers'
rule "dotfiles の CLAUDE.md: コミットの前の検査" "$ROOT/CLAUDE.md" 'sh tests/static.sh' 'sh tests/install.sh' 'sh tests/acceptance.sh'
rule "config/codex/README.md: codex-review の仕分けと再レビュー" "$ROOT/config/codex/README.md" '「直す」' '「参考」' '<その HEAD>...<HEAD>'
rule "config/claude/README.md: superpowers の入れ方" "$ROOT/config/claude/README.md" 'claude plugin install superpowers@claude-plugins-official'

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
  # claude doctor: settings.json の規則を読めること。壊れた規則を入れた写しで Invalid settings が出る（見分けられる）ことも確かめる
  mkdir -p "$D/doc" "$D/bad"; cp "$S" "$D/doc/settings.json"
  jq '.permissions.deny += ["Foo(bar"]' "$S" > "$D/bad/settings.json"
  doctor() { (cd "$D" && CLAUDE_CONFIG_DIR="$D/$1" claude doctor </dev/null 2>&1); }
  doctor bad > "$D/doctor.bad.txt"; doctor doc > "$D/doctor.doc.txt"
  lcheck "（LIVE）claude doctor は壊れた規則を Invalid settings に出す（見分けられる）" grep -q 'Invalid settings' "$D/doctor.bad.txt"
  lcheck "（LIVE）claude doctor は settings.json に Invalid settings を出さない" \
    sh -c "! grep -q 'Invalid settings' '$D/doctor.doc.txt' && grep -q 'Claude Code doctor' '$D/doctor.doc.txt'"
  # permissions が効く: cwd を worktree の形（.worktrees/x）にして、cwd の外（--add-dir）のレビューの結果と .env 類を試す。
  # 対照の ctrl.md の Edit が通るのは、acceptEdits と --add-dir で cwd の外を書けること（拒否がモードのせいでないこと）の確かめ。
  # .git/ は保護されたパスで規則が無くても acceptEdits では書けない（文言は Claude requested permissions to edit …）ので、
  # 規則による拒否は文言（denied by your permission settings）で見分ける（Claude Code が文言を変えたら落ちて分かる）。
  # モデルがツールを呼ばなければ行が無く落ちる（記録が残る）。
  P="$(cd "$D" && pwd -P)/perm"; R="$P/.git/codex-review"; X="$P/.worktrees/x"
  mkdir -p "$R" "$X/a"; git init -q "$P"
  printf 'VERDICT: FAIL\n' > "$R/z.md"; printf 'VERDICT: FAIL\n' > "$P/ctrl.md"
  for f in ok.txt .env a/.env .env.local .env.example a/.env.example; do echo "x=1" > "$X/$f"; done
  jq '{permissions: {deny: .permissions.deny}}' "$S" > "$D/perm.json"
  (cd "$X" && claude -p "Do exactly these tool calls in order, one call each, and keep going even if a call fails: Read ok.txt; Read .env; Read a/.env; Read .env.local; Read .env.example; Read a/.env.example; Read $P/ctrl.md; Edit $P/ctrl.md replacing FAIL with PASS; Read $R/z.md; Edit $R/z.md replacing FAIL with PASS; Write $R/y.md with the text hello. Use no other tools. Then answer DONE." \
    --model haiku --settings "$D/perm.json" --setting-sources local --permission-mode acceptEdits --add-dir "$P" --tools Read,Edit,Write \
    --strict-mcp-config --no-session-persistence --output-format stream-json --verbose > "$D/perm.jsonl" 2> "$D/perm.err" </dev/null)
  # 「<ツール> <パス> ok|denied:rule|denied:other」の行（パスは cwd と $P を前から外す。モデルは相対パスも絶対パスも使う）
  jq -rs --arg cwd "$X/" --arg top "$P/" '([.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
    | {key: .id, value: "\(.name) \(.input.file_path | ltrimstr($cwd) | ltrimstr($top))"}] | from_entries) as $p
    | .[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
    | "\($p[.tool_use_id]) \(if .is_error | not then "ok" elif (.content | tostring | test("denied by your permission settings")) then "denied:rule" else "denied:other" end)"' \
    "$D/perm.jsonl" > "$D/perm.txt" 2>/dev/null
  for l in 'Read ok.txt ok' 'Read .env denied:rule' 'Read a/.env denied:rule' 'Read .env.local denied:rule' 'Read .env.example ok' 'Read a/.env.example ok' \
    'Edit ctrl.md ok' 'Edit .git/codex-review/z.md denied:rule' 'Write .git/codex-review/y.md denied:rule'; do
    lcheck "（LIVE）permissions: $l" grep -qx "$l" "$D/perm.txt"
  done
  lcheck "（LIVE）permissions: ctrl.md が PASS になった" grep -qx 'VERDICT: PASS' "$P/ctrl.md"
  lcheck "（LIVE）permissions: z.md は FAIL のまま" grep -qx 'VERDICT: FAIL' "$R/z.md"
  lcheck "（LIVE）permissions: y.md は作られない" [ ! -e "$R/y.md" ]
  # LIVE が落ちたら、原因（未ログイン・プラグイン未導入など）を見られるように記録を残す
  if [ "$live_fail" != 0 ]; then trap - EXIT; echo "（LIVE）記録を残した: $L・$D/stderr.txt・$N/steps.log"; fi
fi

[ "$fail" = 0 ] && echo "acceptance claude-config: ok"
[ "$fail" = 0 ]
