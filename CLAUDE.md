# dotfiles

- このリポジトリは `$HOME` にリンクされている（`install.sh`）。編集は保存した瞬間にこの端末の実環境に効く: シェル設定、`~/.claude` の設定・skill、実行中の Claude Code の hooks（`bin/harness-hook`）。hook を壊すと自分の編集・コミットの関門も止まるので、編集したらすぐテストする。skill（`config/claude/skills`）の追加・変更も起動中のセッションにすぐ効く。例外: agent の定義（`config/claude/agents`）は起動中のセッションにはすぐには読み込まれない（新しい agent が見えたのは十数分後。すぐ確かめるなら別プロセスの `claude -p`）
- テストのコマンドは `/verify` の一覧と README。`install.sh`・shell・mise の設定を変えたら `tests/install-nosudo.sh` まで通す
