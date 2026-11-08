# config/mise

- `config/mise/config.toml`: rg fd bat eza fzf starship gh jq uv node tmux lazygit lazydocker neovim tree-sitter yazi tinymemory。tmux は Windows に、eza は mac に入れない（`os` で決める）。mac の eza は lock の対象外の例外で Brewfile（理由はルートの README の「版の固定と更新」）。eza が無い端末の `ll`・`la` は ls
- `config/mise/mise.lock`: 道具の版・URL・checksum。更新はルートの README の「版の固定と更新」

## mise

- 公開 24 時間未満のリリースは `latest` で選ばれない（サプライチェーン対策）。lock を作り直すときも同じ。自作の tinymemory は版を明示しているので、**リリースしたら `config/mise/config.toml` の版を上げて lock を作り直す**（README）
- mise 本体の版は `install.sh` の `MISE_VERSION=`（`windows/install.ps1` は `$MiseVersion`）で固定している。install は、入っている mise をその版にする（古い mise は lock を読めない）。インストーラは配布物をその release の SHASUMS256.txt で検証する。上げ方は README
- lock は install が `~/.config/mise/mise.lock` に**写し**（リンクしない: mise は `.node-version` などの版を入れるたびにグローバルの lock に書き足すので、リンクだとリポジトリが変わる）、`mise install --locked` で lock の版だけを入れる。lock に無い道具・checksum の合わない配布物は入らず、install が止まる。shim の自動の導入も、lock にある版は checksum を確かめる
- `config.toml` の後半はテーブル形式。**その後ろに `key = value` を書くとテーブルに入ってしまう**ので、通常のツールは前半に追加する
- tinymemory のプラグイン hook は PATH・`~/.local/bin`・`~/.cargo/bin` しか探さない（hook 文字列は変更不可）→ `install.sh` が `~/.local/bin/tinymemory` に shim を置く

## Node

- 版はプロジェクトの `mise.toml`・`.node-version`・`.nvmrc`（`[settings]` の `idiomatic_version_file_enable_tools`）、無ければ lock の node（lock を作り直したときの最新の LTS）。対話のシェルは mise activate、非対話のシェル（スクリプト、エージェントのコマンド）は PATH の shims が、呼ばれた場所で決める。Claude Code の Bash ツールは起動したシェルの PATH を使い回すので、SessionStart のフック（`bin/claude-env`、Windows は `windows/posix/hook env`）が shims を先頭に置く。Windows の PowerShell ツールは、pwsh のプロファイルが cd と prompt のたびに PATH から Node の install のディレクトリを外すので、起動した pwsh の PATH を受け継いでも node・npm・npx・corepack は shims が呼ばれた場所の版で動く。入っていない版は最初の呼び出しで入る
- `lts` が指す版は mise の版に書かれている。新しい LTS（毎年 10 月）や同じ LTS の中の更新は lock を作り直す（README。新しい LTS は先に mise を上げる）。古い版は `mise prune`
- npm・npx・corepack は使っている node と同じ版で動く。corepack は Node 24 まで同梱（25 から無い）。pnpm・yarn は `corepack pnpm …`。`node.corepack`（corepack enable）は Windows で失敗して Node 24 以前が入らなくなるので使わない
- `npm i -g` で入れた道具は、その版の Node に入る（版を変えると無い）。mac / linux は npm の後に mise が shims を作り直す。Windows は `mise reshim`
- Linux: Node 26 以降の公式の配布物は `libatomic1` が要る。無いと `mise install` が Node の確かめで失敗する。sudo が無く入れられない端末は、端末ごとの `~/.config/mise/config.local.toml`（リポジトリの外。`config.toml` より勝ち、プロジェクトの指定はさらに勝つ）に `[tools]` `node = "24"`（libatomic が要らない LTS）を書き、一度 `mise lock --global --local` を実行する（install は lock の版だけを入れるので、端末の版を `~/.config/mise/mise.local.lock` に固定する。リポジトリの外）
- fnm から移る（前に install.sh を実行した端末で一度）: `~/dotfiles/install.sh` → シェルと Claude Code を開き直す。消してよいもの: `mise uninstall --all aqua:Schniz/fnm`、`~/.local/share/fnm`。fnm の Node に `npm i -g` で入れたものは入れ直す。Windows は `windows/README.md`
- lock を入れた後に一度（前に install.sh を実行した端末）: `config.local.toml` のある端末は先に `mise lock --global --local`。mac は `mise uninstall --all eza` の後に install.sh（Homebrew の eza を使う。前の mise の eza（vfox）の shim が残ると、zshrc が eza ありと見て壊れた shim を呼ぶため）。前の eza の入れ物は `mise prune` で消える
