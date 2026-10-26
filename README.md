# dotfiles

mac / linux（Ubuntu・WSL）共通の開発環境。Windows ネイティブは対象外。
環境構築は **sudo 不要・ユーザー領域のみ**（`~/.local` 以下。システム全体には何も入れない）。Python は uv、Node は fnm で管理する（conda / conda-forge / pixi、システムや Homebrew の Python・Node は開発に使わない）。設定は `$HOME` へのシンボリックリンクなので、
**どの端末で編集してもこのリポジトリが変わる** → commit / push → 他端末で `git pull`（LINKS を変えたとき、または `ssh/config` を変えたときは `./install.sh` も。umask 002 の端末では pull で `ssh/config` が 664 になり、ssh が拒むため）。

## セットアップ

前提: `git` `curl` があること（sudo は不要）。

```sh
git clone https://github.com/arkrtm/dotfiles.git ~/dotfiles
~/dotfiles/install.sh        # 何度実行しても安全。既存ファイルは *.bak.<日時> に退避
```

## 文書

- `INSTALL.md` — `install.sh` がやることと、対象外のもの（GUI 端末・管理者権限が要るもの）
- `config/README.md` — README の無い小さな設定（starship・tmux・ghostty・nvim・yazi・bat）
- `config/claude/README.md` — Claude Code の設定と手順（新しい端末の plugin の入れ方）
- `config/codex/README.md` — Codex の設定と手順、`codex-review`
- `config/agents/README.md` — 全プロジェクト共通の指示と skill
- `config/git/README.md` — git の設定と業務サーバー
- `config/herdr/README.md` — 常時起動サーバー（herdr と Claude Code）
- `config/wezterm/README.md`・`config/mise/README.md` — WezTerm（Windows）、mise の注意
- `bin/README.md` — コマンドと `integrate setup`
- `tests/README.md` — 検査・CI・GitHub の main の保護
- `shell/README.md`・`ssh/README.md`・`mac/README.md`
