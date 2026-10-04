#!/bin/sh
# 静的な検査（ネットワーク無し・数秒）: #!/bin/sh のファイルの構文（dash があれば dash）、zsh・bash の起動ファイルの構文、
# tmux.conf の読み込み、ssh/config の構文、SKILL.md の frontmatter、settings.json（JSON として読める、hooks の event 名が既知、
# hooks が呼ぶ ~/.local/bin/<名前> が install.sh の LINKS にある）、mise の config.toml が読める、受け入れ検査が使う jq が mise にある、
# mac では plist
#   sh tests/static.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

# ---- 構文: #!/bin/sh のファイルは dash（Debian の /bin/sh。無ければ sh）、zsh・bash の起動ファイルはそれぞれのシェル
SH="$(command -v dash || echo sh)"
for f in $(git -C "$ROOT" ls-files); do
  [ -f "$ROOT/$f" ] || continue
  case "$(head -n 1 "$ROOT/$f")" in '#!/bin/sh'*) ;; *) continue ;; esac
  "$SH" -n "$ROOT/$f" 2>/dev/null && ok "構文（$(basename "$SH") -n）: $f" || ng "構文エラー: $f"
done
if command -v zsh >/dev/null 2>&1; then
  for f in shell/zshenv shell/zprofile shell/zshrc; do
    [ -f "$ROOT/$f" ] || continue
    zsh -n "$ROOT/$f" 2>/dev/null && ok "構文（zsh -n）: $f" || ng "構文エラー: $f"
  done
fi
for f in shell/bashrc shell/bash_profile; do
  bash -n "$ROOT/$f" 2>/dev/null && ok "構文（bash -n）: $f" || ng "構文エラー: $f"
done

# ---- tmux.conf: 私設のサーバで読み込める（new-session は壊れた conf でも 0 を返すので source-file で見る）。
#      prefix r の再読込は、追記する terminal-features を既定に戻してから読み直す（戻さないと再読込のたびに増える）
if command -v tmux >/dev/null 2>&1; then
  S="dotfiles-static-$$"
  if tmux -L "$S" -f "$ROOT/config/tmux/tmux.conf" new-session -d -x 80 -y 24 2>/dev/null; then
    tmux -L "$S" source-file "$ROOT/config/tmux/tmux.conf" 2>/dev/null && ok "tmux.conf が読み込める" || ng "tmux.conf にエラーがある"
    r="$(tmux -L "$S" list-keys -T prefix 2>/dev/null | grep -E '^bind-key +-T prefix +r ' || true)"
    case "$r" in *'set-option -su terminal-features'*) ok "prefix r は terminal-features を戻してから読み直す" ;; *) ng "prefix r が terminal-features を戻さない: $r" ;; esac
    tmux -L "$S" kill-server 2>/dev/null || true
  else
    ng "tmux.conf でサーバを起こせない"
  fi
fi

# ---- ssh/config: 構文（Match の exec を走らせないホスト名で評価する）
ssh -G -F "$ROOT/ssh/config" example.invalid >/dev/null 2>&1 && ok "ssh/config が読める" || ng "ssh/config にエラーがある"
grep -q '^Include config.local$' "$ROOT/ssh/config" && ok "ssh/config は端末固有の Host を ~/.ssh/config.local から読む" || ng "ssh/config に Include config.local が無い"

# ---- Claude Code の skill: frontmatter（---、name がディレクトリ名、description）
for f in "$ROOT"/config/claude/skills/*/SKILL.md; do
  n="$(basename "$(dirname "$f")")"
  if [ "$(sed -n 1p "$f")" = "---" ] && sed -n '2,/^---$/p' "$f" | grep -q "^name: $n\$" && sed -n '2,/^---$/p' "$f" | grep -q '^description: .'; then
    ok "skill の frontmatter: $n"
  else ng "skill の frontmatter（---、name: $n、description）: $f"; fi
done

# ---- settings.json: JSON として読める、hooks の event 名が既知、hooks が呼ぶ ~/.local/bin/<名前> が LINKS にある
S="$ROOT/config/claude/settings.json"
command -v jq >/dev/null 2>&1 || { echo "FAIL jq が無い（mise で入る）"; exit 1; }
jq -e . "$S" >/dev/null 2>&1 && ok "settings.json は JSON として読める" || ng "settings.json が JSON として読めない"
# 既知の event 名（https://code.claude.com/docs/en/hooks の一覧、2026-10）。足りなければここに足す（未知の名前は Claude Code が警告して無視する）
KNOWN=" SessionStart Setup UserPromptSubmit UserPromptExpansion PreToolUse PermissionRequest PostToolUse PostToolUseFailure PostToolBatch Notification MessageDisplay SubagentStart SubagentStop TaskCreated TaskCompleted Stop StopFailure TeammateIdle InstructionsLoaded ConfigChange CwdChanged DirectoryAdded FileChanged WorktreeCreate WorktreeRemove PreCompact PostCompact PreModelSwitch PostModelSwitch Elicitation ElicitationResult SessionEnd PermissionDenied "
bad=0
for e in $(jq -r '.hooks | keys[]' "$S" 2>/dev/null); do
  case "$KNOWN" in *" $e "*) ;; *) ng "settings.json の hooks に未知の event 名: $e"; bad=1 ;; esac
done
[ "$bad" = 0 ] && ok "settings.json の hooks の event 名はすべて既知"
for b in $(jq -r '.hooks[][].hooks[].command' "$S" 2>/dev/null | grep -o '\.local/bin/[A-Za-z0-9_-]\{1,\}' | sed 's|\.local/bin/||' | sort -u); do
  grep -q "^bin/$b  *\.local/bin/$b\$" "$ROOT/install.sh" && ok "hooks が呼ぶ $b は install.sh の LINKS にある" || ng "hooks が呼ぶ ~/.local/bin/$b が install.sh の LINKS に無い"
done

# ---- mise: config.toml が読める。受け入れ検査が使う jq を mise が入れる（Ubuntu / WSL には既定で無い）
if command -v mise >/dev/null 2>&1; then
  MISE_GLOBAL_CONFIG_FILE="$ROOT/config/mise/config.toml" mise config ls >/dev/null 2>&1 && ok "mise の config.toml が読める" || ng "mise の config.toml が読めない"
fi
grep -q '^jq = ' "$ROOT/config/mise/config.toml" && ok "jq は mise で入る（tests/acceptance が使う）" || ng "config/mise/config.toml に jq が無い"

# ---- mac: launchd の plist
if command -v plutil >/dev/null 2>&1; then
  plutil -lint -s "$ROOT"/mac/*.plist && ok "mac の plist が読める" || ng "mac の plist にエラーがある"
fi

exit "$fail"
