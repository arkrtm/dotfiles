#!/bin/sh
# mac 専用の設定（install.sh から呼ばれる。何度実行しても安全）
set -eu
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"

# Homebrew（GUI アプリ等）
if command -v brew >/dev/null 2>&1; then
  brew bundle --file="$DOTFILES/Brewfile" || echo "warning: brew bundle に失敗（以降の設定は続行）"
else
  echo "Homebrew が無いので Brewfile（ghostty）は省略"
fi

# スクリーンショット: ~/Screenshots に保存、撮影後のサムネイル（保存が約 5 秒遅れる）を無効化
mkdir -p "$HOME/Screenshots"
if [ "$(defaults read com.apple.screencapture location 2>/dev/null)" != "$HOME/Screenshots" ] ||
  [ "$(defaults read com.apple.screencapture show-thumbnail 2>/dev/null)" != 0 ]; then
  defaults write com.apple.screencapture location "$HOME/Screenshots"
  defaults write com.apple.screencapture show-thumbnail -bool false
  killall SystemUIServer 2>/dev/null || true
  echo "screencapture: ~/Screenshots, サムネイル無効"
fi

# スクリーンショット自動送信（launchd）
label=com.arkrithm.ss-sync
plist="$HOME/Library/LaunchAgents/$label.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/state/ss-sync"
new=$(sed "s|@HOME@|$HOME|g" "$DOTFILES/mac/$label.plist")
if [ ! -f "$plist" ] || [ "$new" != "$(cat "$plist")" ]; then
  printf '%s\n' "$new" >"$plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  # GUI セッションが無い時（ssh 越しなど）は登録できない。plist は置いたので次回ログインで launchd が読む
  launchctl bootstrap "gui/$(id -u)" "$plist" && echo "launchd: $label を登録" || echo "warning: launchd の登録に失敗（次回ログインで有効になる）"
fi
