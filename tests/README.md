# tests

- `scripts/check`: リンクしない。dotfiles のテスト（`tests/static.sh`・`install.sh`・`acceptance.sh`。dotfiles の `integrate setup` の test と CI が呼ぶ。ほかのリポジトリに同じ名前を求める決まりではない）
- `.github/workflows/check.yml`: リンクしない。GitHub の CI。PR と main への push で `scripts/check` を ubuntu で実行する（push の後の知らせ。main の保護の必須チェックではない）
- `tests/`: リンクしない。コミット前の検査（何を通すかは `CLAUDE.md`）。`static.sh` は構文と設定、`install.sh` はリンク、`acceptance/*.sh` は受け入れ、`install-nosudo.sh` はコンテナでのフル install、`nvim.sh` は Neovim

## GitHub の main の保護

自分の GitHub（kind `github`）は integrate が main へ直接 push するので、PR 必須・必須チェックは入れず、強制 push と main の削除だけを禁じる。CI（`.github/workflows/check.yml`）は push の後に結果を知らせるだけ。PR を使うとき（手作業など）のマージは rebase だけ（squash・merge commit は無効）で、マージ後にブランチを消す。リポジトリごとに一度:

```sh
gh api -X PUT repos/arkrtm/dotfiles/branches/main/protection --input - <<'EOF'
{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"required_linear_history":true,"allow_force_pushes":false,"allow_deletions":false}
EOF
gh api -X PATCH repos/arkrtm/dotfiles -F allow_rebase_merge=true -F allow_squash_merge=false -F allow_merge_commit=false -F delete_branch_on_merge=true -F allow_auto_merge=false
```
