#!/bin/sh
# install.sh の検査: 空の HOME に対して実行し、(1) LINKS 表の全項目がリンクされること、(2) 既存ファイルが
# 退避されること、(3) 配置した git 設定とこの端末に入れたプラグイン harness でコミットの関門が効くこと、
# (4) 再実行しても同じ結果になること、(5) ハーネスの旧来のリンクを置かないこと
#   sh tests/install.sh   （プラグイン harness を入れた端末で）
set -eu
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
# プラグインの harness-hook は $HOME/.local/libexec/uv で動く。空の HOME では mise の shim が使えないので、先に uv の実体を控える
UV="$HOME/.local/libexec/uv"; [ -x "$UV" ] || UV="$(mise which uv 2>/dev/null || true)"
[ -x "$UV" ] || { echo "FAIL uv の実体が見つからない（dotfiles の install.sh を実行すること）"; exit 1; }
# この端末に入れたプラグイン harness の場所（Claude Code が installed_plugins.json に記録する）も、空の HOME に替える前に控える
PLUGIN="$(jq -r '.plugins["harness@harness"][0].installPath // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null || true)"
[ -x "$PLUGIN/bin/harness-hook" ] || { echo "FAIL プラグイン harness が入っていない（claude plugin install harness@harness）"; exit 1; }
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}" # uv 管理の Python も元の HOME のものを使う（毎回ダウンロードしない）
export HOME="$(mktemp -d)"
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM CLAUDECODE 2>/dev/null || true
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.local/libexec"; ln -s "$UV" "$HOME/.local/libexec/uv"
fail=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

# 既存ファイルがある状態で実行 → 退避されてリンクに置き換わる
mkdir -p "$HOME/.config/tmux"; echo old > "$HOME/.config/tmux/tmux.conf"
DOTFILES_LINKS_ONLY=1 sh "$DOTFILES/install.sh" >/dev/null

# LINKS 表の全項目がリンクされているか（install.sh から表を読み取る）
[ "$(sed -n '/^LINKS="/,/^"/p' "$DOTFILES/install.sh" | grep -cvE '^(LINKS="|")$')" -gt 10 ] && ok "LINKS 表を読み取れている" || ng "LINKS 表を読み取れない（以降の 2 件は無意味）"
sed -n '/^LINKS="/,/^"/p' "$DOTFILES/install.sh" | grep -vE '^(LINKS="|")$' | while read -r src dst; do
  [ -n "$src" ] || continue
  if [ -L "$HOME/$dst" ] && [ "$(readlink "$HOME/$dst")" = "$DOTFILES/$src" ]; then :; else echo "MISSING $dst"; fi
done | grep MISSING && ng "リンクされていない項目がある" || ok "LINKS 表の全項目がリンクされている"

ls "$HOME/.config/tmux/"tmux.conf.bak.* >/dev/null 2>&1 && ok "既存ファイルは *.bak.<日時> に退避される" || ng "既存ファイルが退避されていない"

# 各リンク元が実在するか（表の書き間違いを検出）
sed -n '/^LINKS="/,/^"/p' "$DOTFILES/install.sh" | grep -vE '^(LINKS="|")$' | while read -r src dst; do
  [ -n "$src" ] && [ ! -e "$DOTFILES/$src" ] && echo "NOSRC $src"
done | grep NOSRC && ng "リンク元が存在しない項目がある" || ok "全リンク元が存在する"

# ハーネスはプラグインから入る。dotfiles の旧来のハーネスのリンクは置かない（プラグインと二重にしない）
for p in .local/bin/harness-hook .config/git/hooks .claude/skills .claude/agents; do
  if [ -e "$HOME/$p" ] || [ -L "$HOME/$p" ]; then echo "STALE $p"; fi
done | grep STALE && ng "ハーネスの旧来のリンクがある" || ok "ハーネスの旧来のリンク（harness-hook・git hooks・skills・agents）を置かない"

# 配置した git 設定（~/.config/git/config の core.hooksPath = プラグインの data の git-hooks）経由で、コミットの関門が実際に効く。
# data の git-hooks はプラグインの SessionStart が置く。ここでは入れたプラグインの session-start を、空の HOME の data に向けて動かす
export XDG_STATE_HOME="$HOME/.state"
out="$(CLAUDE_PLUGIN_DATA="$HOME/.claude/plugins/data/harness-harness" "$PLUGIN/bin/harness-hook" session-start </dev/null)"
case "$out" in
  *systemMessage*) ng "git 設定の core.hooksPath が、プラグインが置く data の git-hooks を指していない: $out" ;;
  *additionalContext*) ok "git 設定の core.hooksPath が、プラグインが置く data の git-hooks を指す（SessionStart が警告を出さない）" ;;
  *) ng "プラグインの session-start が動かない: $out" ;;
esac
R="$HOME/repo"; mkdir -p "$R"; g="git -C $R -c user.name=t -c user.email=t@t"
$g init -q -b main; $g commit -q --allow-empty -m init; $g switch -q -c feat/x
# Claude Code のセッションがこのリポジトリで始まった状態にする（turn hook が対象に登録する）
printf '{"session_id":"t","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$R" | "$PLUGIN/bin/harness-hook" turn
echo doc > "$R/README.md"; $g add -A
if CLAUDECODE=1 $g commit -q -m docs 2>/dev/null; then ok "インストール後: ドキュメントだけのコミットは通る"; else ng "ドキュメントのコミットが止められた"; fi
echo code > "$R/app.py"; $g add -A
if CLAUDECODE=1 $g commit -q -m code 2>/dev/null; then ng "インストール後: 証拠なしのコード変更がコミットできてしまった"; else ok "インストール後: Claude Code からの、証拠なしのコード変更のコミットは止まる"; fi
if $g commit -q -m code 2>/dev/null; then ok "インストール後: 人の手動コミットは止めない"; else ng "人の手動コミットが止められた"; fi

# 再実行しても何も起きない（べき等）: 2 回目の出力に link: / backup: が無い
out=$(DOTFILES_LINKS_ONLY=1 sh "$DOTFILES/install.sh")
case "$out" in *link:*|*backup:*) ng "再実行でリンクや退避が発生した: $out" ;; *) ok "再実行しても何も起きない（べき等）" ;; esac

exit $fail
