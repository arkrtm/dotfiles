# config/mise

- `config/mise/config.toml`: rg fd bat eza fzf starship gh jq uv node tmux lazygit lazydocker neovim tree-sitter yazi tinymemory

## mise

- 公開 24 時間未満のリリースは `latest` で選ばれない（サプライチェーン対策）。自作の tinymemory は版を明示しているので、**リリースしたら `config/mise/config.toml` の版を上げる**
- mise 本体の版は `install.sh` の `MISE_VERSION=` で固定している（最初の install にだけ効く。インストーラが配布物をその release の SHASUMS256.txt で検証するため）。上げるときはその値を直す。入っている端末は `mise self-update`
- `config.toml` の後半はテーブル形式。**その後ろに `key = value` を書くとテーブルに入ってしまう**ので、通常のツールは前半に追加する
- tinymemory のプラグイン hook は PATH・`~/.local/bin`・`~/.cargo/bin` しか探さない（hook 文字列は変更不可）→ `install.sh` が `~/.local/bin/tinymemory` に shim を置く

## Node

- 版はプロジェクトの `mise.toml`・`.node-version`・`.nvmrc`（`[settings]` の `idiomatic_version_file_enable_tools`）、無ければ `node = "lts"`。対話のシェルは mise activate、非対話のシェル（スクリプト、エージェントのコマンド）は PATH の shims が、呼ばれた場所で決める。Claude Code の Bash ツールは起動したシェルの PATH を使い回すので、SessionStart のフック（`bin/claude-env`、Windows は `windows/posix/hook env`）が shims を先頭に置く。入っていない版は最初の呼び出しで入る
- `lts` が指す版は mise の版に書かれている。新しい LTS（毎年 10 月）に移るには mise を上げる（`install.sh` の `MISE_VERSION`・`windows/install.ps1` の `$MiseVersion`、入っている端末は `mise self-update`）。同じ LTS の中の更新は `mise upgrade`（ほかの道具と同じ）。古い版は `mise prune`
- npm・npx・corepack は使っている node と同じ版で動く。corepack は Node 24 まで同梱（25 から無い）。pnpm・yarn は `corepack pnpm …`。`node.corepack`（corepack enable）は Windows で失敗して Node 24 以前が入らなくなるので使わない
- `npm i -g` で入れた道具は、その版の Node に入る（版を変えると無い）。mac / linux は npm の後に mise が shims を作り直す。Windows は `mise reshim`
- Linux: Node 26 以降の公式の配布物は `libatomic1` が要る。無いと `mise install` が Node の確かめで失敗する。sudo が無く入れられない端末は、端末ごとの `~/.config/mise/config.local.toml`（リポジトリの外。`config.toml` より勝ち、プロジェクトの指定はさらに勝つ）に `[tools]` `node = "24"`（libatomic が要らない LTS）を書く
- fnm から移る（前に install.sh を実行した端末で一度）: `mise self-update` → `~/dotfiles/install.sh` → シェルと Claude Code を開き直す。消してよいもの: `mise uninstall --all aqua:Schniz/fnm`、`~/.local/share/fnm`。fnm の Node に `npm i -g` で入れたものは入れ直す。Windows は `windows/README.md`
