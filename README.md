# dotfiles

mac / linux 共通の設定。sudo 不要。

## セットアップ

```sh
git clone https://github.com/arkrtm/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

- 設定ファイルは `$HOME` 側にシンボリックリンクで配置される。どの端末で編集してもこのリポジトリが変わるので、commit / push → 他端末で `git pull` で反映
- CLI ツールは [mise](https://mise.jdx.dev) で `~/.local` 以下に入る（`config/mise/config.toml`）
- 既存ファイルは `*.bak.<日時>` に退避される

## 構成

| リポジトリ | 配置先 |
|---|---|
| `config/mise/config.toml` | `~/.config/mise/config.toml` |
| `config/starship.toml` | `~/.config/starship.toml` |
| `config/bat/config` | `~/.config/bat/config` |
| `config/git/config` | `~/.config/git/config` |
| `ssh/config` | `~/.ssh/config` |

端末固有の git 設定（credential helper 等）は `~/.gitconfig` に書く（リポジトリ外）。
