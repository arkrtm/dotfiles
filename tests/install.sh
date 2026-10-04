#!/bin/sh
# install.sh の検査: 空の HOME に対して実行し、(1) LINKS 表の全項目がリンクされること、(2) 既存ファイルが
# 退避されること、(3) Claude Code の skill は issue と wrap-up だけを置き（ほかの skill には触らない）、
# git の共通 hooks の設定と旧来のハーネスのものを置かないこと（ARK-67）、(4) 再実行しても同じ結果になること
#   sh tests/install.sh
set -eu
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
# 安全装置: install.sh がリンクだけで止まる早期終了（DOTFILES_LINKS_ONLY）が無いと、一時 HOME に対してフル install が走る
# （mac では defaults write と launchd の登録も）
grep -qF 'DOTFILES_LINKS_ONLY' "$DOTFILES/install.sh" || { echo "FAIL install.sh に DOTFILES_LINKS_ONLY の早期終了が無い"; exit 1; }
fail=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

# 既存ファイル（ぶら下がりのリンクも）がある状態で実行 → 退避されてリンクに置き換わる。ほかの skill は残る
mkdir -p "$HOME/.config/tmux" "$HOME/.claude/skills/other"; echo old > "$HOME/.config/tmux/tmux.conf"
ln -s /nonexistent "$HOME/.zshrc"
echo other > "$HOME/.claude/skills/other/SKILL.md"
out1="$(DOTFILES_LINKS_ONLY=1 sh "$DOTFILES/install.sh")"
case "$out1" in *done.*) ng "install.sh がリンクだけで止まらなかった（DOTFILES_LINKS_ONLY）" ;; *) ok "install.sh はリンクだけで止まる（DOTFILES_LINKS_ONLY）" ;; esac

# LINKS 表の全項目がリンクされているか（install.sh から表を読み取る）
[ "$(sed -n '/^LINKS="/,/^"/p' "$DOTFILES/install.sh" | grep -cvE '^(LINKS="|")$')" -gt 10 ] && ok "LINKS 表を読み取れている" || ng "LINKS 表を読み取れない（以降の 2 件は無意味）"
sed -n '/^LINKS="/,/^"/p' "$DOTFILES/install.sh" | grep -vE '^(LINKS="|")$' | while read -r src dst; do
  [ -n "$src" ] || continue
  if [ -L "$HOME/$dst" ] && [ "$(readlink "$HOME/$dst")" = "$DOTFILES/$src" ]; then :; else echo "MISSING $dst"; fi
done | grep MISSING && ng "リンクされていない項目がある" || ok "LINKS 表の全項目がリンクされている"

[ "$(cat "$HOME/.config/tmux/"tmux.conf.bak.* 2>/dev/null)" = old ] && ok "既存ファイルは *.bak.<日時> に中身ごと退避される" || ng "既存ファイルが退避されていない"
[ -L "$HOME"/.zshrc.bak.* ] && ok "既存のシンボリックリンク（ぶら下がりでも）も退避される" || ng "既存のリンクが退避されていない"

# 各リンク元が実在するか（表の書き間違いを検出）
sed -n '/^LINKS="/,/^"/p' "$DOTFILES/install.sh" | grep -vE '^(LINKS="|")$' | while read -r src dst; do
  [ -n "$src" ] && [ ! -e "$DOTFILES/$src" ] && echo "NOSRC $src"
done | grep NOSRC && ng "リンク元が存在しない項目がある" || ok "全リンク元が存在する"

# Claude Code の skill: issue と wrap-up を置き、ほかの skill はそのまま残す。本文は harness・関門に触れない
[ "$(ls "$HOME/.claude/skills" | tr '\n' ' ')" = "issue other wrap-up " ] && [ "$(cat "$HOME/.claude/skills/other/SKILL.md")" = other ] \
  && ok "skill は issue と wrap-up を置き、ほかの skill には触らない" || ng "skill の置き方: $(ls "$HOME/.claude/skills" | tr '\n' ' ')"
grep -qx 'name: issue' "$HOME/.claude/skills/issue/SKILL.md" && grep -qx 'name: wrap-up' "$HOME/.claude/skills/wrap-up/SKILL.md" \
  && ok "skill の issue と wrap-up が読める" || ng "skill の issue・wrap-up の SKILL.md が無い"

# 旧来のハーネスのものを置かない。git の設定は共通 hooks の場所を指さない（各リポジトリの .git/hooks がそのまま効く）
for p in .local/bin/harness-hook .local/libexec/uv .config/git/hooks .claude/agents; do
  if [ -e "$HOME/$p" ] || [ -L "$HOME/$p" ]; then echo "STALE $p"; fi
done | grep STALE && ng "ハーネスのものが置かれている" || ok "ハーネスのもの（harness-hook・uv のリンク・git hooks・agents）を置かない"
[ -z "$(git config --file "$HOME/.config/git/config" --get core.hooksPath || true)" ] \
  && ok "git の設定は共通 hooks の場所を指さない" || ng "git の設定に共通 hooks の場所が残っている"

# 再実行しても何も起きない（べき等）: 2 回目の出力に link: / backup: が無い
out=$(DOTFILES_LINKS_ONLY=1 sh "$DOTFILES/install.sh")
case "$out" in *link:*|*backup:*) ng "再実行でリンクや退避が発生した: $out" ;; *) ok "再実行しても何も起きない（べき等）" ;; esac

exit $fail
