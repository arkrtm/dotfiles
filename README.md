# dotfiles — Claude Code 環境

`~/dotfiles` を単一の真実として、Claude Code のカスタム環境を多端末で再現する。

- **auto mode** をデフォルト（literal `auto`）
- **Python-first**（`uv` / `ruff` / `pytest` / `pyright`）。ツール版は mise で pin
- **強制開発ワークフロー**（要件→設計→実装(TDD)→review→verify、hook + 状態機械で hard-enforce）
- **長期記憶 cc-memory**（ディレクトリ別・検索可能・`/dream` 整理。データは machine-local）
- **自己改善 `/learn`**（セッション学習を承認制で skill/CLAUDE.md に昇格）
- **外部プラグイン非依存**（良いパターンを自作で再実装）

## セットアップ（新端末）

```sh
git clone https://github.com/arkrtm/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

## 更新

```sh
~/dotfiles/update.sh
```

## 構成

| パス | 役割 | 配備方式 |
|---|---|---|
| `claude/` | `~/.claude/` の中身 | per-item symlink（`settings.json` のみ COPY） |
| `mise/config.toml` | `~/.config/mise/config.toml`（node/python/uv pin） | symlink |
| `claude-memory/` | cc-memory パッケージ（uv project） | 絶対パス参照（symlink しない） |
| `install.sh` / `update.sh` / `bootstrap.sh` | 配備 / 更新 / 新端末構築 | — |

## 同期しないもの（machine-local・非 commit）

記憶 DB（`~/.local/share/cc-memory/`）、`/learn` journal（`~/.local/state/cc-learn/`）、各 repo の `.workflow/` 進行状態、認証情報、transcript、`.venv`。

## 注意

- **Claude Code 本体はこのリポジトリで管理しない**（ユーザが手動更新）。
- `settings.json` はアプリが上書きするため symlink ではなく COPY。`/config` で変更したら repo に還元すること（`install.sh --check` が drift を検出）。
