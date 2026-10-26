# config/claude

- `config/claude/settings.json`: プラグイン（tinymemory・ponytail は GitHub の marketplace、superpowers は公式の marketplace）、remote-control を常に（`remoteControlAtStartup`）、hooks（状態表示 + compact・resume 後の記憶の注入 + integrate-hook・handoff・context-nudge・agent-pane）、permissions（`git push`・`gh pr merge`・`integrate --human-approved`・`integrate setup --force` と `.env`・`~/.ssh`・`~/.codex/auth.json` の読み取り、`~/.config/integrate/` の編集を禁止。push の禁止は統合を `integrate` に通すための抑止で、Bash の規則は前方一致なので `git -C . push` や `bin/integrate setup --force` などは捕らえない。機械的な関門は integrate 自身。設定の上書きは integrate が端末からだけ受け付ける）、ステータスライン、ログ 365 日
- `config/claude/statusline.sh`: ステータスライン（2 行。Claude のモデルと effort → Codex のモデルと effort（`~/.codex/config.toml` から）→ ブランチと、コンテキスト・5 時間・週の上限のメーター → Codex の 5 時間・週の上限のメーター（`~/.codex/sessions` の更新の新しいセッションの最後の記録から）。Nerd Font のアイコン（Claude は橙、Codex は白）。Claude・OpenAI のアイコン（`nf-cod-claude`・`nf-cod-openai`）は Nerd Fonts 3.5.0 以降のフォントが要る）

## Claude Code の手順

開発の手順（設計・計画・TDD・レビュー）は [superpowers](https://github.com/obra/superpowers)（プラグイン。公式の marketplace `claude-plugins-official`）の skill に任せる。ブランチ・worktree・統合の方法はグローバル指示（`config/agents/AGENTS.md`）の「Git」の節で、統合の後の片づけ（Linear の完了・relay・worktree）は `/wrap-up` の「統合の後」。Linear の記録は dotfiles の skill（`/issue`・`/wrap-up`）。dotfiles が受け持つのは次の 3 つ:

- `config/claude/settings.json` の宣言（`extraKnownMarketplaces` の `claude-plugins-official`・`tinymemory`・`ponytail` と、`enabledPlugins` の `superpowers@claude-plugins-official`・`tinymemory@tinymemory`・`ponytail@ponytail`。ponytail は node で動き、コードを最小にする指示を毎ターン入れる）。宣言だけでは入らないので、新しい端末では `install.sh` の後に `claude plugin marketplace add anthropics/claude-plugins-official` → `claude plugin install superpowers@claude-plugins-official` → `claude plugin marketplace add arkrtm/tinymemory` → `claude plugin install tinymemory@tinymemory` → `claude plugin marketplace add DietrichGebert/ponytail` → `claude plugin install ponytail@ponytail`
- skill の `issue`・`wrap-up`（`install.sh` が `~/.claude/skills` と `~/.agents/skills` にリンクする）と `handoff`（`~/.claude/skills` だけ）
- ステータスライン（上の `config/claude/statusline.sh`）

更新は `claude plugin marketplace update <marketplace>` → `claude plugin update <plugin>`（新しいセッションから効く）。`LIVE=1 sh tests/acceptance/claude-config.sh` は、本物の `claude -p` の新しいセッションで superpowers・tinymemory・ponytail と skill の issue・wrap-up が見えることと、空の設定の置き場で上の新しい端末の手順が通り settings.json を変えないことを確かめる（haiku を 1 回呼ぶ。課金あり。marketplace の取得にネットワークが要る）。
