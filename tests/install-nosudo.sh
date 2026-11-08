#!/bin/sh
# sudo の無い Linux で install.sh が最後まで通り、必要なものがすべてユーザー領域に入ることの検査
# debian:12（sudo も python3 も zsh も tmux も node も無い）に git と curl と libatomic1（Node 26 以降の公式の配布物が要る。README の前提）だけ入れ、一般ユーザーで実行する。
# 作業ツリー（未コミットの変更を含む）を標準入力でコンテナに送る。この端末の docker で実行する（DOCKER で docker のコマンドを替えられる）:
#   sh tests/install-nosudo.sh
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

  # Node（mise）。nodev: 版だけを出して 0 で終わったときだけ版を返す（エラーの文・起動ファイルの出力が混ざれば失敗。libatomic が無いときの node のエラーも）
  nodev() { _v="$("$@" 2>&1)" || return 1; case "$_v" in '' | *[!v0-9.]*) return 1 ;; v[0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$_v" ;; *) return 1 ;; esac; }
  nodev sh -c 'echo v22.1.0' >/dev/null && ! nodev sh -c 'echo "node: error while loading shared libraries: libatomic.so.1"; exit 127' >/dev/null &&
    ! nodev sh -c 'echo libatomic >&2; echo v22.1.0' >/dev/null && ok "node の検査は版だけを出して 0 で終わったときだけ通す" || ng "node の検査そのもの"
  # 最新の LTS は nodejs.org の一覧（新しい順）の最初の LTS。mise の lts は mise の版に書かれているので、ずれたら install.sh の MISE_VERSION を上げる
  idx="$(curl -fsSL https://nodejs.org/dist/index.json || true)"
  lts="$(printf '%s\n' "$idx" | sed -n '/"lts":"/{s/^{"version":"v\([0-9]*\)\..*/\1/p;q;}')"
  [ -n "$lts" ] || ng "最新の LTS を nodejs.org の一覧から読めない"
  n="$(zq 'command -v node' || true)"
  [ "$n" = "$HOME/.local/share/mise/shims/node" ] && ok "非対話 zsh の node は mise の shim" || ng "非対話 zsh の node が mise の shim でない（${n:-なし}）"
  v="$(nodev zq 'node --version')" && [ "${v%%.*}" = "v$lts" ] && ok "非対話 zsh の node が動き、指定の無い場所では最新の LTS（$v）" ||
    ng "非対話 zsh の node: $(zq 'node --version')（最新の LTS は v$lts）"
  # ssh 経由のコマンドなど、非対話のログイン bash（bash_profile → bashrc）
  v="$(nodev clean env NO_ZSH=1 bash -lc 'node --version')" && [ "${v%%.*}" = "v$lts" ] && ok "bash -lc の node も動き、最新の LTS（$v）" ||
    ng "bash -lc の node: $(clean env NO_ZSH=1 bash -lc 'node --version' 2>&1)"
  # .node-version・.nvmrc の版（先に入れておく。入っていなければ shim が最初の呼び出しで入れ、その出力が混ざる）
  zq 'mise install --yes node@22' >/dev/null || ng "node@22 を入れられない"
  mkdir -p "$HOME/nv" "$HOME/nr"; echo 22 > "$HOME/nv/.node-version"; echo v22 > "$HOME/nr/.nvmrc"
  v="$(cd "$HOME/nv" && nodev zq 'node --version')" && [ "${v%%.*}" = v22 ] && ok ".node-version の場所の非対話 zsh は v22（$v）" || ng ".node-version の場所の非対話 zsh: $(cd "$HOME/nv" && zq 'node --version')"
  v="$(cd "$HOME/nr" && nodev zq 'node --version')" && [ "${v%%.*}" = v22 ] && ok ".nvmrc の場所の非対話 zsh は v22（$v）" || ng ".nvmrc の場所の非対話 zsh: $(cd "$HOME/nr" && zq 'node --version')"
  v="$(cd "$HOME/nv" && nodev clean env NO_ZSH=1 bash -lc 'node --version')" && [ "${v%%.*}" = v22 ] && ok ".node-version の場所の bash -lc は v22" || ng ".node-version の場所の bash -lc"
  m="$(cd "$HOME/nv" && zq 'npm version --json' || true)"
  case "$m" in *'"node": "22.'*) ok "npm も .node-version の版の node で動く" ;; *) ng "npm の node: $m" ;; esac

  u="$(zq 'command -v uv' || true)"
  [ "$u" = "$HOME/.local/share/mise/shims/uv" ] && ok "日常の uv は mise の shim（プロジェクトの版の固定に従う）" || ng "日常の uv が mise の shim でない（${u:-なし}）"

  # 対話 zsh（zsh-bin の 5.8）。端末が無いと zle が使えないので script で疑似端末を付け、端末の制御シーケンスと CR を除く
  zi() { clean script -qec "$HOME/.local/bin/zsh -ic '$1'" /dev/null 2>&1 | tr -d '\r' | sed "s/$(printf '\033')\[[?0-9;]*[a-zA-Z]//g"; }
  i="$(zi 'echo mise=${MISE_SHELL:+ok}')"
  [ "$i" = "mise=ok" ] && ok "対話 zsh で zshrc がエラーなく読まれ、mise activate が効く" || ng "対話 zsh の zshrc: $i"
  i="$(cd "$HOME/nv" && zi 'node --version')"
  case "$i" in '' | *[!v0-9.]*) ng "対話 zsh の node: $i" ;; v22.[0-9]*.[0-9]*) ok "対話 zsh も .node-version の版（$i）" ;; *) ng "対話 zsh の node: $i" ;; esac
  # zsh の補完: install.sh が書き出した補完を、対話 zsh の compinit が読む
  c="$(clean script -qec "$HOME/.local/bin/zsh -ic 'print -r -- \${_comps[gh]}/\${_comps[mise]}/\${_comps[uv]}/\${_comps[uvx]}/\${_comps[rg]}/\${_comps[fd]}'" /dev/null 2>&1 | tr -d '\r' | sed "s/$(printf '\033')\[[?0-9;]*[a-zA-Z]//g" || true)"
  [ "$c" = "_gh/_mise/_uv/_uvx/_rg/_fd" ] && ok "対話 zsh に gh・mise・uv・uvx・rg・fd の補完がある" || ng "zsh の補完: $c"
  # zsh のプラグイン: install.sh に書いたコミット（2 回の install の後。再実行でも変わらない）
  n=0
  for p in $(grep -o 'zsh-users/[a-z-]*@[0-9a-f]\{40\}' "$HOME/dotfiles/install.sh"); do
    r="${p%@*}"; h="$(git -C "$HOME/.local/share/zsh/plugins/${r#*/}" rev-parse HEAD 2>/dev/null || true)"
    if [ "$h" = "${p#*@}" ]; then n=$((n + 1)); else ng "zsh のプラグイン $r が ${p#*@} でない（${h:-なし}）"; fi
  done
  [ "$n" = 2 ] && ok "zsh のプラグイン 2 つが install.sh に書いたコミットで、再実行でも変わらない" || ng "固定したプラグインの数: $n"

  p="$(clean "$HOME/.local/bin/zsh" -lc 'echo "$PATH"' 2>&1 || true)"
  case "$p" in "$HOME/.local/bin:$HOME/.local/share/mise/shims:"*) ok "ログイン zsh（zprofile）でも PATH の先頭はユーザー領域で重複が無い" ;; *) ng "ログイン zsh の PATH: $p" ;; esac
  sh="$(clean sh -c 'PATH="$HOME/.local/bin:$PATH"; command -v tinymemory' 2>&1 || true)"
  [ "$sh" = "$HOME/.local/bin/tinymemory" ] && ok "tinymemory の shim が ~/.local/bin にある（Claude Code の hook が探す場所）" || ng "tinymemory の shim: ${sh:-なし}"

  # Codex: 公式のインストーラーで ~/.local/bin に入り、起動ファイルに PATH を書き足さない。config.toml はテンプレートと既存の結合で、
  # 既存は 1 回だけ退避（2 回目は意味が同じなので退避しない）。テンプレートに無い表は値ごと残る。ponytail が入り、tinymemory の hook がある
  cv="$(clean "$HOME/.local/bin/codex" --version 2>&1 || true)"
  case "$cv" in codex-cli*) ok "codex が ~/.local/bin に入り動く（$cv）" ;; *) ng "codex が動かない: $cv" ;; esac
  grep -l 'Codex installer' "$HOME"/dotfiles/shell/* "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null | grep . && ng "Codex のインストーラーが起動ファイルに書き足した" || ok "Codex のインストーラーは起動ファイルを変えない"
  CT="$HOME/.codex/config.toml"
  if ! grep -q '@HOME@' "$CT" && grep -qxF "writable_roots = [\"$HOME/.tinymemory\"]" "$CT" && grep -qx 'model_reasoning_effort = "xhigh"' "$CT" && grep -qx 'model = "gpt-6.1-sol"' "$CT" \
    && grep -qxF '[plugins."ponytail@ponytail"]' "$CT" && grep -qx '\[mcp_servers.linear\]' "$CT"; then ok "config.toml はテンプレートから生成される"; else ng "config.toml: $(cat "$CT")"; fi
  bk="$(ls "$CT".bak.* 2>/dev/null || true)"
  [ "$(echo "$bk" | grep -c .)" = 1 ] && grep -qx 'model = "old"' "$bk" && ok "既存の config.toml は 1 回だけ退避される" || ng "config.toml の退避: ${bk:-なし}"
  grep -qxF '[hooks.state."a:session_start:0:0"]' "$CT" && grep -qx 'trusted_hash = "sha256:aa"' "$CT" && grep -qxF '[projects."/x"]' "$CT" \
    && ! grep -q 'model = "old"' "$CT" && grep -qx '\[other\]' "$CT" && grep -qx 'k = 1' "$CT" && ok "テンプレートに無い表（Codex が書いた承認・信頼・ほか）は値ごと残る" || ng "引き継ぎ: $(cat "$CT")"
  clean "$HOME/.local/bin/codex" plugin list 2>/dev/null | grep -q 'ponytail@ponytail  *installed, enabled' && ok "Codex に ponytail が入る" || ng "Codex に ponytail が入っていない"
  grep -q 'tinymemory hook session-start' "$HOME/.codex/hooks.json" 2>/dev/null && ok "Codex の hooks.json に tinymemory の SessionStart がある" || ng "Codex の hooks.json に tinymemory が無い"

  exit "$fail"
fi

if [ "${1:-}" = --in-container ]; then
  # ---- コンテナ内で root として: 前提（git, curl）だけ入れ、一般ユーザーで install.sh → 検査 ----
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends git curl ca-certificates libatomic1 >/dev/null
  useradd -m -s /bin/bash u
  cp -R /src /home/u/dotfiles && chown -R u:u /home/u/dotfiles
  # 既存の config.toml: 退避されること、テンプレートに無い表（承認・信頼・[other]）が値ごと残ること
  mkdir -p /home/u/.codex && printf 'model = "old"\n\n[projects."/x"]\ntrust_level = "trusted"\n\n[hooks.state."a:session_start:0:0"]\ntrusted_hash = "sha256:aa"\n\n[other]\nk = 1\n' > /home/u/.codex/config.toml && chown -R u:u /home/u/.codex
  for run in 1 2; do # 2 回目は「再実行しても安全」の確認
    su - u -c "sh ~/dotfiles/install.sh" >/tmp/install.log 2>&1 || { tail -40 /tmp/install.log; echo "FAIL install.sh（$run 回目）が失敗した"; exit 1; }
    # 想定外の warning / error は失敗にする
    if grep -iE "warning|error" /tmp/install.log; then echo "FAIL install.sh（$run 回目）が warning / error を出した"; exit 1; fi
  done
  # テンプレートと混ぜられない config.toml（command 方式の [mcp_servers.linear]）では、フルの install.sh も config.toml の生成で止まり、
  # config.toml を変えず退避もしない。確かめた後は元に戻す（--check は 2 回目までの結果を見る）
  C=/home/u/.codex/config.toml
  cp -p "$C" /tmp/keep.toml && printf '[mcp_servers.linear]\ncommand = "npx"\n' > "$C" && cp -p "$C" /tmp/bad.toml
  nb="$(ls "$C".bak.* | wc -l)"
  if su - u -c "sh ~/dotfiles/install.sh" >/tmp/install.log 2>&1; then tail -40 /tmp/install.log; echo "FAIL install.sh が command 方式の linear で止まらなかった"; exit 1; fi
  grep -qF 'mcp_servers.linear' /tmp/install.log && ! grep -qx 'done.' /tmp/install.log && cmp -s "$C" /tmp/bad.toml && [ "$(ls "$C".bak.* | wc -l)" = "$nb" ] \
    || { tail -40 /tmp/install.log; echo "FAIL command 方式の linear で、理由を出して止まり config.toml を変えず退避しないこと"; exit 1; }
  cp -p /tmp/keep.toml "$C"
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
