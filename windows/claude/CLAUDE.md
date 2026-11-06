@~/dotfiles/config/agents/AGENTS.md

## Windows

この端末はネイティブの Windows（WSL ではない）。上の指示との違い:

- スクリーンショット: Windows のピクチャの `Screenshots`（`~/Pictures/Screenshots`。スニッピングツールが撮影のたびに保存する）の最新ファイルを、ファイルを読むツールで見る。上の「WSL 以外の端末にはスクショを見る手段が無い」より優先する。新しい順のパスは Git Bash で `ls -t ~/Pictures/Screenshots/*.png | head`
- dotfiles のコマンド（`codex-review`・`integrate`・`notify`・`handoff`、heredoc で本文を渡す `tinymemory save`）は Bash ツール（Git Bash）で実行する（POSIX のスクリプトと heredoc なので PowerShell ツールでは使わない）。Bash ツールの PATH には SessionStart のフックが dotfiles の `bin` と jq の shim（改行を LF で出す）を足す
