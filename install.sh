#!/bin/sh
# dotfiles セットアップ（mac / linux 共通、sudo 不要、何度実行しても安全）
set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
# worktree（.git がファイル）から実行すると、リンクが worktree を指し、worktree を消すと設定が読めなくなる
if [ -f "$DOTFILES/.git" ] && [ -z "${DOTFILES_ALLOW_WORKTREE:-}" ]; then
  echo "install.sh: worktree からは実行しない（元のチェックアウトで実行する）" >&2
  exit 1
fi

# Codex: config.toml はリンクせずテンプレートから作る（writable_roots にホームの絶対パスが要るため）。テンプレートにあるキーはテンプレートの値にし、
# 既存のほかのキーと表（Codex の CLI・デスクトップが書く notify・プラグイン・MCP・承認など）は値ごと残す。意味が変わるときだけ既存を退避して置き換え、
# 作れないとき（command 方式の [mcp_servers.linear]、壊れた TOML、書き出しの読み直しの不一致）は止まる。結合は config/codex/merge-config.py（tomlkit）。
# 引数は uv を呼ぶコマンド。--managed-python でシステムの python3 を使わず、--script と --no-config で呼んだ場所や dotfiles の上の場所（~/uv.toml など）の uv・Python の設定に左右されない
codex_config() {
  mkdir -p "$HOME/.codex"
  "$@" run --no-config --managed-python --quiet --script "$DOTFILES/config/codex/merge-config.py" \
    "$DOTFILES/config/codex/config.toml.tmpl" "$HOME/.codex/config.toml" "$HOME"
}
# config.toml の生成だけを検査したい時（tests/acceptance/codex-config.sh）は、PATH の uv で作って終わる（リンクもほかの設定もしない）
if [ -n "${DOTFILES_CODEX_CONFIG_ONLY:-}" ]; then codex_config uv; exit 0; fi

# リンク定義: <リポジトリ内パス> <$HOME からの配置先>
LINKS="
shell/zshenv             .zshenv
shell/zprofile           .zprofile
shell/zshrc              .zshrc
shell/bashrc             .bashrc
shell/bash_profile       .bash_profile
config/mise/config.toml  .config/mise/config.toml
config/starship.toml     .config/starship.toml
config/bat/config        .config/bat/config
config/git/config        .config/git/config
config/git/ignore        .config/git/ignore
config/git/hooks-nosign  .config/git/hooks-nosign
config/tmux/tmux.conf    .config/tmux/tmux.conf
config/ghostty/config    .config/ghostty/config
config/claude/settings.json  .claude/settings.json
config/claude/statusline.sh  .claude/statusline.sh
config/agents/AGENTS.md         .claude/CLAUDE.md
config/agents/AGENTS.md         .codex/AGENTS.md
config/agents/skills/issue      .claude/skills/issue
config/agents/skills/wrap-up    .claude/skills/wrap-up
config/agents/skills/handoff    .claude/skills/handoff
config/agents/skills/issue      .agents/skills/issue
config/agents/skills/wrap-up    .agents/skills/wrap-up
config/herdr/config.toml                  .config/herdr/config.toml
config/nvim              .config/nvim
config/yazi              .config/yazi
bin/agent-status         .local/bin/agent-status
bin/notify               .local/bin/notify
bin/codex-review         .local/bin/codex-review
bin/integrate            .local/bin/integrate
bin/integrate-hook       .local/bin/integrate-hook
bin/handoff              .local/bin/handoff
bin/context-nudge        .local/bin/context-nudge
bin/claude-env           .local/bin/claude-env
bin/agent-pane           .local/bin/agent-pane
bin/geoview              .local/bin/geoview
ssh/config               .ssh/config
ssh/config.mux           .ssh/config.mux
"

link() {
  case "$1" in /*) src="$1" ;; *) src="$DOTFILES/$1" ;; esac
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

# ponytail の band（プロンプトの上の行）を既定で隠す。ファイルがあれば触らない。`/ponytail band on` はファイルを消すだけで再実行で隠れるので、
# 出し続ける端末は中身を on にする（off 以外なら出る）。リンクと同じく tests/install.sh で確かめるので、早期終了の前に置く
[ -e "$HOME/.claude/.ponytail-band" ] || echo off > "$HOME/.claude/.ponytail-band"

# WSL: shell/zshenv が Windows の PATH を絞るので、名前で呼ばれる Windows の道具は ~/.local/bin にリンクする
# （powershell.exe は herdr・Codex のクリップボード、win32yank.exe は Neovim のクリップボード）。
# 先が無ければぶら下がったリンクを作らず warning を出す。リンクと同じく tests/acceptance/wsl.sh で確かめるので、早期終了の前に置く
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  wsl_ps=""; wsl_yank=""
  if wsl_cmd="$(command -v cmd.exe)"; then
    wsl_sys32="$(dirname "$wsl_cmd")"
    wsl_ps="$wsl_sys32/WindowsPowerShell/v1.0/powershell.exe"
    # cmd.exe は Linux のディレクトリで起動すると UNC パスの警告を出すので、system32 で起動する。Windows のユーザー名は Linux と同じとは限らない
    if wsl_lad="$(cd "$wsl_sys32" && cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')" && [ -n "$wsl_lad" ] && wsl_lad="$(wslpath -u "$wsl_lad" 2>/dev/null)"; then
      wsl_yank="$wsl_lad/Microsoft/WinGet/Links/win32yank.exe"
    fi
  fi
  if [ -e "$wsl_ps" ]; then link "$wsl_ps" .local/bin/powershell.exe
  else echo "warning: Windows の powershell.exe を見つけられず、リンクしない（続行）"; fi
  if [ -e "$wsl_yank" ]; then link "$wsl_yank" .local/bin/win32yank.exe
  else echo "warning: Windows の win32yank.exe を見つけられず、リンクしない（Neovim のクリップボードが動かない。Windows で winget install -e --id equalsraf.win32yank）"; fi
fi

# zsh の補完の置き場。compaudit は fpath のディレクトリとその親が他人（group を含む）に書けると、対話の起動のたびに続けるか尋ね、
# 端末が無ければ compinit を打ち切る。umask 002 の端末では mkdir -p が 775 にするので、毎回 go-w にする（前から 775 の端末も直る）。
# 早期終了の前に置くのは、一時 HOME の検査（tests/acceptance/shell.sh）で umask 002 の結果を確かめるため
ZCOMP="$HOME/.local/share/zsh/site-functions"
mkdir -p "$ZCOMP"
chmod go-w "$HOME/.local/share/zsh" "$ZCOMP"

# リンク配置だけを検査したい時（tests/install.sh）はここで終わる
[ -n "${DOTFILES_LINKS_ONLY:-}" ] && exit 0

# ssh は設定ファイル（Include したファイルも）が他ユーザー書き込み可だと拒否するため権限を絞る
chmod 700 "$HOME/.ssh"
chmod 600 "$DOTFILES/ssh/config" "$DOTFILES/ssh/config.mux"

# git config --global の書き込み先を端末ローカルの ~/.gitconfig にする
# （存在しないと ~/.config/git/config = リポジトリ側が書き換わる）
touch "$HOME/.gitconfig"

# zsh プラグイン（プラグインマネージャは使わず、コミットを固定して取得する。上げるときは下の SHA を直す）。
# 取得の失敗は致命にしない（オフラインでも後段を通す。zshrc はファイルがあるときだけ読むので、プラグイン無しで起動でき、再実行で入る）
ZPLUGINS="$HOME/.local/share/zsh/plugins"
mkdir -p "$ZPLUGINS"
for p in zsh-users/zsh-autosuggestions@85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5 \
         zsh-users/zsh-syntax-highlighting@e6683f20e5c38d3e5447f45845d04ddda75d0f23; do
  repo="${p%@*}"; sha="${p#*@}"; dir="$ZPLUGINS/${repo#*/}"
  if [ ! -d "$dir/.git" ] || [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$sha" ]; then
    { [ -d "$dir/.git" ] || git init -q "$dir"; } \
      && git -C "$dir" fetch -q --depth 1 "https://github.com/$repo.git" "$sha" && git -C "$dir" checkout -q --detach "$sha" \
      || echo "warning: $repo を $sha にできなかった（続行）"
  fi
done
# zsh が無ければ静的ビルド（zsh-bin）を ~/.local に入れる（/etc/shells は触らない。chsh できない時は bash_profile が exec zsh）
if ! command -v zsh >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/zsh" ]; then
  # インストーラーはコミットを固定して取得する（中の sha256 で配布物を検証するので、スクリプト自体の改ざんを防ぐ）。取得失敗は set -e で止める
  zsh_bin_install="$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/0c5d2f31679a6bd9a639c1d0b027feed7c271625/install)"
  sh -c "$zsh_bin_install" -- -q -d "$HOME/.local" -e no -a sha256
fi

# mise 本体（~/.local/bin/mise）
# ここから先の mise・uv は、呼んだ場所の設定（mise.toml、.python-version など）に左右されないよう $HOME で実行する
cd "$HOME"
MISE="$HOME/.local/bin/mise"
# 版の上げ方は README の「版の固定と更新」。windows/install.ps1 の $MiseVersion と同じ
MISE_VERSION=v2026.11.3
if [ ! -x "$MISE" ]; then
  # インストーラは取得してから実行する（パイプだと curl の失敗を sh が空入力の成功で隠す。取得失敗は set -e で止める）。
  # 版を固定すると、インストーラは配布物をその release の SHASUMS256.txt で検証する（現行版は埋め込みの sha256）。インストーラ自体は mise.run の
  # その時点のものなので、信頼の根は TLS + mise.run + GitHub（zsh-bin と違い鎖の全体は固定していない。固定するなら raw の URL をコミットで指す）。
  mise_install="$(curl -fsSL https://mise.run)"
  MISE_VERSION="$MISE_VERSION" sh -c "$mise_install"
elif [ "$("$MISE" --version 2>/dev/null | cut -d ' ' -f 1)" != "${MISE_VERSION#v}" ]; then
  # 入っている mise をこの版にする（古い mise は lock を読めない。self-update は配布物の署名を確かめる）
  "$MISE" self-update --yes --no-plugins "${MISE_VERSION#v}"
fi
# lock はリンクせず写す（mise は .node-version などの版を入れるたびにグローバルの lock に書き足すので、リンクだとリポジトリが変わる）。
# rm は前にリンクがあっても、先を書き換えないため
rm -f "$HOME/.config/mise/mise.lock"
cp "$DOTFILES/config/mise/mise.lock" "$HOME/.config/mise/mise.lock"
# lock の版だけを入れる（lock に無い道具・checksum の合わない配布物は入れず止まる）
"$MISE" install --yes --locked

# zsh の補完を道具に書き出させる（git・tmux・jq は zsh に同梱の補完がある）。再実行で道具の版に追随する。足すときは zcomp を 1 行足す。
# 一時ファイルに書いてから置き換え、道具が無い・失敗・出力が空なら前のファイルを残して warning を出す（続行）。stderr は捨てる（mise の更新の知らせなどを混ぜない）
zcomp() { # <名前> <コマンド…>
  zc_name="$1"; shift
  if "$MISE" exec -- "$@" > "$ZCOMP/_$zc_name.new" 2>/dev/null && [ -s "$ZCOMP/_$zc_name.new" ]; then
    mv "$ZCOMP/_$zc_name.new" "$ZCOMP/_$zc_name"
  else
    rm -f "$ZCOMP/_$zc_name.new"
    echo "warning: zsh の補完 $zc_name を作れなかった（続行）"
  fi
}
zcomp gh gh completion -s zsh
zcomp mise "$MISE" completion zsh
zcomp uv uv generate-shell-completion zsh
zcomp uvx uvx --generate-shell-completion zsh
zcomp rg rg --generate complete-zsh
zcomp fd fd --gen-completions zsh

# tinymemory の hook は PATH + ~/.local/bin + ~/.cargo/bin しか探さない（hook 文字列は Codex の
# 信頼ハッシュに固定されていて変更不可）。PATH が最小でも見つかるよう ~/.local/bin に shim を置く
ln -sfn "$HOME/.local/share/mise/shims/tinymemory" "$HOME/.local/bin/tinymemory"

# Codex の config.toml（上の codex_config）。uv は mise のもの（$HOME で実行する）
codex_config "$MISE" exec -- uv
# Codex 本体は公式のインストーラー（~/.local/bin、sha256 で検証）。入っていれば何もしない（npm などで入れた端末もそのまま）。
# ~/.local/bin が PATH に無いと起動ファイル（dotfiles へのリンク）に書き足すので、PATH に入れてから呼ぶ
CODEX="$(command -v codex || echo "$HOME/.local/bin/codex")"
# 取得や導入に失敗しても（オフラインなど）install.sh は止めず、Codex の後続だけ飛ばす
if [ ! -x "$CODEX" ]; then
  if codex_install="$(curl -fsSL https://chatgpt.com/codex/install.sh)"; then
    PATH="$HOME/.local/bin:$PATH" CODEX_NON_INTERACTIVE=1 sh -c "$codex_install" || true
  fi
  [ -x "$CODEX" ] || echo "warning: Codex を入れられなかった（続行。install.sh の再実行で入れ直す）"
fi
# ponytail は宣言だけでは入らない（ログインは要らない）。superpowers は Codex 公式のカタログにあり、ログインの後に config/codex/README.md の手順で入れる
if [ -x "$CODEX" ]; then
  "$CODEX" plugin marketplace add DietrichGebert/ponytail >/dev/null && "$CODEX" plugin add ponytail@ponytail >/dev/null \
    || echo "warning: Codex に ponytail を入れられなかった（続行）"
fi
# tinymemory の Codex の hook（~/.codex/hooks.json）と skill。承認は Codex の /hooks で端末ごとに一度
"$HOME/.local/bin/tinymemory" init codex >/dev/null

# Neovim プラグインを lazy-lock.json のバージョンに揃える（端末間の差分を防ぐ）。mise exec で tree-sitter も PATH に載せ、
# init.lua の treesitter の有効・無効が install.sh を呼んだシェルの PATH で変わらないようにする
if "$MISE" which nvim >/dev/null 2>&1; then
  "$MISE" exec -- nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || echo "warning: nvim プラグインの restore に失敗"
fi

# mac 専用（Homebrew、スクリーンショット設定）
if [ "$(uname -s)" = Darwin ]; then
  "$DOTFILES/mac/setup.sh"
fi

echo "done."
