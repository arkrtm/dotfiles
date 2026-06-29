# 長期記憶（cc-memory）

プロジェクト単位で「過去の決定・事実・手順」を検索可能な形で蓄える長期記憶レイヤー。実体は `~/dotfiles/claude-memory` の小さな Python パッケージ `cc_memory`（`sqlite` + `FTS5` バックエンド）で、CLI・MCP サーバ・SessionStart/SessionEnd フックの 3 経路から同じ DB を読み書きする。

- ソース: `claude-memory/cc_memory/{core,cli,mcp_server,__init__}.py`、`claude-memory/pyproject.toml`
- フック: `claude/hooks/memory_session_start.sh` / `memory_session_end.sh`
- スキル: `claude/skills/{recall,remember,dream}/SKILL.md`

> このドキュメントは「記憶」だけを扱う。フック登録や settings.json の連携は `./workflow.md` / `./hooks.md` を参照。

---

## データの保存場所

| 項目 | 値 |
|---|---|
| 既定 DB | `~/.local/share/cc-memory/memory.db`（`core.DEFAULT_DB`） |
| 上書き | 環境変数 `CC_MEMORY_DB`（`~` 展開あり / `core.db_path()`） |
| 同期 | **machine-local。リポジトリには絶対に入れない**（`memory.db`・認証・`.workflow` state と同じ扱い） |

`connect()` が親ディレクトリを自動作成し、`PRAGMA busy_timeout=3000` と `synchronous=NORMAL` を設定する（MCP とフックが同時に DB を触りうるため）。DB ファイル自体をコピーすればフルバックアップになる（後述の `export`/`import` は移行・選別用）。

---

## 記憶モデル

### スコープ（per-directory）

記憶は「スコープ」ごとに分離される。`resolve_scope()` は対象ディレクトリの **git トップレベル**（`git rev-parse --show-toplevel`、timeout 3s）を優先し、git 外なら `cwd` の絶対パスを使う。つまり同一リポジトリ内ならどのサブディレクトリで起動してもスコープは一致する。スコープ値はそのまま絶対パス文字列で、`memory_recall`/`memory_remember` に渡す `scope` と同じもの。

### 記憶の種類（`VALID_TYPES`）

| type | 意味 | 主な作られ方 |
|---|---|---|
| `episodic` | 出来事（このセッションで何をしたか） | SessionEnd の自動キャプチャ、手動 |
| `semantic` | 事実・規約 | `/remember`・MCP・`/dream` の昇格 |
| `procedural` | 手順・how-to | `/dream` で繰り返し手順を昇格 |

### スカラー属性

| 列 | 既定 | 役割 |
|---|---|---|
| `importance` | 0.5（MCP は 0.6） | 重要度。recall/digest スコアの重み |
| `confidence` | 0.6 | その内容への確信度（並び替えには未使用、選別の手がかり） |
| `frequency` | 1 | アクセス回数。**recall でヒットするたび +1**（よく使う記憶ほど浮上） |
| `last_accessed` | 作成時刻 | recall で更新。recency 減衰の基準 |
| `source` | `manual` | 由来（`manual`/`mcp`/`session-end`/`dream`/`reflect`/`import`） |
| `session_id` | NULL | SessionEnd の冪等キー |

### 忘却は可逆（no hard delete）

「忘れる」は物理削除ではなく **`memories` → `archive` テーブルへの移動**（`archive_memory()`：archive に INSERT してから元行を DELETE、単一トランザクション）。`restore_archived()` で元の `id` のまま復元できる。`/dream` の forget も restore も、この往復だけ。ハードデリート関数は存在しない。

---

## バックエンド：FTS5 と（任意の）ベクトル検索

- **常時**：`sqlite` + `FTS5`。`memories_fts`（`fts5(content, concepts, content='memories', content_rowid='id')`）が外部コンテンツ FTS として本体に追従する。INSERT/UPDATE/DELETE トリガ（`mem_ai`/`mem_au`/`mem_ad`）でインデックスを同期。
- **任意**：`sqlite-vec` + `fastembed`（`pyproject.toml` の `vec` extra、pre-v1 のため**ピン留め固定**）。有効化は次のコマンド。

```
uv sync --extra vec
```

`_maybe_load_vec()` は `import sqlite_vec` が通った時だけ `enable_load_extension(True)` → `load` → 即 `False` に戻す（拡張未導入の通常経路では `enable_load_extension` に一切触れない）。読み込めた場合だけ `memories_vec`（`vec0`、384 次元）を作る。

> **既定はベクトル OFF（FTS5 のみで出荷）。** さらに現状の実装では、`recall()` は FTS5（と substring フォールバック）しか引かず、`remember()` は埋め込みを書かない。`reindex()` のコメントどおり再埋め込みは「stub until fastembed wired」。`vec` extra を入れてもスキーマが用意されるだけで、**意味検索はまだ配線されていない**点に注意。

---

## recall のスコアリング

`recall(query, scope, limit=8, types=None)` の流れ。

1. **関連度（relevance）の取得**
   - クエリを単語に分解し `"t1" OR "t2" …` の FTS5 MATCH（`_fts_query`）。`bm25()` で上位 50 件、`relevance = -bm25`（bm25 は小さいほど良いので符号反転）。
   - FTS が 0 件なら **substring フォールバック**（`content LIKE '%query%'`、relevance 一律 0.3）。
2. **スコア合成**（候補ごと、`rel` はその回の最大値で正規化）

   ```
   score = 0.25*recency + 0.25*importance + 0.15*freq_sat + 0.35*relevance
   ```

   | 成分 | 重み | 定義 |
   |---|---|---|
   | `recency` | 0.25 | `exp(-(now - last_accessed) / (14*86400))`（時定数 τ = 14 日） |
   | `importance` | 0.25 | 記憶の `importance`（0–1） |
   | `freq_sat` | 0.15 | `frequency / (frequency + 3)`（飽和） |
   | `relevance` | 0.35 | 正規化した FTS/substring 関連度 |

3. スコア降順で `limit` 件を返し、**返した記憶の `last_accessed` を更新し `frequency` を +1**（=「思い出すと強化される」）。`types` を渡すと種別で絞り込み。`--all-scopes`（CLI）/ `scope` 空（MCP）で全スコープ横断。

`digest(scope, top=8)` は別ロジックで、クエリ非依存の「このプロジェクトの代表的記憶」を返す：`importance*0.5 + freq_sat*0.5` 降順 → `last_accessed` 降順。SessionStart の注入に使う。

---

## 3 つのアクセス経路

### 1. MCP ツール（モデルが自動で呼ぶ）

`cc_memory/mcp_server.py` が FastMCP の stdio サーバを立て、2 つのツールを公開する。

| ツール | 既定 | 説明 |
|---|---|---|
| `memory_recall(query, scope="", limit=8)` | scope 空→現在地のスコープ | スコア付き記憶を返す |
| `memory_remember(content, scope="", type="semantic", concepts, files, importance=0.6)` | `source="mcp"`、secret は reject | 不正な `type` は `{error}`、秘密検出時も `{error}` |

登録（user スコープ、mise 経由で uv を解決）：

```
claude mcp add --scope user cc-memory -- mise exec -- \
  uv run --project ~/dotfiles/claude-memory cc-memory mcp
```

SessionStart メッセージが「このプロジェクトの scope（絶対パス）」を明示するので、モデルはそれをそのまま `scope` に渡す運用。

### 2. 手動スキル `/recall` `/remember`（人が呼ぶ）

どちらも `disable-model-invocation: true` + `user-invocable: true`（モデルからは起動せず、ユーザーのみ）。MCP の手動コンパニオン。

- **`/recall <query>`**：`cc-memory recall` を実行してスコア付き結果を表示。スキル本文は「記憶は過去であって現在ではない。orient に使い、行動前に実コードを読め」と釘を刺す。
- **`/remember <fact>`**：argv のクオート/インジェクションを避けるため **stdin（heredoc）で内容を渡す**。先に `cc-memory scope` で scope を取得し、`--type`（semantic/procedural/episodic）を選んで保存、返った id を報告。秘密は意図的に拒否される。

### 3. SessionStart 注入 / SessionEnd キャプチャ（フック）

| フック | スクリプト | 動作 |
|---|---|---|
| SessionStart | `memory_session_start.sh` → `cc-memory hook session-start` | `digest`（top 8）を `additionalContext` として注入。各行 `- [type] content(160 字)`、末尾に「この scope を memory_recall/memory_remember に渡せ」という案内 + scope パスを付ける |
| SessionEnd（`/exit`） | `memory_session_end.sh` → `cc-memory hook session-end` | transcript を解析し、**1 件の低重要度 episodic** を保存。ログのみ（SessionEnd は block/inject 不可）、fail-open |

両スクリプトは `mise exec -- uv run`（無ければ素の `uv run`）に委譲する薄いシムで、`mise`/`uv` が無ければ `exit 0`（fail-open）。

SessionEnd の `ingest_transcript()` は JSONL を走査して `goal`（最初のユーザー発話）/ `files`（Edit/Write/MultiEdit/NotebookEdit の file_path）/ `commands`（Bash の先頭 120 字 ×最大 8）/ `outcome`（最後のアシスタント発話）を要約し、`importance=0.3, confidence=0.4, source="session-end"` で保存。ファイルもコマンドも無い空セッションは skip。`(session_id, source='session-end')` の**部分 UNIQUE インデックス**で冪等（同セッションの二重記録を防止、`session_id` が NULL のものは衝突させない）。この粗い episodic を後から `/dream` が磨く。

---

## `/dream`：記憶の統合（consolidation）

設計は **「CLI が候補を出す → セッションのモデルが推論する → CLI が適用する」** の 3 段。適用は単一トランザクション。

```
1. emit-candidates  cc-memory dream --emit-candidates   # 決定的
2. reason           モデルが operations JSON を生成
3. apply            cc-memory dream --apply -            # 決定的・1 トランザクション
```

**1. 候補抽出（`dream_emit`）**：`meta` の `last_dream:{scope}` 以降の `episodic` 全件と、既存の `semantic`/`procedural`（id/type/content/concepts）を返す。

**2. 推論（モデル）**：候補から `operations` JSON を組む。SKILL は「明らかに durable なものだけ。≥2 エピソードに跨る / 高確信度のバーを下回るものは捨てる。捏造しない」と保守的姿勢を要求。

| キー | 適用先 |
|---|---|
| `create_semantic` | `semantic` を新規作成（`source=dream`） |
| `create_procedural` | `procedural` を新規作成（`source=dream`、counts は `promoted`） |
| `reflections` | `semantic` を作成（`source=reflect`） |
| `consume_episodic_ids` | 取り込み済み episodic を**可逆 archive** |
| `archive_ids` | 陳腐・低価値を**可逆 archive** |

**3. 適用（`dream_apply`）**：`with conn:` の単一トランザクションで上記を実行し、`last_dream:{scope}` を更新。`/dream` の書き込みはすべて `secret_mode="mask"`（拒否ではなくマスク）。返り値は `{created, promoted, reflected, forgotten}`。forget は可逆なので `cc-memory restore --archive <id>` で戻せる。

---

## 秘密情報の扱い

`find_secrets(text)` が 2 系統を検出し、`guard_content(text, mode)` が処理する。

| 系統 | 検出 | 既定（`reject`）の挙動 | `mask` モードの挙動 |
|---|---|---|---|
| **structured** | `api_key/secret/token/password/client_secret/private_key` 代入、URL 埋め込み資格情報、`AKIA…`、`gh[pousr]_…`、`BEGIN … PRIVATE KEY`、`bearer …` | **保存拒否**（`ValueError`） | `«redacted-secret»` に置換 |
| **entropy** | 24 文字以上の高エントロピートークン（hex 24+ かつ Shannon>3.0、または Shannon>4.5） | 常に `«redacted»` でマスク | 同左 |

- **git-SHA 免除**：ちょうど 40 桁の hex はマスクしない（コミットハッシュを保護対象外に）。
- **秘密文字列をログに出さない**：structured ヒットはラベル `"structured-secret-pattern"` として記録し、実際の値は記録もエコーもしない。
- モード使い分け：手動 `remember`・MCP・`/recall` 経由は `reject`（拒否＝意図どおり）。SessionEnd キャプチャ・`/dream`・`import` は `mask`（落とさず無害化）。

これは正規表現ベースの**ヒューリスティック**であり、すべての秘密を捕捉する保証はない。あくまで「うっかり秘密を長期記憶に焼き付ける」事故を減らす deterrent として理解すること。

---

## CLI コマンド

エントリポイントは `cc-memory`（`pyproject.toml` の `[project.scripts]`）。実行は `mise exec -- uv run --project ~/dotfiles/claude-memory cc-memory <cmd>`。

| コマンド | 役割 |
|---|---|
| `init` | DB を初期化し `{db, fts, vec, load_extension}` を表示（環境診断にも使える） |
| `scope [--cwd DIR]` | 解決済みスコープ（絶対パス）を出力 |
| `remember [text] [--stdin/--file] --scope --type --concepts --files --importance --confidence --source` | 記憶を保存。秘密検出時は stderr に `refused:` を出し exit 2 |
| `recall <query> --scope --limit --type(複数可) --all-scopes` | スコア付き recall（JSON） |
| `digest --scope --top` | 代表的記憶の要約（JSON） |
| `dream --scope --emit-candidates \| --apply FILE` | 統合。`--apply -` で stdin から JSON |
| `export [--scope]` | scope 省略で**全スコープ**を JSONL ダンプ |
| `import [--file]` | JSONL を取り込み（`secret_mode=mask`） |
| `restore --archive <id>` | archive から記憶を復元 |
| `reindex` | FTS を rebuild（vec 再埋め込みは現状 stub） |
| `mcp` | MCP サーバを起動 |
| `hook {session-start,session-end}` | フックのエントリポイント |

---

## バックアップ・移行・復元

| 目的 | 手段 |
|---|---|
| フルバックアップ | `memory.db` ファイルをコピー（最も確実） |
| 選択的エクスポート | `cc-memory export [--scope <path>]` → JSONL（1 行 1 記憶） |
| インポート / 別マシン移行 | `cc-memory import --file dump.jsonl`（mask 適用、新規 id で再採番） |
| 個別の「忘却の取り消し」 | `cc-memory restore --archive <id>`（`/dream` が archive した id を戻す） |
| インデックス再構築 | `cc-memory reindex`（FTS 破損時など） |

> `export` は `archive` テーブルを含まない（`memories` のみ）。archive まで含めて保全したいときは DB ファイルごとコピーする。

---

## 動作環境・限界（正直なメモ）

- `requires-python >=3.12`、ランタイム依存は `mcp>=1.28,<2` のみ。`vec` extra は明示インストール時だけ。
- フックは fail-open：`mise`/`uv` が無くても、DB が壊れても、セッションを止めない（記憶機能が静かに無効化されるだけ）。
- 並行性は `busy_timeout=3000` + `synchronous=NORMAL` で緩和しているが、強い同時書き込み耐性は前提にしない。
- 意味検索（ベクトル）は**スキーマだけ存在し未配線**。現状の検索は FTS5 + substring フォールバックが実体。
- 秘密ガードは正規表現ヒューリスティックで、完全ではない（上述）。
