# config/git

- `config/git/config`: user / defaultBranch、rebase 中心の pull・push（`push.autoSetupRemote` は git 2.37 から）、`rebase.autoSquash`（`-i` のときだけ効く）・`rebase.updateRefs`（積んだブランチも動かす。git 2.38 から）、`diff.algorithm = histogram`、`transfer.fsckObjects`（受け取るオブジェクトを検査する。古い不正なオブジェクトを持つリポジトリの clone が止まったら `git -c transfer.fsckObjects=false clone …`）、衝突は diff3（zdiff3 にしない: git 2.35 より古い git は `zdiff3` を読んだところで merge・rebase などが止まり、`~/.gitconfig` でも上書きできない）、bare の守り（この端末の bare は新旧とも、早送りでない push とブランチの削除を拒む）。端末固有設定は `~/.gitconfig`（リポジトリ外）
- `config/git/hooks-nosign/`: コミットメッセージから AI 由来の行を消す commit-msg フック: AI のツールが付ける `Co-Authored-By`（メールアドレスが Claude Code の `noreply@anthropic.com`、Codex の `noreply@openai.com` のもの）、`Claude-Session:`、`Generated with Claude Code`・`Generated with Codex` だけの行（行頭の 🤖、リンクの形、行末の `.` も）、セッションの URL（`https://claude.ai/code/session_…`）だけの行。人の共同作者（名前に Claude などを含んでも）と、文中でこれらに触れる行は残す。integrate が作る PR の本文はコミットメッセージから作る（`gh pr create --fill`）ので、PR にも残らない。業務サーバーだけが使う（下の「業務サーバー」）
- `config/git/ignore`: 全リポジトリ共通の除外（superpowers の plan と台帳 `.superpowers/`、issue ごとの worktree `.worktrees/`）

## 業務サーバー

端末ごとの違いは git のアカウント、AI の署名の行、コミットの SSH 署名だけ（私用の端末では Claude Code の既定どおりコミットに AI の `Co-Authored-By` などが付く）。業務サーバーでは `~/.gitconfig`（端末ローカル）に次を書く。`core.hooksPath` は各リポジトリの `.git/hooks` より優先されるので、業務のリポジトリで git フックを使い始めたら見直す:

```ini
[user]
	name = <業務の名前>
	email = <業務のアドレス>
	signingKey = ~/.ssh/id_ed25519
[core]
	hooksPath = ~/.config/git/hooks-nosign
[gpg]
	format = ssh
[commit]
	gpgSign = true
```

コミットの SSH 署名は、署名に使う公開鍵を GitHub などに署名の鍵（Signing Key）として登録する（git 2.34 から）。`signingKey` は秘密鍵のパスにする（公開鍵の `.pub` を書くと、ssh-agent に鍵が入っていない端末では署名に失敗してコミットできない）。
