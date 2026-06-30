# architecture — システム全体像

`~/dotfiles` は Claude Code のカスタム環境を「単一の真実 (single source of truth)」として多端末で再現するための repo。
このドキュメントは最初に読む**地図**。各層の詳細は兄弟ドキュメント（`./workflow.md` / `./memory.md` / `./learn.md` / `./safety.md` / `./hooks.md` など）へ。

ソースの実体は `/Users/arkrithm/dotfiles`。本書の記述はすべてそこの実ファイルに基づく。

---

## 1. 5つの協調する層 (layers)

環境は独立した5層が重なってできている。各層は **deploy 方式・状態の置き場所・強制力** が異なる。

| 層 | 役割 | 実体 | 強制力 |
|---|---|---|---|
| **L1 sync / bootstrap** | 新端末構築・配備・更新・drift 検出 | `bootstrap.sh` / `install.sh` / `update.sh` / `mise/config.toml` | — (運用) |
| **L2 settings + philosophy** | 権限モード・hook 登録・北極星の心得 | `claude/settings.json` / `claude/CLAUDE.md` / `claude/skills/python-engineering-discipline/` | settings は hard、CLAUDE.md は advisory |
| **L3 workflow enforcement** | 要件→設計→実装(TDD)→review→verify を状態機械で hard-enforce | `claude/hooks/*` + `claude/hooks/lib/wf.sh` + `claude/skills/{spec,clarify,approve-*,design,tdd-implement,verify}` | **hard**（後述の anti-cheat / green-gate） |
| **L4 memory + context** | ディレクトリ別の長期記憶・workflow 状態の注入・出力圧縮 | `claude-memory/`（cc-memory パッケージ）+ `memory_*` / `workflow_session_start` / `context_compactor` hooks | advisory（注入のみ、block しない） |
| **L5 self-improvement** | セッション学習を承認制で skill / CLAUDE.md に昇格 | `claude/skills/{learn,dream}` + `learn_*` hooks + `session_analyzer.py` | advisory（**必ず承認制**、auto-edit しない） |

### 層の相互作用（1セッションの流れ）

```
SessionStart ─┬─ memory_session_start  (L4: この repo の記憶を注入)
              ├─ learn_session_start    (L5: 学習が溜まったら nudge)
              └─ workflow_session_start (L3: 現在 stage と「いま許されること」を注入)

   作業中  ── PreToolUse(Edit/Write) → gate-prereq / branch-guard / tdd-guard  (L3 hard)
           ── PreToolUse(Bash)        → state-guard                            (L3 hard)
           ── PostToolUse(Edit/Write) → autofix (ruff) / check-weak-tests      (L2/L3)
           ── PostToolUse(Bash)       → mark-red (赤/緑を記録)                  (L3)
           ── PostToolUse(Grep/Glob/Bash) → context_compactor                  (L4)

   subagent ── SubagentStart → discipline_subagent (L2 心得を注入)
            ── SubagentStop  → review-capture (L3: review.json を書く唯一の経路)

   Stop ──────→ verify-gate (L3: GREEN gate。reviewed のときだけ作動)

SessionEnd ─┬─ memory_session_end (L4: このセッションを1記憶に)
            └─ learn_session_end  (L5: journal に1行追記)
```

ポイント：
- **L3 だけが block する。** L4/L5 は `additionalContext` での注入・ログのみで、決して作業を止めない（fail-open）。
- workflow 状態 (`.workflow/state.json`) は **L3 が単独で所有**。L4 の `workflow_session_start` はそれを*読んで*注入するだけ。
- L2 の `CLAUDE.md` と discipline skill は心得（advisory）。実際に強制するのは L3 の hook と、L2 の `settings.json` の `deny`/`ask`。

---

## 2. SYNC MODEL — 3クラスの配備

`install.sh` が repo を live (`~/.claude` / `~/.config/mise`) に配備する。**配備方式は3クラスに分かれる**（`install.sh` 冒頭コメント、`README.md` 構成表が根拠）。

| クラス | 対象 | 方式 | 理由 |
|---|---|---|---|
| **content** | `CLAUDE.md` `statusline.sh` `skills/` `agents/` `hooks/` `output-styles/` | **per-item symlink** (`ln -sfn`) | repo を編集すれば即 live に反映。`install.sh` の `CONTENT_ITEMS` がこの集合 |
| **settings.json** | `claude/settings.json` → `~/.claude/settings.json` | **COPY** (`cp`) | アプリが `/config` 等で**原子的に上書き (atomic-write)** するため。symlink だと detach される |
| **mise config** | `mise/config.toml` → `~/.config/mise/config.toml` | **symlink** | mise はその場で書き換えるので symlink で問題ない |

補足：
- `claude-memory/` は **symlink しない**。MCP 登録・hook から**絶対パス参照**（`$HOME/dotfiles/claude-memory`）される uv project。
- `claude/templates/` は `CONTENT_ITEMS` に含まれず**配備されない**。repo 内テンプレ（各 repo に手でコピーする `.pre-commit-config.yaml`）。
- settings.json が COPY なので **drift が起きうる**。`/config` で live を変えたら repo に還元する必要がある。`install.sh --check`（`update.sh` が pull 前に実行）が `live != repo` を検出して警告し、repo を勝たせる。

### machine-local（同期しない・**絶対に commit しない**）

リポジトリには入れず、各端末で生成・保持されるもの：

| 種別 | 場所 |
|---|---|
| 記憶 DB (cc-memory) | `~/.local/share/cc-memory/` |
| `/learn` journal | `~/.local/state/cc-learn/` |
| workflow 進行状態 | 各 repo の `.workflow/`（`wf.sh init` が対象 repo の `.gitignore` に自動追加） |
| Claude Code 本体設定 | `~/.claude.json` |
| 認証情報 / transcript / `.venv` | 各所 |

二重ガード：
- ルート `.gitignore` が `**/.claude.json` `**/.credentials.json` `**/*.local.json` `.env*` `*.pem` `id_rsa*` を hard-deny。
- `claude/.gitignore` は **「全部無視 → 安全な拡張子だけ再許可 (`*.md *.py *.sh *.yaml *.yml` + `settings.json`) → 機密を最後に再 deny」** という allowlist 方式。vendored script は `.sh`/`.py` で終わらないと commit されない。
- `bootstrap.sh` が `gitleaks` + `detect-private-key` の **pre-commit secret-scan**（この dotfiles repo 自身。CI は無し、ローカルゲートのみ）を仕込む。

---

## 3. auto-mode の SAFETY MODEL

`settings.json` の `permissions.defaultMode` は **`"auto"`**（literal）。これが既定の安全モデルを規定する。

**hard な保証は2つだけ：**

1. **`deny` / `ask` ルール**（`settings.json`）— auto mode でも常に効く。
   現在の `deny`：機密の読取（`.env*` / `~/.ssh` / `~/.aws` / `~/.config/gh` / `*.pem` / `id_rsa*`）、破壊的 git（`git push --force*` / `git reset --hard*` / `git clean -fd*`）、カバレッジを潰す pytest（`pytest * --no-cov*`）。
2. **決定論的 hook**（L3）— 文字列の許可ではなく **stage / state / 識別子**で判定し、`permissionDecision:"deny"` や Stop の `decision:"block"` を返す。これが workflow の本当の壁。

**重要な含意：**

- **auto では `allow` ルールは「落ちる」。** auto mode は許可済みコマンドを自動実行する前提なので、`allow` リスト（`uv run pytest` 等）は事実上 no-op になりうる。安全を担保しているのは `allow` ではなく **`deny`/`ask` と hook**。`allow` は他モード／可読性のためのもの。
- **OS サンドボックスは無い。** ゆえに Bash 系ガード（`state-guard.sh` の文字列マッチ等）は **deterrent（抑止）であって airtight ではない**。`state-guard.sh` 自身が明記：`base64|sh` や `eval` による難読化は文字列ガードを抜けうる。事故的・「親切心」由来のバイパスのハードルを上げるのが目的で、敵対者を止める保証ではない。
- 一方、**hook 経由の hard なものは本物**：
  - **anti-cheat（強）** — `tdd-guard.sh` は test 削除・`skip`/`xfail`/`collect_ignore` 追加を block し、production `.py` 編集前に**記録された失敗テスト**(`.workflow/red.json`)を要求。`mark-red.sh` は**絞り込み実行 (`-k`/`-x`/`--lf`) の GREEN を信用しない**（偽 green 防止）。`check-weak-tests.py` は無アサーション/トートロジーなテストを AST で検出。
  - **green-gate（強）** — `verify-gate.sh`（Stop hook, state==`reviewed` のみ作動）が full pytest + ruff + pyright + diff-cover ≥90% を通って初めて `verified` を刻む。**3連続 red で last green checkpoint へ auto-rollback**（壊れた WIP は `rescue/*` へ退避）。
  - **review の偽造不可** — `review-capture.sh` は `implementing→reviewed` を進める唯一の経路で、SubagentStop 上で**権限系の外**で走り、`adversarial-reviewer` という identity を fail-closed で確認する。Bash/Edit からは forge できない。
- **対して「pure な test-first」は advisory。** 「実装の前に必ずテストを書く」という TDD の精神は心得（CLAUDE.md / `tdd-implement` skill）止まりで、強制されるのは **anti-cheat（テストを消すな・偽 green を作るな）** と **green-gate（最終的に緑であれ）** の部分。

**fail-closed vs fail-open：** L3 のゲート（`gate-prereq` / `branch-guard` / `tdd-guard` / `state-guard`）は `jq` が無ければ `exit 2` で**閉じる (fail-closed)**。記録・注入系（`mark-red` / `autofix` / `memory_*` / `workflow_session_start` / `verify-gate` の jq/uv 欠如時）は**開く (fail-open)**＝環境が欠けても作業を止めない。

**escape hatch：** workflow が未 init（`state=none`）の repo では L3 ゲートは素通り（typo・1行修正のための逃げ道）。緑のままの refactor は `touch .workflow/allow-refactor`（1サイクル限り）で `tdd-guard` を通す。

詳細な stage 遷移と各ゲートの条件は `./workflow.md` を参照。

---

## 4. ディレクトリツリー（注釈付き）

```
~/dotfiles/
├── README.md                     概要（日本語）。構成表 = sync の権威
├── bootstrap.sh                  新端末: brew→mise→install→runtimes→pre-commit→cc-memory→MCP登録
├── install.sh                    配備本体。apply / --check(drift検出)。CONTENT_ITEMS / COPY / symlink
├── update.sh                     drift precheck → git pull --ff-only → install apply → mise → cc-memory sync
├── .gitignore                    ルート hard-deny（機密・cc-memory data/.venv・mise local override）
├── .pre-commit-config.yaml       この repo 自身の secret-scan（gitleaks + detect-private-key、SCAN専用）
│
├── mise/
│   └── config.toml               node/python/uv の宣言的 pin（curl|bash を避ける）。~/.config/mise に symlink
│
├── claude-memory/                cc-memory: per-dir 長期記憶（sqlite FTS5 + 任意の semantic vec）。symlinkせず絶対参照
│   ├── pyproject.toml            uv project。scripts: cc-memory。ruff/pyright strict
│   ├── uv.lock
│   └── cc_memory/
│       ├── cli.py                init/reindex/mcp/scope/remember/recall/digest/dream/export/import/restore/hook
│       ├── core.py               記憶のコア（保存・検索・scope 解決・dream 整理）
│       └── mcp_server.py         memory_remember / memory_recall を出す MCP server
│
└── claude/                       → 各項目が ~/.claude/ に配備される（settings.json のみ COPY）
    ├── .gitignore                allowlist 方式（全無視→安全拡張子だけ許可→機密を最後に deny）
    ├── settings.json             【COPY】auto mode・deny/ask・全 hook 登録・statusLine
    ├── CLAUDE.md                 【symlink】北極星の心得（advisory）。詳細は discipline skill へ委譲
    ├── statusline.sh             【symlink】model / effort / dir / context% / branch / venv を1行表示
    │
    ├── hooks/                    【symlink】L3/L4/L5 の決定論的フック群
    │   ├── lib/
    │   │   ├── wf.sh             ★ workflow 状態機械（state.json の唯一の権威。rank -1..6）
    │   │   ├── status.sh         stage と「いま許されること」を1行化（SessionStart 注入用）
    │   │   ├── next-task.sh      PLAN.md から次タスクを抽出
    │   │   └── pyrun.sh          pytest/ruff の起動を uv 経由で正規化
    │   ├── gate-prereq.sh        PreToolUse(Edit/Write): stage 順序 + .workflow/ 保護 (hard, fail-closed)
    │   ├── branch-guard.sh       PreToolUse(Edit/Write): main/master での code 編集を block (hard)
    │   ├── tdd-guard.sh          PreToolUse(Edit/Write): TDD anti-cheat（赤テスト要求・silencing 禁止）(hard)
    │   ├── state-guard.sh        PreToolUse(Bash): wf.sh mutator 偽造 / Bash 経由の code 書込を block (hard)
    │   ├── autofix.sh            PostToolUse(Edit/Write): ruff check --fix + format (advisory)
    │   ├── check-weak-tests.py   PostToolUse + pre-commit: 弱いテストを AST 検出（hook=advisory / pre-commit=hard）
    │   ├── mark-red.sh           PostToolUse(Bash): pytest の赤/緑を red.json に記録（絞込 green は無視）
    │   ├── verify-gate.sh        ★ Stop: GREEN gate（full test+ruff+pyright+diff-cover、3赤で rollback）(hard)
    │   ├── review-capture.sh     SubagentStop: review.json を書く唯一の経路。adversarial-reviewer のみ (hard)
    │   ├── discipline_subagent.sh SubagentStart: 心得を subagent に注入（CLAUDE.md を継承しないため）
    │   ├── workflow_session_start.sh SessionStart: 現 stage を注入 (advisory, fail-open)
    │   ├── memory_session_start.sh   SessionStart: この repo の記憶を注入（cc-memory shim）
    │   ├── memory_session_end.sh     SessionEnd: セッションを1記憶として保存
    │   ├── learn_session_start.sh    SessionStart: 学習が溜まったら nudge
    │   ├── learn_session_end.sh      SessionEnd: journal に1行追記
    │   └── context_compactor.py      PostToolUse(Grep/Glob/Bash): 巨大出力を保守的に圧縮（>=25%節約時のみ）
    │
    ├── skills/                   【symlink】model-/user-invocable な手順
    │   ├── spec/                 GATE1準備: 要件収集→REQUIREMENTS.md(EARS)
    │   ├── clarify/              要件の曖昧さを requirements-analyst で洗い出し解消
    │   ├── approve-requirements/ GATE1: EARS 検証して requirements_approved を刻む（model 起動不可）
    │   ├── design/               GATE2準備: DESIGN.md + PLAN.md
    │   ├── approve-design/       GATE2: placeholder無し・要件→task 追跡・(test)/(verify) を検証
    │   ├── tdd-implement/        承認後の TDD 実装（red→green→refactor）
    │   ├── verify/               full test+lint+type+diff-cover → review
    │   ├── recall/ remember/     cc-memory の手動 companion（自動 MCP の手動版）
    │   ├── dream/                記憶の整理（dedup・episodic→semantic 昇格・忘却）
    │   ├── learn/                セッション学習を承認制で skill/CLAUDE.md に昇格（+ session_analyzer.py）
    │   ├── map/                  repo の Python シンボルマップ（+ repo_map.py）
    │   └── python-engineering-discipline/  作業規律の本体（必要時に自動展開、+ examples.md）
    │
    ├── agents/                   【symlink】fresh-context な read-only subagent
    │   ├── adversarial-reviewer.md   diff を REQUIREMENTS/PLAN 照合（review-capture が identity 確認）
    │   └── requirements-analyst.md   要件の曖昧さ/欠落/エラーケースを指摘
    │
    └── templates/                ※配備されない repo 内テンプレ
        └── .pre-commit-config.yaml  各 repo にコピーするローカル品質ゲート（ruff/pyright/weak-tests/gitleaks）
```

★ = 状態機械の中核（`wf.sh`）と最終ゲート（`verify-gate.sh`）。この2つを押さえると L3 の全体像が掴める。

---

## 関連ドキュメント

- workflow の stage 遷移と各ゲート: `./workflow.md`
- cc-memory（保存・検索・scope・dream）: `./memory.md`
- `/learn` の自己改善ループ: `./learn.md`
- 権限・hook・fail-closed/open の安全設計: `./safety.md`
