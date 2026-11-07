# config/codex

- `config/codex/config.toml.tmpl`: `~/.codex/config.toml` を生成する（リンクしない）。Codex の設定: モデル sol（`gpt-6.1-sol`）・effort xhigh に固定、ponytail、tinymemory の書き込み先、Linear の MCP。リンクしないのはホームの絶対パスが要るため。Codex が書き込んだ分は install.sh の再実行で消える。ただしフックの承認（`hooks.state`）・プロジェクトの信頼（`projects`）・表示（`tui`）の表は引き継ぐ

## Codex の手順

Codex はレビュー役（`bin/codex-review`。AGENTS.md の「レビュー」）。`install.sh` が本体・config.toml・ponytail・tinymemory の hook まで入れる。新しい端末ではその後に `codex login` → `codex plugin add superpowers@openai-curated-remote`（Codex 公式のカタログ。ログインが要る）→ `codex` を起動して `/hooks` で tinymemory と ponytail の hook を承認（端末ごとに一度）。

- `codex-review plan <計画書>` / `codex-review branch [ベース]` — `codex exec` を読み取り専用の sandbox・effort xhigh・フックなし（tinymemory の記憶を入れない。ponytail のフックも止まる）で呼ぶ。指摘は「直す」と「参考」に分けさせる（分け方は AGENTS.md の「レビュー」）。branch の最後の行は、「直す」が無ければ `VERDICT: PASS`、あれば `VERDICT: FAIL`。branch の結果は `<git の共通ディレクトリ>/codex-review/<日時>-branch-<merge-base>-<HEAD>.md` にも保存する（`integrate` が読む）。同じ merge-base への結果のうち、最後の行が `VERDICT: PASS`/`VERDICT: FAIL` のもの（空や途中で終わった結果は飛ばす）で、HEAD が今の HEAD の祖先（今の HEAD は除く）で最新のものがあれば、全体でなく、その結果の本文を依頼文に入れて、その「直す」が直ったかと `<その HEAD>...<HEAD>` の修正だけを見させる（無ければ全体。本文を読めなければレビューせずに失敗する）
