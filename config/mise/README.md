# config/mise

- `config/mise/config.toml`: rg fd bat eza fzf starship gh jq uv fnm tmux lazygit lazydocker neovim tree-sitter yazi tinymemory

## mise

- 公開 24 時間未満のリリースは `latest` で選ばれない（サプライチェーン対策）。自作の tinymemory は版を明示しているので、**リリースしたら `config/mise/config.toml` の版を上げる**
- mise 本体の版は `install.sh` の `MISE_VERSION=` で固定している（最初の install にだけ効く。インストーラが配布物をその release の SHASUMS256.txt で検証するため）。上げるときはその値を直す。入っている端末は `mise self-update`
- `config.toml` の後半はテーブル形式。**その後ろに `key = value` を書くとテーブルに入ってしまう**ので、通常のツールは前半に追加する
- tinymemory のプラグイン hook は PATH・`~/.local/bin`・`~/.cargo/bin` しか探さない（hook 文字列は変更不可）→ `install.sh` が `~/.local/bin/tinymemory` に shim を置く
