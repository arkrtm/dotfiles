# dotfiles

- このリポジトリは `$HOME` にリンクされている（`install.sh`）。編集は保存した瞬間にこの端末の実環境に効く: シェル設定、`~/.claude` の設定・skill、実行中の Claude Code の hooks（`bin/harness-hook`）。hook を壊すと自分の編集・コミットの関門も止まるので、編集したらすぐテストする。例外: skill と agent の定義（`config/claude/skills`・`agents`）はセッション開始時に読まれ、変更は新しいセッションから効く
- テストのコマンドは `/verify` の一覧と README。`install.sh`・shell・mise の設定を変えたら `tests/install-nosudo.sh` まで通す
