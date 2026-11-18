@~/dotfiles/config/agents/AGENTS.md

## Windows

この端末はネイティブの Windows（WSL ではない）。上の指示との違い:

- シェル: コマンドは PowerShell ツールで実行し、Bash ツール（Git Bash）は使わない。利用者に実行を頼むコマンドも PowerShell の形で書く（パスは `D:\...` の形。`/d/...` のような Git Bash のパスにしない）
- スクリーンショット: Windows のピクチャの `Screenshots`（`~/Pictures/Screenshots`。スニッピングツールが撮影のたびに保存する）の最新ファイルを、ファイルを読むツールで見る。上の「WSL 以外の端末にはスクショを見る手段が無い」より優先する。新しい順のパスは `Get-ChildItem ~/Pictures/Screenshots/*.png | Sort-Object LastWriteTime -Descending | Select-Object -First 10 -ExpandProperty FullName`
- dotfiles のコマンド（`codex-review`・`integrate`・`notify`・`handoff`）は PowerShell からそのまま呼ぶ（ユーザーの Path にある `windows/bin` の `.ps1` が、Git Bash を探して `bin/` のスクリプトを動かす）。上の指示が heredoc で本文を渡すところ（`tinymemory save` など）は、単一引用符の here-string をパイプで渡す（閉じの `'@` は行頭に置く）:

  ```powershell
  @'
  <本文>
  '@ | tinymemory save --type fact --title "<タイトル>"
  ```
