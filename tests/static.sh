#!/bin/sh
# 静的な検査（ネットワーク無し・数秒）: #!/bin/sh のファイルの構文（dash があれば dash）、#!/usr/bin/env bash のファイルの構文、zsh・bash の起動ファイルの構文、
# tmux.conf の読み込み、ssh/config の構文、SKILL.md の frontmatter、settings.json（JSON として読める、hooks の event 名が既知、
# hooks が呼ぶ ~/.local/bin/<名前> が install.sh の LINKS にある）、mise の config.toml が読める、受け入れ検査が使う jq が mise にある、herdr の config.toml にエラーが無い、一時ファイルを作る検査の trap の形、追跡するファイルに Linear の issue 番号が無い
#   sh tests/static.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

# ---- 構文: #!/bin/sh のファイルは dash（Debian の /bin/sh。無ければ sh）、#!/usr/bin/env bash のファイルと zsh・bash の起動ファイルはそれぞれのシェル
SH="$(command -v dash || echo sh)"
for f in $(git -C "$ROOT" ls-files); do
  [ -f "$ROOT/$f" ] || continue
  case "$(head -n 1 "$ROOT/$f")" in '#!/bin/sh'*) ;; *) continue ;; esac
  "$SH" -n "$ROOT/$f" 2>/dev/null && ok "構文（$(basename "$SH") -n）: $f" || ng "構文エラー: $f"
done
for f in $(git -C "$ROOT" ls-files); do
  [ -f "$ROOT/$f" ] || continue
  case "$(head -n 1 "$ROOT/$f")" in '#!/usr/bin/env bash'*) ;; *) continue ;; esac
  bash -n "$ROOT/$f" 2>/dev/null && ok "構文（bash -n）: $f" || ng "構文エラー: $f"
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
  # ソケットは一時ディレクトリに置き、どの終わり方でもサーバを止めて消す（tmux は終了時にソケットを消さない。trap の中も set -e が効くので
  # kill-server の失敗は握る）。S は後で settings.json に使い回すので、trap は $T から組む
  T=""
  trap 'trap "" HUP INT TERM; [ -z "$T" ] || { tmux -S "$T/sock" kill-server 2>/dev/null || true; rm -rf "$T"; }' EXIT
  trap 'exit 1' HUP INT TERM
  T="$(trap '' HUP INT TERM; mktemp -d /tmp/static-$$.XXXXXX)"; S="$T/sock" # TMPDIR の下に重ねない（ソケットのパスが 104 バイトを超えないように短い /tmp に。pid で名前を絞る）
  if tmux -S "$S" -f "$ROOT/config/tmux/tmux.conf" new-session -d -x 80 -y 24 2>/dev/null; then
    n0="$(tmux -S "$S" show -s -v terminal-features 2>/dev/null | wc -l | tr -d ' ')" # 起動直後の要素数（この後の source-file より前に取る）
    tmux -S "$S" source-file "$ROOT/config/tmux/tmux.conf" 2>/dev/null && ok "tmux.conf が読み込める" || ng "tmux.conf にエラーがある"
    r="$(tmux -S "$S" list-keys -T prefix 2>/dev/null | grep -E '^bind-key +-T prefix +r ' || true)"
    case "$r" in *'set-option -su terminal-features'*) ok "prefix r は terminal-features を戻してから読み直す" ;; *) ng "prefix r が terminal-features を戻さない: $r" ;; esac
    # bind の中身を実際に実行して、terminal-features が起動直後の数に戻ることを見る（文字列でなく振る舞い）。list-keys の行からコマンド部分を取り、
    # \; は eval で tmux の区切りに、conf のパス（tmux が ~ を $HOME に展開済み）はリポジトリのファイルに置き換えて、リンクの有無に依らず同じものを読む。
    # 末尾の display-message はクライアントが無く失敗してよい
    cmd="$(printf '%s\n' "$r" | sed -e 's/^bind-key *-T prefix *r *//' -e "s|$HOME/.config/tmux/tmux.conf|$ROOT/config/tmux/tmux.conf|")"
    eval "tmux -S \"\$S\" $cmd" >/dev/null 2>&1 || true
    n1="$(tmux -S "$S" show -s -v terminal-features 2>/dev/null | wc -l | tr -d ' ')"
    [ -n "$cmd" ] && [ "$n1" = "$n0" ] && ok "prefix r を実行しても terminal-features が増えない（$n0 → $n1）" || ng "prefix r で terminal-features が $n0 → $n1 になる"
  else
    ng "tmux.conf でサーバを起こせない"
  fi
fi

# ---- ssh/config: 構文
ssh -G -F "$ROOT/ssh/config" example.invalid >/dev/null 2>&1 && ok "ssh/config が読める" || ng "ssh/config か ~/.ssh/config.local（Include で読む）にエラーがある"
grep -q '^Include config.local$' "$ROOT/ssh/config" && ok "ssh/config は端末固有の Host を ~/.ssh/config.local から読む" || ng "ssh/config に Include config.local が無い"

# ---- wezterm.lua: Lua の構文（luac が無い端末では省く）
if command -v luac >/dev/null 2>&1; then
  luac -p "$ROOT/config/wezterm/wezterm.lua" && ok "wezterm.lua の構文" || ng "wezterm.lua の構文"
fi

# ---- Claude Code の skill: frontmatter（---、name がディレクトリ名、description）
for f in "$ROOT"/config/agents/skills/*/SKILL.md; do
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

# ---- herdr: config.toml にエラーが無い（無効なキー・未知の項目・構文。同じキーへの二重の割り当ては見ない）
if command -v herdr >/dev/null 2>&1; then
  r="$(HERDR_CONFIG_PATH="$ROOT/config/herdr/config.toml" herdr config check 2>&1)" && ok "herdr の config.toml にエラーが無い" || ng "herdr の config.toml にエラーがある: $r"
fi

# ---- 検査の後片づけ: 一時ファイルを作る検査は、作る前に 2 つの trap を置く。後片づけの trap は始めに信号を無視して最後まで走り、
#      もう 1 つは信号を exit に変える（dash は信号で終わると EXIT の trap を実行しない。後片づけの最中の信号で打ち切られないように）。
#      作るのは $(trap '' HUP INT TERM; mktemp …) の形だけで、信号で止めずに名前を返させる（作った後・名前を返す前に止まると、消す先が分からない）。
#      mktemp を含む行（コメントを除く）は、書き方に依らずすべて拾い、この形でなければ落とす
for f in $(git -C "$ROOT" ls-files 'tests/*.sh'); do
  c="$(grep -nw 'mk[t]emp' "$ROOT/$f" | grep -v '^[0-9]*: *#' || true)"; [ -n "$c" ] || continue
  m="$(printf '%s\n' "$c" | head -n 1 | cut -d: -f1)"
  # 1 行に mktemp が複数あるときも、すべてがこの形であること（mktemp の数と、この形の数が同じ行だけ通す）
  bad="$(printf '%s\n' "$c" | awk -F: '{ n = $1; l = $0; sub(/^[0-9]+:/, "", l); g = l; a = gsub(/mk[t]emp/, "", l)
    b = gsub("[$][(]trap \047\047 HUP INT TERM; mk[t]emp", "", g); if (a != b) printf "%s ", n }' | sed 's/ $//')"
  e="$(grep -nE "(^ *|; *)trap 'trap \"\" HUP INT TERM; [^']*' EXIT" "$ROOT/$f" | head -n 1 | cut -d: -f1)"
  s="$(grep -nE "(^ *|; *)trap 'exit 1' HUP INT TERM" "$ROOT/$f" | head -n 1 | cut -d: -f1)"
  if [ -z "$bad" ] && [ -n "$e" ] && [ -n "$s" ] && [ "$e" -lt "$m" ] && [ "$s" -lt "$m" ]; then ok "止めても後片づけする: $f"
  else ng "trap 'trap \"\" HUP INT TERM; <後片づけ>' EXIT と trap 'exit 1' HUP INT TERM を置いてから、\$(trap '' HUP INT TERM; mktemp …) で作る: $f${bad:+（形の違う行: $bad）}"; fi
done

# ---- Linear の issue 番号: 追跡するファイルに書かない（パターンの [ ] は、この行自身に当たらないため。-I は付けない: binary 扱いのファイルも見る）
rc=0; hits="$(git -C "$ROOT" grep -nE 'AR[K]-[0-9]')" || rc=$? # 1 = 一致なし、0 = 番号がある、ほかは実行の失敗
case "$rc" in
  1) ok "追跡するファイルに Linear の issue 番号が無い" ;;
  0) ng "追跡するファイルに Linear の issue 番号がある（番号でなく理由の文を書く）:
$hits" ;;
  *) ng "issue 番号の検査の git grep が失敗した（rc=$rc）" ;;
esac

exit "$fail"
