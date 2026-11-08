# dotfiles

mac / linux（Ubuntu・WSL）共通の開発環境。ネイティブの Windows は `windows/README.md` の手順で入れる。
環境構築は **sudo 不要・ユーザー領域のみ**（`~/.local` 以下。システム全体には何も入れない）。Python は uv、Node は mise で管理する（版はプロジェクトの .node-version・.nvmrc・mise.toml、無ければ最新の LTS。conda / conda-forge / pixi、システムや Homebrew の Python・Node は開発に使わない）。設定は `$HOME` へのシンボリックリンクなので、
**どの端末で編集してもこのリポジトリが変わる** → commit / push → 他端末で `git pull`（LINKS を変えたとき、または `ssh/` の設定を変えたときは `./install.sh` も。umask 002 の端末では pull で `ssh/` の設定が 664 になり、ssh が拒むため）。

## セットアップ

前提: `git` `curl` があること（sudo は不要）。Linux は `libatomic1` も要る（Node 26 以降。多くの端末には入っている。無ければ INSTALL.md の対象外の表）。

```sh
git clone https://github.com/arkrtm/dotfiles.git ~/dotfiles
~/dotfiles/install.sh        # 何度実行しても安全。既存ファイルは *.bak.<日時> に退避
```

## 版の固定と更新

道具の版はリポジトリで固定し、全端末が同じ版を入れる。上げるときは「固定を作り直す → 検査（`sh scripts/check` と `sh tests/install-nosudo.sh`）→ 差分を見てコミット」。ほかの端末は `git pull` の後に `./install.sh`（Windows は `windows/install.ps1`）で入る（pull だけでは入らない）。

| 何 | 固定する場所 | 上げ方（リポジトリのルートで） |
| -- | -- | -- |
| mise の道具 | `config/mise/mise.lock`（版・URL・checksum。linux-x64・linux-arm64・macos-arm64・windows-x64） | `MISE_CONFIG_DIR="$PWD/config/mise" mise lock --global --bump --platform linux-x64,linux-arm64,macos-arm64,windows-x64`。`latest`・`lts` を今の版に進める（公開 24 時間未満は選ばない）。版を書いた道具（tinymemory・shellcheck）は先に `config/mise/config.toml` の版を直す |
| mise 本体 | `install.sh` の `MISE_VERSION` と `windows/install.ps1` の `$MiseVersion`（同じ版） | 2 つを直し、この端末で `mise self-update --yes <版>` の後に上の lock のコマンド（Node の `lts` が指す版は mise の版で決まる）。install が入っている mise をその版にする |
| Neovim のプラグイン | `config/nvim/lazy-lock.json` | nvim で `:Lazy update`（`~/.config/nvim` のリンク先の lazy-lock.json が変わる）→ `sh tests/nvim.sh` |
| zsh のプラグイン | `install.sh` の `zsh-users/<名前>@<SHA>` | 新しいコミット（`git ls-remote https://github.com/zsh-users/<名前> HEAD`）に直す |

- 版を進めずに lock だけ作り直す（道具を足す・消す、`os` を変える）: 上のコマンドから `--bump` を外す
- Windows の PowerShell で作り直すとき: `$env:MISE_CONFIG_DIR = "$PWD\config\mise"; mise lock --global --bump --platform linux-x64,linux-arm64,macos-arm64,windows-x64; Remove-Item env:MISE_CONFIG_DIR`
- `MISE_CONFIG_DIR` を付けないと、本物の `~/.config/mise/mise.lock` を作ってしまう
- `mise upgrade`・`mise use -g` は使わない（写しの lock だけが変わり、次の install で lock の版に戻る）
- lock の対象外の例外は mac の eza だけ。eza は mac の配布物を出しておらず、固定できる配布元が無い。Brewfile で入れ、Homebrew が bottle の checksum を確かめ、版は Homebrew が決める
- lock の 4 つ以外の端末（Intel の mac・musl の Linux など）は install が止まる。`--platform` に足して作り直す

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
