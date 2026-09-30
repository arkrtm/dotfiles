# dotfiles

- このリポジトリは `$HOME` にリンクされている（`install.sh`）。編集は保存した瞬間にこの端末の実環境に効く: シェル設定、`~/.claude` の設定・skill、実行中の Claude Code の hooks（`bin/harness-hook`）。hook を壊すと自分の編集・コミットの関門も止まるので、編集したらすぐテストする。skill（`config/claude/skills`）の追加・変更も起動中のセッションにすぐ効く。例外: agent の定義（`config/claude/agents`）は起動中のセッションにはすぐには読み込まれない（新しい agent が見えたのは十数分後。すぐ確かめるなら別プロセスの `claude -p`）
- 検証は `.harness-verify` の 3 本（コードを変えたら、同じ内容に対してすべて通さないとコミットできない）。`install.sh`・shell・mise の設定を変えたら `tests/install-nosudo.sh` まで通す。関門の対象には `.harness-code` で `config/*`・`shell/*`・`CLAUDE.md` を足してある（skill や設定の Markdown・JSON の変更にも検証とレビューが要る）
