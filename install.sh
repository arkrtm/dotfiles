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
config/git/hooks         .config/git/hooks
config/tmux/tmux.conf    .config/tmux/tmux.conf
config/ghostty/config    .config/ghostty/config
config/claude/settings.json  .claude/settings.json
config/claude/CLAUDE.md  .claude/CLAUDE.md
config/claude/agents/reviewer.md  .claude/agents/reviewer.md
config/claude/agents/implementer.md  .claude/agents/implementer.md
config/claude/agents/acceptor.md  .claude/agents/acceptor.md
config/claude/skills/verify  .claude/skills/verify
config/claude/skills/review  .claude/skills/review
config/claude/skills/issue   .claude/skills/issue
config/claude/skills/wrap-up .claude/skills/wrap-up
config/claude/skills/implement .claude/skills/implement
config/claude/skills/diagnose  .claude/skills/diagnose
config/claude/skills/accept    .claude/skills/accept
bin/harness-hook         .local/bin/harness-hook
config/ss-sync           .config/ss-sync
bin/ss-sync              .local/bin/ss-sync
bin/lan-reachable        .local/bin/lan-reachable
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

# リンク配置だけを検査したい時（tests/install.sh）はここで終わる
[ -n "${DOTFILES_LINKS_ONLY:-}" ] && exit 0

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
# zsh が無ければ静的ビルド（zsh-bin）を ~/.local に入れる（/etc/shells は触らない。chsh できない時は bash_profile が exec zsh）
if ! command -v zsh >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/zsh" ]; then
  # インストーラーはコミットを固定して取得する（中の sha256 で配布物を検証するので、スクリプト自体の改ざんを防ぐ）。取得失敗は set -e で止める
  zsh_bin_install="$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/0c5d2f31679a6bd9a639c1d0b027feed7c271625/install)"
  sh -c "$zsh_bin_install" -- -q -d "$HOME/.local" -e no -a sha256
fi

# mise 本体（~/.local/bin/mise）
# ここから先の mise・fnm・uv は、呼んだ場所の設定（mise.toml、.python-version など）に左右されないよう $HOME で実行する
cd "$HOME"
MISE="$HOME/.local/bin/mise"
if [ ! -x "$MISE" ]; then
  curl -fsSL https://mise.run | sh
fi
"$MISE" install --yes

# Node は fnm で最新の LTS を入れて既定にする。再実行のたびに最新の LTS を入れて default を付け直すので追随する
# ponytail: 古い版は残る（容量が気になったら fnm uninstall <版>）。FNM_DIR は shell/zshenv・bashrc と同じ場所
export FNM_DIR="$HOME/.local/share/fnm"
"$MISE" exec -- fnm install --lts
"$MISE" exec -- fnm default lts-latest

# harness-hook は ~/.local/libexec/uv を直接使う（mise の shim は cwd の mise 設定で壊れうるため）。uv の実体
# （global 設定の latest 経由なので mise の更新に追随）をリンクする。PATH には入れない（日常の uv はプロジェクトの版の固定に従わせる）
mkdir -p "$HOME/.local/libexec"
ln -sfn "$("$MISE" which uv)" "$HOME/.local/libexec/uv"
# Python が無い端末では初回の hook 実行（timeout 15 秒）で
# ダウンロードが走らないよう、ここで入れておく（>=3.9 は bin/harness-hook の requires-python と同じ）。
# Python は uv 経由で実行する方針なので、~/.local/bin に python 実行ファイルは置かない（--no-bin）
"$MISE" exec -- uv python find '>=3.9' >/dev/null 2>&1 || "$MISE" exec -- uv python install --no-bin '>=3.9'

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
