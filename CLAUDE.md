# dotfiles

- このリポジトリは `$HOME` にリンクされている（`install.sh`）。編集は保存した瞬間にこの端末の実環境に効く: シェル設定、`~/.claude` の設定（`settings.json`）と全プロジェクト共通の指示（`CLAUDE.md`）、skill（`config/claude/skills`）。`settings.json` を壊すと Claude Code の設定が読めなくなるので、編集したらすぐテストする
- 開発の手順はプラグイン superpowers（公式の marketplace `claude-plugins-official`）の skill に任せ、ここには置かない。dotfiles が受け持つのは、`settings.json` の宣言（`extraKnownMarketplaces`・`enabledPlugins`）と、Linear の記録の skill（`config/claude/skills` の `issue`・`wrap-up`。`~/.claude/skills` にリンクする）
- コミットの前に、同じ内容に対して `sh tests/install.sh` と `sh tests/acceptance.sh` を通す。受け入れ検査は `tests/acceptance/*.sh` に置き、`tests/acceptance.sh` がまとめて実行する。追加の確認: `install.sh`・shell・mise の設定を変えたら `DOCKER='ssh nas docker' sh tests/install-nosudo.sh` も、`config/nvim` を変えたら `sh tests/nvim.sh` も、プラグインの宣言を変えたら `LIVE=1 sh tests/acceptance/plugin-switch.sh` も通す
