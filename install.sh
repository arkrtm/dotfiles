#!/bin/sh
# dotfiles セットアップ（mac / linux 共通、sudo 不要、何度実行しても安全）
set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# リンク定義: <リポジトリ内パス> <$HOME からの配置先>
LINKS="
shell/zshenv             .zshenv
shell/zshrc              .zshrc
shell/bashrc             .bashrc
shell/bash_profile       .bash_profile
config/mise/config.toml  .config/mise/config.toml
config/starship.toml     .config/starship.toml
config/bat/config        .config/bat/config
config/git/config        .config/git/config
config/tmux/tmux.conf    .config/tmux/tmux.conf
config/ghostty/config    .config/ghostty/config
config/claude/settings.json  .claude/settings.json
config/claude/CLAUDE.md  .claude/CLAUDE.md
config/ss-sync           .config/ss-sync
bin/ss-sync              .local/bin/ss-sync
config/nvim              .config/nvim
config/yazi              .config/yazi
bin/agent-status         .local/bin/agent-status
bin/geoview              .local/bin/geoview
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

# zsh プラグイン（プラグインマネージャは使わず clone のみ。再実行で更新）
ZPLUGINS="$HOME/.local/share/zsh/plugins"
mkdir -p "$ZPLUGINS"
for repo in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
  dir="$ZPLUGINS/${repo#*/}"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull -q --ff-only
  else
    git clone -q --depth 1 "https://github.com/$repo.git" "$dir"
  fi
done
if ! command -v zsh >/dev/null 2>&1; then
  echo "warning: zsh が見つかりません（linux: sudo apt install zsh）。bash 設定で動作します"
fi

# mise 本体（~/.local/bin/mise）
MISE="$HOME/.local/bin/mise"
if [ ! -x "$MISE" ]; then
  curl -fsSL https://mise.run | sh
fi
"$MISE" install --yes

# tinymemory の hook は PATH + ~/.local/bin + ~/.cargo/bin しか探さない（hook 文字列は Codex の
# 信頼ハッシュに固定されていて変更不可）。PATH が最小でも見つかるよう ~/.local/bin に shim を置く
ln -sfn "$HOME/.local/share/mise/shims/tinymemory" "$HOME/.local/bin/tinymemory"

# Neovim プラグインを lazy-lock.json のバージョンに揃える（端末間の差分を防ぐ）
NVIM="$("$MISE" which nvim 2>/dev/null || true)"
if [ -n "$NVIM" ]; then
  "$NVIM" --headless "+Lazy! restore" +qa >/dev/null 2>&1 || echo "warning: nvim プラグインの restore に失敗"
fi

# mac 専用（Homebrew、スクリーンショット設定、launchd）
if [ "$(uname -s)" = Darwin ]; then
  "$DOTFILES/mac/setup.sh"
fi

echo "done."
