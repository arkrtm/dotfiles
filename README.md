# dotfiles — Claude Code 環境

`~/dotfiles` を単一の真実 (single source of truth) として、Claude Code のカスタム環境を多端末で再現する repo。**auto mode** を既定にしつつ、要件→設計→TDD 実装→review→verify の開発ワークフローを hook と状態機械で hard-enforce し、ディレクトリ別の長期記憶 (cc-memory) と承認制の自己改善 (`/learn`) を足し、外部プラグインに頼らず良いパターンを自作で実装している。Python-first（`uv` / `ruff` / `pytest` / `pyright`、版は mise で pin）。

詳しい設計は [`docs/`](docs/) に分かれている — まず [`docs/architecture.md`](docs/architecture.md)（地図）から。

---

## セットアップ

**新端末（クローンから）:**

```sh
git clone https://github.com/arkrtm/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

`bootstrap.sh` は brew→base tools(jq/git/gitleaks)→mise→`install.sh`→pinned runtimes→pre-commit(secret-scan)→cc-memory→MCP 登録を順に行う。**Claude Code 本体は管理対象外**（自分でインストール/更新する）。完了後は新しいシェルを開いてから `install.sh --check`。

**既存端末（再配備のみ）:**

```sh
~/dotfiles/install.sh          # apply: content を symlink、settings.json を COPY、mise config を symlink
~/dotfiles/install.sh --check  # drift 検出（nonzero で drift あり）
```

---

## 機能ツアー

| 機能 | 何をするか | 詳細 |
|---|---|---|
| **auto mode** | `settings.json` の `defaultMode:"auto"`。許可済みコマンドを自動実行。hard な安全は `deny`/`ask` ルールと L3 hook だけ（`allow` は auto では事実上 no-op、OS サンドボックスは無い） | [`docs/architecture.md` §3](docs/architecture.md) |
| **強制ワークフロー** | `/spec`→`/approve-requirements`→branch→`/design`→`/approve-design`→`/tdd-implement`→`/verify`。`.workflow/state.json` の状態機械を PreToolUse / Stop / SubagentStop hook が門番。非自明な変更だけに適用、自明な変更は素通し | [`docs/workflow.md`](docs/workflow.md) |
| **cc-memory** | ディレクトリ別の検索可能な長期記憶（SQLite + FTS5）。MCP・CLI・SessionStart/End hook の 3 経路で同じ DB を読み書き。`/dream` で統合 | [`docs/memory.md`](docs/memory.md) |
| **`/learn`** | セッションの学習を **承認制**で skill / `CLAUDE.md` / deny ルールに昇格。auto-edit はせず必ず diff を見せて承認を取る。`~/dotfiles` にだけ書く（`~/.claude` には書かない） | [`docs/hooks.md`](docs/hooks.md)（learn hooks）+ [`claude/skills/learn/SKILL.md`](claude/skills/learn/SKILL.md) |
| **discipline skill** | `python-engineering-discipline` skill が作業規律の本体。**the ladder**（書く前に上から評価し最初に成立した段で止める: ①YAGNI ②既存を grep して再利用 ③stdlib ④言語/フレームワーク native や DB/ORM 制約 ⑤既存依存 ⑥1行 ⑦初めて最小実装）。subagent には `discipline_subagent.sh` が毎回注入 | [`claude/skills/python-engineering-discipline/SKILL.md`](claude/skills/python-engineering-discipline/SKILL.md) + [`docs/hooks.md`](docs/hooks.md) |

> **強制力の正直な整理**: anti-cheat（テスト削除・`skip`/`xfail` 沈黙の禁止、fake-green 無視）と green-gate（`verify-gate.sh`）は **hard**。pure な test-first の「順序」は advisory。Bash 系の文字列ガードは OS サンドボックスが無いため deterrent（難読化で回避余地あり）。詳細は [`docs/architecture.md` §3](docs/architecture.md) / [`docs/hooks.md`](docs/hooks.md)。

---

## 構成（ディレクトリマップ）

| パス | 役割 | 配備方式 |
|---|---|---|
| `claude/settings.json` | auto mode・deny/ask・全 hook 登録・statusLine | **COPY**（app が atomic-write するため） |
| `claude/{CLAUDE.md,statusline.sh,skills,agents,hooks,output-styles}` | `~/.claude/` 配下の中身 | per-item **symlink** |
| `claude/templates/` | 各 repo に手でコピーする `.pre-commit-config.yaml` | 配備されない |
| `mise/config.toml` | `~/.config/mise/config.toml`（node/python/uv pin） | **symlink** |
| `claude-memory/` | cc-memory パッケージ（uv project） | 絶対パス参照（symlink しない） |
| `bootstrap.sh` / `install.sh` / `update.sh` | 新端末構築 / 配備 / 更新 | — |

注釈付きの完全なツリーは [`docs/architecture.md` §4](docs/architecture.md)。

---

## よくある操作

| やりたいこと | 方法 |
|---|---|
| 環境を更新する | `~/dotfiles/update.sh`（drift precheck → `git pull --ff-only` → `install.sh apply` → mise install → cc-memory `uv sync`） |
| skill を追加する | `/learn` を実行（承認制で `~/dotfiles/claude/skills/` に書く）。**新規 top-level skill は Claude Code の再起動が必要** |
| deny/allow ルールを調整 | `claude/settings.json` の `permissions` を編集 → **`install.sh` を実行**（settings は COPY なので再配備が要る）。`/config` で live を変えた場合は逆に repo へ還元 |
| hook の env var を切替 | 永続化は `settings.json` の `env`、一時的にはシェル env。例: `CC_GATE_XDIST`（gate の pytest ワーカ数）、`WF_ARCHIVE=1`（verified 時に spec を archive）、`CC_COMPACT_DISABLE=1`（出力圧縮を全停止）。一覧は [`docs/hooks.md`](docs/hooks.md) の env 早見表 |
| 記憶を手動で扱う | `/remember <fact>` / `/recall <query>` / `/dream`（[`docs/memory.md`](docs/memory.md)） |

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| Edit/Write/Bash が常に止まる（`exit 2`） | deny ガード 4 本（`gate-prereq`/`branch-guard`/`tdd-guard`/`state-guard`）は **`jq` 欠落で fail-closed**。`command -v jq` を確認（`bootstrap.sh` step 2 が入れる）。hook は PATH を `/opt/homebrew/bin:/usr/local/bin:…` に固定するが、GUI 起動で痩せた PATH には注意 |
| `node`/`uv` 等が見つからない | `mise` の shim がシェル rc で activate されているか確認。`bootstrap.sh` 後は **新しいシェルを開く**。`uv` が PATH に無いと verify-gate は静かに no-op（fail-open） |
| settings.json の drift | `install.sh --check` が `live != repo` を検出。`update.sh` は pull 前にこれを走らせ警告する。live を勝たせたいなら repo の `claude/settings.json` にコピーしてから、不要なら `install.sh` で repo を勝たせる |
| mise が config を信頼しない | `mise trust ~/.config/mise/config.toml`（symlink は repo パスに解決される）。`bootstrap.sh` step 5 が両パスを trust する |
| cc-memory MCP が繋がらない | `claude mcp add --scope user cc-memory -- mise exec -- uv run --project ~/dotfiles/claude-memory cc-memory mcp` を再実行（`bootstrap.sh` step 9 と同じ）。診断は `cc-memory init`（`{db,fts,vec,load_extension}` を表示） |

---

## 同期しないもの（machine-local・**絶対に commit しない**）

| 種別 | 場所 |
|---|---|
| 記憶 DB (cc-memory) | `~/.local/share/cc-memory/` |
| `/learn` journal | `~/.local/state/cc-learn/` |
| workflow 進行状態 | 各 repo の `.workflow/`（`wf.sh init` が対象 repo の `.gitignore` に自動追加） |
| Claude Code 本体設定 | `~/.claude.json` |
| 認証情報 / transcript / `.venv` | 各所 |

二重ガード: ルート `.gitignore` が機密を hard-deny、`claude/.gitignore` は allowlist 方式（全無視→安全な拡張子だけ再許可→機密を最後に再 deny）。さらに `gitleaks` + `detect-private-key` の pre-commit secret-scan（このリポジトリ自身、ローカルゲート）。

この repo の中身を編集するとき（環境そのものを直すとき）は [`CLAUDE.md`](CLAUDE.md) を参照。
