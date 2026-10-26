# config/git

- `config/git/config`: user / defaultBranch、rebase 中心の pull・push（`push.autoSetupRemote` は git 2.37 から）、衝突は diff3、bare の守り（この端末の bare は新旧とも、早送りでない push とブランチの削除を拒む）。端末固有設定は `~/.gitconfig`（リポジトリ外）
- `config/git/hooks-nosign/`: コミットメッセージから AI 由来の行を消す commit-msg フック: AI のツールが付ける `Co-Authored-By`（メールアドレスが Claude Code の `noreply@anthropic.com`、Codex の `noreply@openai.com` のもの）、`Claude-Session:`、`Generated with Claude Code`・`Generated with Codex` だけの行（行頭の 🤖、リンクの形、行末の `.` も）、セッションの URL（`https://claude.ai/code/session_…`）だけの行。人の共同作者（名前に Claude などを含んでも）と、文中でこれらに触れる行は残す。integrate が作る PR の本文はコミットメッセージから作る（`gh pr create --fill`）ので、PR にも残らない。業務サーバーだけが使う（下の「業務サーバー」）
- `config/git/ignore`: 全リポジトリ共通の除外（superpowers の plan と台帳 `.superpowers/`、issue ごとの worktree `.worktrees/`）

## 業務サーバー

端末ごとの違いは git のアカウントと署名だけ（私用の端末では Claude Code の既定どおりコミットに AI の `Co-Authored-By` などが付く）。業務サーバーでは `~/.gitconfig`（端末ローカル）に次を書く。`core.hooksPath` は各リポジトリの `.git/hooks` より優先されるので、業務のリポジトリで git フックを使い始めたら見直す:

```ini
[user]
	name = <業務の名前>
	email = <業務のアドレス>
[core]
	hooksPath = ~/.config/git/hooks-nosign
```
