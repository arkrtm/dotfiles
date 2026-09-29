#!/bin/sh
# dotfiles セットアップ（mac / linux 共通、sudo 不要、何度実行しても安全）
set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# リンク定義: <リポジトリ内パス> <$HOME からの配置先>
LINKS="
shell/bashrc             .bashrc
shell/bash_profile       .bash_profile
config/mise/config.toml  .config/mise/config.toml
config/starship.toml     .config/starship.toml
config/bat/config        .config/bat/config
config/git/config        .config/git/config
config/tmux/tmux.conf    .config/tmux/tmux.conf
config/ghostty/config    .config/ghostty/config
config/claude/settings.json  .claude/settings.json
bin/agent-status         .local/bin/agent-status
ssh/config               .ssh/config
"

link() {
  src="$DOTFILES/$1"
  dst="$HOME/$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "backup: $dst -> $bak"
  fi
  ln -s "$src" "$dst"
  echo "link:   $dst -> $src"
}

echo "$LINKS" | while read -r src dst; do
  if [ -n "$src" ]; then link "$src" "$dst"; fi
done

# ssh は設定ファイルが他ユーザー書き込み可だと拒否するため権限を絞る
chmod 700 "$HOME/.ssh"
chmod 600 "$DOTFILES/ssh/config"

# git config --global の書き込み先を端末ローカルの ~/.gitconfig にする
# （存在しないと ~/.config/git/config = リポジトリ側が書き換わる）
touch "$HOME/.gitconfig"

# mise 本体（~/.local/bin/mise）
MISE="$HOME/.local/bin/mise"
if [ ! -x "$MISE" ]; then
  curl -fsSL https://mise.run | sh
fi
"$MISE" install --yes

# mac: GUI アプリ等は Homebrew（Brewfile）
if [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
  brew bundle --file="$DOTFILES/Brewfile"
fi

echo "done."
