# config/codex

- `config/codex/config.toml.tmpl`: `~/.codex/config.toml` の元（リンクしない。ホームの絶対パスが要るため）。Codex の設定: モデル sol（`gpt-6.1-sol`）・effort xhigh に固定、ponytail、tinymemory の書き込み先、Linear の MCP。install.sh は既存の config.toml と結合する: テンプレートにあるキーはテンプレートの値にし、ほかのキーと表（Codex の CLI・デスクトップが書く notify・プラグイン・MCP・承認・信頼など）は値ごと残す。意味が同じなら書き換えない（表の並びと書式の違いは見ない）。書き換えるときは既存を `config.toml.bak.<日時>` に退避する。**テンプレートから消したキーは各端末の config.toml に残り続ける**（要らなければ各端末で手で消す）。既存の `[mcp_servers.linear]` が command 方式（テンプレートの url と混ぜると Codex が起動しない）、TOML として読めない、書き出しを読み直すと結合の結果と違う、のどれかなら書かずに install.sh を止める
- `config/codex/merge-config.py`: 上の結合。install.sh が mise の uv で、uv の管理する Python と版を固定した tomlkit で実行する（システムの python3 は使わない）。既存の文書を土台にテンプレートのキーだけを書き換えるので、既存のコメント・並び・書式は残る（既存が無ければテンプレートをコメントごと書く）

## Codex の手順

Codex はレビュー役（`bin/codex-review`。AGENTS.md の「レビュー」）。`install.sh` が本体・config.toml・ponytail・tinymemory の hook まで入れる。新しい端末ではその後に `codex login` → `codex plugin add superpowers@openai-curated-remote`（Codex 公式のカタログ。ログインが要る）→ `codex` を起動して `/hooks` で tinymemory と ponytail の hook を承認（端末ごとに一度）。

- `codex-review plan <計画書>` / `codex-review branch [ベース]` — `codex exec` を読み取り専用の sandbox・effort xhigh・フックなし（tinymemory の記憶を入れない。ponytail のフックも止まる）で呼ぶ。指摘は「直す」と「参考」に分けさせる（分け方は AGENTS.md の「レビュー」）。branch の最後の行は、「直す」が無ければ `VERDICT: PASS`、あれば `VERDICT: FAIL`。branch の結果は `<git の共通ディレクトリ>/codex-review/<日時>-branch-<merge-base>-<HEAD>.md` にも保存する（`integrate` が読む）。同じ merge-base への結果のうち、最後の行が `VERDICT: PASS`/`VERDICT: FAIL` のもの（空や途中で終わった結果は飛ばす）で、HEAD が今の HEAD の祖先（今の HEAD は除く）で最新のものがあれば、全体でなく、その結果の本文を依頼文に入れて、その「直す」が直ったかと `<その HEAD>...<HEAD>` の修正だけを見させる（無ければ全体。本文を読めなければレビューせずに失敗する）
