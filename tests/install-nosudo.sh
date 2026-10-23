#!/bin/sh
# sudo の無い Linux で install.sh が最後まで通り、必要なものがすべてユーザー領域に入ることの検査（ARK-37）
# debian:12（sudo も python3 も zsh も tmux も node も無い）に git と curl だけ入れ、一般ユーザーで実行する。
# 併せて config/pi/setup.sh（Pi/herdr エージェント層）も sudo なしでユーザー領域に入ることを確認する（Pi パッケージを取得するぶん遅い）。
# 作業ツリー（未コミットの変更を含む）をコンテナに送るので、docker を別の端末で動かしてもよい:
#   sh tests/install-nosudo.sh                         # docker がある端末（NAS）で
#   DOCKER='ssh nas docker' sh tests/install-nosudo.sh # mac から NAS の docker を使う
# ネットワークからツールを取得するので数分かかる。
set -eu

if [ "${1:-}" = --check ]; then
  # ---- コンテナ内で、install.sh を実行した一般ユーザーとして検査する ----
  fail=0
  ok() { echo "ok   $1"; }
  ng() { echo "FAIL $1"; fail=1; }
  under_home() { case "$1" in "$HOME"/*) return 0 ;; *) return 1 ;; esac; }
  # 検査は環境を空にして行う（su の中では bashrc が作った PATH を引き継いでいて、zshenv 等を検査できないため）
  clean() { env -i HOME="$HOME" PATH=/usr/bin:/bin TERM=xterm-256color "$@"; }
  # 非対話の zsh（スクリプトや Claude Code のコマンド実行と同じ条件。zshenv だけが読まれる）で実行する。
  # stderr も拾う（起動ファイルがエラーを出せば値に混ざって、後の比較が落ちる）
  zq() { clean "$HOME/.local/bin/zsh" -c "$1" 2>&1; }

  command -v sudo >/dev/null 2>&1 && ng "前提: sudo が無いこと" || ok "前提: sudo が無い"
  [ ! -e /usr/bin/python3 ] && ok "前提: システムの python3 が無い" || ng "前提: システムの python3 が無いこと"
  [ "$(id -u)" != 0 ] && ok "前提: 一般ユーザーで実行している" || ng "前提: 一般ユーザーで実行すること"

  clean "$HOME/.local/bin/zsh" -c 'exit 0' && ok "zsh がユーザー領域（~/.local/bin）に入り動く" || ng "zsh が ~/.local/bin に無いか動かない"
  # ssh の対話ログインと同じ条件（PATH は /etc/profile のもの、chsh なし）で bash から zsh に切り替わる
  s="$(echo 'echo "shell=${ZSH_VERSION:+zsh}"' | clean bash -il 2>/dev/null || true)"
  case "$s" in *shell=zsh*) ok "対話ログインの bash は zsh に切り替わる" ;; *) ng "対話ログインの bash が zsh に切り替わらない（$s）" ;; esac

  t="$(zq 'command -v tmux' || true)"
  # new-session は conf が壊れていても 0 を返すので、source-file で conf も確かめる
  under_home "$t" && zq 'tmux -L t new-session -d "sleep 5" && tmux -L t source-file "$HOME/.config/tmux/tmux.conf" && tmux -L t kill-server' &&
    ok "tmux がユーザー領域に入り、セッションを作れ、tmux.conf が読める（$t）" || ng "tmux がユーザー領域に無いか、動かないか、tmux.conf にエラーがある（${t:-なし}）"

  n="$(zq 'command -v node' || true)"
  case "$n" in "$HOME"/*/fnm/*) v="$(zq 'node --version' || true)"; [ -n "$v" ] && ok "非対話 zsh の node は fnm の既定版（$v）" || ng "node が動かない（$n）" ;;
    *) ng "非対話 zsh の node が fnm 管理でない（${n:-なし}）" ;; esac
  # ssh 経由のコマンドなど、非対話のログイン bash（bash_profile → bashrc）
  b="$(clean env NO_ZSH=1 bash -lc 'command -v node' 2>&1 || true)"
  case "$b" in "$HOME"/*/fnm/*) ok "bash でも node は fnm の既定版" ;; *) ng "bash で node が fnm 管理でない（${b:-なし}）" ;; esac

  u="$(zq 'command -v uv' || true)"
  [ "$u" = "$HOME/.local/share/mise/shims/uv" ] && ok "日常の uv は mise の shim（プロジェクトの版の固定に従う）" || ng "日常の uv が mise の shim でない（${u:-なし}）"

  # 対話 zsh（zsh-bin の 5.8）で zshrc がエラーなく読まれ、fnm env が効く（端末が無いと zle が使えないので script で疑似端末を付ける）
  i="$(clean script -qec "$HOME/.local/bin/zsh -ic 'echo fnm=\${FNM_MULTISHELL_PATH:+ok}'" /dev/null 2>&1 | tr -d '\r' | sed "s/$(printf '\033')\[[?0-9;]*[a-zA-Z]//g" || true)" # 端末の制御シーケンスは除く
  [ "$i" = "fnm=ok" ] && ok "対話 zsh で zshrc がエラーなく読まれ、fnm env が効く" || ng "対話 zsh の zshrc: $i"

  g="$(clean env GODEBUG=tlskyber=0 "$HOME/.local/bin/zsh" -c 'echo "g=${GODEBUG:-none}"' 2>&1 || true)"
  [ "$g" = "g=none" ] && ok "廃止済みの GODEBUG を zshenv が外す（NAS の go.sh 対策）" || ng "GODEBUG が残る: $g"
  p="$(clean "$HOME/.local/bin/zsh" -lc 'echo "$PATH"' 2>&1 || true)"
  case "$p" in "$HOME/.local/share/fnm/aliases/default/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:"*) ok "ログイン zsh（zprofile）でも PATH の先頭はユーザー領域で重複が無い" ;; *) ng "ログイン zsh の PATH: $p" ;; esac
  sh="$(clean sh -c 'PATH="$HOME/.local/bin:$PATH"; command -v tinymemory' 2>&1 || true)"
  [ "$sh" = "$HOME/.local/bin/tinymemory" ] && ok "tinymemory の shim が ~/.local/bin にある（Claude Code の hook が探す場所）" || ng "tinymemory の shim: ${sh:-なし}"

  # config/pi/setup.sh の成果物がすべてユーザー領域に入ったか（Pi 本体・パッケージ・yamlfix、sudo なし）
  pb="$(zq 'command -v pi' || true)"
  under_home "$pb" && ok "pi がユーザー領域に入る（$pb）" || ng "pi がユーザー領域に無い（${pb:-なし}）"
  [ -d "$HOME/.pi/agent/npm/node_modules/pi-subagents" ] && ok "Pi パッケージが ~/.pi に入る（pi-subagents）" || ng "Pi パッケージが ~/.pi に無い"
  yf="$(zq 'command -v yamlfix' || true)"
  under_home "$yf" && ok "yamlfix がユーザー領域に入る（$yf）" || ng "yamlfix がユーザー領域に無い（${yf:-なし}）"

  # Codex（ARK-87）: 公式のインストーラーで ~/.local/bin に入り、起動ファイルに PATH を書き足さない。config.toml はテンプレートから生成され、
  # 既存は 1 回だけ退避（2 回目は同じ中身なので退避しない）。ponytail が入り、tinymemory の hook がある
  cv="$(clean "$HOME/.local/bin/codex" --version 2>&1 || true)"
  case "$cv" in codex-cli*) ok "codex が ~/.local/bin に入り動く（$cv）" ;; *) ng "codex が動かない: $cv" ;; esac
  grep -l 'Codex installer' "$HOME"/dotfiles/shell/* "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null | grep . && ng "Codex のインストーラーが起動ファイルに書き足した" || ok "Codex のインストーラーは起動ファイルを変えない"
  CT="$HOME/.codex/config.toml"
  if ! grep -q '@HOME@' "$CT" && grep -qxF "writable_roots = [\"$HOME/.tinymemory\"]" "$CT" && grep -qx 'model_reasoning_effort = "high"' "$CT" \
    && grep -qxF '[plugins."ponytail@ponytail"]' "$CT" && grep -qx '\[mcp_servers.linear\]' "$CT"; then ok "config.toml はテンプレートから生成される"; else ng "config.toml: $(cat "$CT")"; fi
  bk="$(ls "$CT".bak.* 2>/dev/null || true)"
  [ "$(echo "$bk" | grep -c .)" = 1 ] && grep -qx 'model = "old"' "$bk" && ok "既存の config.toml は 1 回だけ退避される" || ng "config.toml の退避: ${bk:-なし}"
  grep -qxF '[hooks.state."a:session_start:0:0"]' "$CT" && grep -qx 'trusted_hash = "sha256:aa"' "$CT" && grep -qxF '[projects."/x"]' "$CT" \
    && ! grep -q 'model = "old"' "$CT" && ! grep -qx '\[other\]' "$CT" && ok "Codex が書いた承認と信頼の表だけ引き継ぐ" || ng "引き継ぎ: $(cat "$CT")"
  clean "$HOME/.local/bin/codex" plugin list 2>/dev/null | grep -q 'ponytail@ponytail  *installed, enabled' && ok "Codex に ponytail が入る" || ng "Codex に ponytail が入っていない"
  grep -q 'tinymemory hook session-start' "$HOME/.codex/hooks.json" 2>/dev/null && ok "Codex の hooks.json に tinymemory の SessionStart がある" || ng "Codex の hooks.json に tinymemory が無い"

  exit "$fail"
fi

if [ "${1:-}" = --in-container ]; then
  # ---- コンテナ内で root として: 前提（git, curl）だけ入れ、一般ユーザーで install.sh → 検査 ----
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends git curl ca-certificates >/dev/null
  useradd -m -s /bin/bash u
  cp -R /src /home/u/dotfiles && chown -R u:u /home/u/dotfiles
  # 既存の config.toml: 退避されること、Codex が書いた承認（hooks.state）・信頼（projects）・表示（tui）の表は引き継がれること
  mkdir -p /home/u/.codex && printf 'model = "old"\n\n[projects."/x"]\ntrust_level = "trusted"\n\n[hooks.state."a:session_start:0:0"]\ntrusted_hash = "sha256:aa"\n\n[other]\nk = 1\n' > /home/u/.codex/config.toml && chown -R u:u /home/u/.codex
  for run in 1 2; do # 2 回目は「再実行しても安全」の確認
    su - u -c "sh ~/dotfiles/install.sh" >/tmp/install.log 2>&1 || { tail -40 /tmp/install.log; echo "FAIL install.sh（$run 回目）が失敗した"; exit 1; }
    # 想定外の warning / error は失敗にする（2 回目の fnm の「インストール済み」だけは想定内）
    if grep -iE "warning|error" /tmp/install.log | grep -v "Version already installed"; then echo "FAIL install.sh（$run 回目）が warning / error を出した"; exit 1; fi
  done
  # Pi/herdr エージェント層（config/pi/setup.sh、sudo なし）。npm は warning が多いので
  # 終了コードだけで判定し、成果物は --check で確認する。ネットワークで Pi パッケージを入れるので遅い
  su - u -c "sh ~/dotfiles/config/pi/setup.sh" >/tmp/setup.log 2>&1 || { tail -40 /tmp/setup.log; echo "FAIL config/pi/setup.sh が失敗した"; exit 1; }
  exec su - u -c "sh ~/dotfiles/tests/install-nosudo.sh --check"
fi

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
# 削除済みの追跡ファイルがあると tar が失敗するが、パイプの終了コードは base64 のものなので先に止める
[ -z "$(git -C "$DOTFILES" ls-files --deleted)" ] || { echo "FAIL 削除済みの追跡ファイルがある（コミットするか戻す）"; exit 1; }

# コンテナへは標準入力だけで渡す（ssh 経由でも引数の引用が崩れないように）: 作業ツリーの tar を埋め込んだ sh スクリプト
{
  echo "set -eu; mkdir /src; base64 -d <<'EOF' | tar xf - -C /src"
  git -C "$DOTFILES" ls-files -co --exclude-standard -z | (cd "$DOTFILES" && tar cf - --no-xattrs --null -T -) | base64
  echo "EOF"
  echo "exec sh /src/tests/install-nosudo.sh --in-container"
} | $DOCKER run -i --rm debian:12 sh -s
