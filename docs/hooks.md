# Hooks リファレンス

このリポジトリの hooks は `claude/settings.json` の `hooks` ブロックで登録され、
`~/.claude/hooks/` にデプロイされた実体（`$HOME/.claude/hooks/*.sh` / `*.py`）を実行する。
本書はそのすべてを「何を本当にやるか」で記述する。状態機械そのものの詳細は
[./workflow.md](./workflow.md)、記憶系は [./memory.md](./memory.md)、`/learn` コマンド本体は
[../claude/skills/learn/SKILL.md](../claude/skills/learn/SKILL.md) を参照（本書は learn hooks を含むフックの挙動・契約・限界に集中する）。

> ソース: `claude/settings.json`（hooks ブロック）, `claude/hooks/` 配下の全スクリプト。

---

## 全フックを貫く不変条件（必読）

- **既定は fail-open。** どのフックも自身の不具合（依存欠落・パースエラー・タイムアウト）で
  通常作業をブロックしない。session 系・recorder 系・autofix・compactor はすべて
  問題があれば黙って `exit 0` する。
- **例外: 決定論的 deny ガード 4 本は `jq` 欠落時に fail-CLOSED。**
  `gate-prereq.sh` / `branch-guard.sh` / `tdd-guard.sh` / `state-guard.sh` は
  `command -v jq || { ...; exit 2; }` を持ち、`jq` が `PATH` に無いと **exit 2 でツール呼び出しを止める**。
  「ガードが機能しないなら通さない」という設計。
  一方 Stop の `verify-gate.sh` は同じく `jq`/`uv` に依存するが、欠落時は `exit 0`（fail-open）。
- **deny は exit code ではなく JSON。** 通常の拒否は
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":...}}`
  を stdout に出して **`exit 0`**。`exit 2` は上記 fail-closed 経路だけ。Stop の拒否は
  `{"decision":"block","reason":...}`。
- **engaged-only。** ワークフロー系ガードは `.workflow/state.json` の状態が `none`
  （= このリポジトリでワークフロー未開始）なら素通しする。軽微な変更の逃げ道。
- **PATH 固定。** deny 系・recorder 系は先頭で
  `export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"` を行い、
  GUI 起動などで PATH が痩せていても `jq`/`git`/`uv` を見つけられるようにしている。
- **限界（正直に）。** OS サンドボックスが無いため、Bash の文字列ガード（`state-guard.sh`）は
  `base64|sh` や `eval` 等の難読化で理論上回避可能で、悪意ある回避ではなく
  「うっかり/親切による迂回」を止める抑止力。これに対し **anti-cheat（テスト沈黙の禁止・
  fake-green 無視）と green-gate（`verify-gate.sh`）は hard**。
  純粋な test-first（赤を先に書く順序）は advisory に近く、強制されるのは
  「赤の記録が無いと production コードを触れない」という結果側の不変条件。

---

## 登録フック一覧

| Event | Matcher | File | 役割（1行） | 強制 | Env toggle | timeout |
|---|---|---|---|---|---|---|
| SessionStart | `startup\|resume\|clear\|compact` | `memory_session_start.sh` | このリポジトリ関連の長期記憶を注入 | advisory | `CC_MEMORY_DB` | 15s |
| SessionStart | 〃 | `learn_session_start.sh` | `/learn` 未実施が溜まった時の軽い nudge | advisory | `CC_LEARN_HOME` | 15s |
| SessionStart | 〃 | `workflow_session_start.sh` | 現在ステージ・次タスク・許可事項を注入 | advisory | — | 10s |
| SessionEnd | （なし） | `memory_session_end.sh` | セッションを1件の episodic memory として記録 | advisory(log) | `CC_MEMORY_DB` | 20s |
| SessionEnd | （なし） | `learn_session_end.sh` | learn journal に1行ダイジェスト追記 | advisory(log) | `CC_LEARN_HOME` | 15s |
| PreToolUse | `Edit\|MultiEdit\|Write` | `gate-prereq.sh` | ステージ順の強制 + `.workflow/` 保護 | **hard** (fail-closed) | — | 10s |
| PreToolUse | 〃 | `branch-guard.sh` | engaged 時 main/master 上のコード編集を拒否 | **hard** (fail-closed) | — | 10s |
| PreToolUse | 〃 | `tdd-guard.sh` | TDD anti-cheat（赤の記録必須 / テスト沈黙禁止） | **hard** (fail-closed) | — | 15s |
| PreToolUse | `Bash` | `state-guard.sh` | Bash 経由の状態偽造・コード書き込みを拒否 | **hard** (fail-closed) | — | 10s |
| PostToolUse | `Edit\|MultiEdit\|Write` | `autofix.sh` | 編集後の `.py` に ruff `check --fix` + `format` | advisory(fix) | — | 30s |
| PostToolUse | 〃 | `check-weak-tests.py` | 無 assert / 定数 assert のテストを警告 | advisory | — | 10s |
| PostToolUse | `Bash` | `mark-red.sh` | pytest の赤/緑を `.workflow/red.json` に記録 | advisory(recorder) | — | 30s |
| PostToolUse | `Grep\|Glob\|Bash` | `context_compactor.py` | 巨大なツール出力を保守的に圧縮 | advisory | `CC_COMPACT_*` | 10s |
| SubagentStart | （なし） | `discipline_subagent.sh` | エンジニアリング規律を subagent に注入 | advisory | — | 10s |
| SubagentStop | （なし） | `review-capture.sh` | adversarial-reviewer の評定を捕捉し reviewed へ | **hard** | — | 15s |
| Stop | （なし） | `verify-gate.sh` | green gate（full pytest+ruff+pyright+diff-cover） | **hard** | `CC_GATE_XDIST`, `WF_ARCHIVE` | 600s |

> `settings.json` の matcher は `Edit\|MultiEdit\|Write` を含むが、`tdd-guard.sh` /
> `branch-guard.sh` などのコメントは "Edit|Write" とだけ書く。実際は MultiEdit にも適用される
> （matcher が登録のソース・オブ・トゥルース）。`workflow_session_start.sh` のヘッダは
> `startup|resume` と書くが、登録 matcher は `startup|resume|clear|compact`。

---

## ワークフロー・ガード群

`.workflow/state.json` を単一の真実とする状態機械の門番。ランク順序は
`none(-1) → idle(0) → requirements_approved(1) → branched(2) → design_approved(3) →
implementing(4) → reviewed(5) → verified(6)`（[./workflow.md](./workflow.md) 参照）。
共有ロジックは `lib/wf.sh`、4 本の deny ガードはこれを `get`/`rank`/`normalize` で読むだけ。

### gate-prereq.sh — ステージ順の強制（PreToolUse Edit/Write）
- `state=none` なら素通し（軽微変更の逃げ道）。それ以外で `wf.sh normalize` を呼び、
  feature ブランチ上なら `requirements_approved → branched` に昇格させてから判定。
- **`.workflow/` 直接編集を拒否**: ファイルの物理パス（`pwd -P`）で判定し、`./`・`../`・
  symlink prefix での回避を封じる。
- 必要ランク `min` をパス種別で決める: `*.md`(docs)=0、`DESIGN.md`/`PLAN.md`=2、
  `*.py` および他のコード=3。`docs/` 下の `.py` も gate 対象（ドキュメント名で逃がさない）。
- ランク不足なら deny。代表メッセージ: 「Production code is blocked until design is approved.」

### branch-guard.sh — default ブランチでのコード編集禁止（PreToolUse Edit/Write）
- engaged 時のみ。現在ブランチが `main`/`master` 以外なら素通し。
- 編集対象が `*.md` / `docs/*` / `.workflow/*` なら許可（計画ドキュメントは default 上でも可）。
- それ以外（=コード）を default ブランチで編集しようとすると deny:
  「Create a feature branch: git switch -c feat/<slug>.」

### tdd-guard.sh — TDD anti-cheat（PreToolUse Edit/Write, rank>=3 のみ）
- **テストファイル**（`tests/**`, `test_*.py`, `*_test.py`）に対して:
  - `@pytest.mark.skip|xfail` / `pytest.skip(` / `collect_ignore` を **新規追加**する編集を拒否
    （旧文字列に無く新文字列に有る場合のみ＝沈黙化の防止）。
  - `def test` の個数が減る編集（=テスト削除）を拒否。
  - それ以外のテスト書き換え・修復は許可（red-first を妨げない）。
- **production `.py`** に対して: `.workflow/red.json` に **失敗テストの記録が無いと編集を拒否**。
  - 純粋な green リファクタの逃げ道: `touch .workflow/allow-refactor`（このフックが存在を見て素通し。
    このハッチは `verify-gate.sh` の緑成立で**毎サイクル削除**される ＝ 永続化しない）。
  - `fix/*` ブランチでは、production を触る前に `tests/` 配下に再現テストを追加していること
    （`git diff --name-only HEAD` に `^tests/`）を要求（回帰テスト先行 G-REG-1）。
- PostToolUse ではブロックできないため **必ず PreToolUse**。

### state-guard.sh — Bash 経由の迂回封じ（PreToolUse Bash）
- `wf.sh` の mutator（`set|init|approve-*|implementing|reviewed|to_reviewed|verified`）を
  Bash 経由で呼ぶのを拒否（状態の偽造防止）。状態遷移は skill 側の `!cmd` 前処理経由のみ許す設計。
- 各種書き込み動詞（`>`/`>>`/`tee`/`cp`/`mv`/`install`/`dd`/`ln`/`sed -i`/`python`/`jq`/`printf`/`echo`）で
  `.workflow/` に書くのを拒否。
- engaged 時は、Bash でコードファイル（`.py|.pyi|.toml|.cfg|.ini`）へ書き込む（リダイレクト・
  `sed -i`・`open(...,"w")`・`.write_text(`・`os.replace(`・`shutil.move/copy`）のを拒否
  → Edit/Write ツール経由を強制し、上記 3 ガードを迂回させない。
  ただし `*/tmp/*`・`*scratchpad*`・`.workflow/*`（前段で処理）は除外。
- **限界**: 文字列マッチのため難読化（`base64|sh`, `eval`）で理論上回避可。ヘッダ自身が
  「a determined obfuscation can still evade — raises the bar against accidental bypasses」と明記。

### mark-red.sh — pytest 赤/緑レコーダ（PostToolUse Bash, advisory）
- コマンドが pytest 呼び出しでなければ何もしない。
- **clean な呼び出しのみ信用**: `;`・`&&`・`||`・`|`・`` ` ``・`$(`・`>`・`echo` を含むコマンドは
  出力偽造の恐れがあるため **何も記録しない**（plain な pytest を要求 / HIGH 2）。
- 出力をパースし、`FAILED <nodeid>` を抽出。判定: `N failed` / `ERROR` / `errors during collection`
  があれば fail、なければ pass。
- **非対称**: narrowed 実行（`-k`/`-x`/`--lf`/`--ff`/`--testmon`）は **RED の nodeid だけ記録**し
  （red-first を高速化）、その **GREEN は無視**（fake-green 防止）。authoritative な GREEN は
  無制限実行のみが記録（`{failing:[],narrowed:false,green:true}`）。
- 書き込み先は `.workflow/red.json`。`updatedToolOutput` は返さない（純粋な記録係、fail-open）。
  この `red.json` を `tdd-guard.sh` が読む。

### verify-gate.sh — green gate（Stop hook, hard, timeout 600s）
- `state == reviewed` のときだけ作動（`verified` 後は素通し）。`uv` 必須、無ければ `exit 0`。
- **Phase 1（安価な赤）**: `pytest --lf -x -q`。直近失敗が残っていれば末尾 40 行を添えて block。
- **Phase 2（authoritative green）**: 全部緑のときだけ `verified` を刻む。
  1. `pytest -n ${CC_GATE_XDIST:-auto} --cov --cov-branch --cov-report=xml`
  2. `ruff format --check .`
  3. `ruff check .`
  4. `uvx pyright`
  5. `diff-cover coverage.xml --compare-branch <merge-base> --fail-under 90`
- 全緑なら: `.workflow/repair.n` を 0 に、`allow-refactor` を削除、**green checkpoint** を作成
  （`git add -A` → `gitleaks protect --staged` で秘密混入を検査、見つかれば block →
  `git commit --no-verify` + `git tag -f green-<branch>`）、`wf.sh verified`。
- 赤なら `.workflow/repair.n` をインクリメント。**3 連続赤で auto-rollback**:
  per-branch tag `green-<branch>` が存在し HEAD の祖先である時のみ、壊れた WIP を
  `rescue/<ts>-<pid>` に退避コミットし、元ブランチを `git reset --hard green-<branch>` で
  直近 green へ戻す。アンカーが無ければループ回避のため諦めて `exit 0`（stderr に要約）。
- カウンタ `repair.n` が唯一のループ・ブレーカ。`CC_GATE_XDIST` でワーカ数、`WF_ARCHIVE=1` で
  verified 時に `REQUIREMENTS/DESIGN/PLAN.md` を `.workflow/archive/<date>-<slug>/` へ複製。

### review-capture.sh — レビュー評定の捕捉（SubagentStop, hard）
- **`.workflow/review.json` の唯一の writer**であり、`implementing(4) → reviewed(5)` への唯一の経路。
  permission system の外で動くので、main agent / Bash / Edit からは偽造できない。
- subagent の identity が **`adversarial-reviewer` でなければ即 `exit 0`**（fail-CLOSED on identity、
  transcript-grep フォールバック無し ＝ どの subagent も marker を印字して詐称できない / HIGH 3）。
- transcript JSONL から assistant の text を `jq` でデコードしてから
  `<REVIEW_VERDICT>...</REVIEW_VERDICT>` を抽出（marker が JSON 文字列値の中にあり quote が
  escape されているため、生 grep ではなくデコードが必須 / HIGH 4）。
- 評定 JSON を `review.json` に書き、`verdict == pass` なら `wf.sh to_reviewed` を呼ぶ
  （`to_reviewed` 側でも再検証）。

---

## lib/ ヘルパ（フックではなく共有ロジック）

| File | 役割 |
|---|---|
| `lib/wf.sh` | 状態機械の本体。`get/rank/normalize/require <n>` は読み取り、`set/init/approve-requirements/approve-design/implementing/reviewed/verified` は mutator。mutator は skill の `!cmd` 経由のみ想定で、`state-guard.sh` が Bash 直叩きを拒否。`approve-requirements` は EARS 記法（`### R<n>:` と `R<n>.<m> WHEN/IF/WHILE/WHERE ... SHALL`）と未解決 `[NEEDS CLARIFICATION]` 不在を検証。`approve-design` は `PLAN.md` のプレースホルダ不在・全要件のタスク被覆・各タスクの `(test)`/`(verify)` 埋め込みを検証。`verified` で `WF_ARCHIVE=1` ならアーカイブ複製。 |
| `lib/status.sh` | 現在のステージ・ブランチ・`PLAN.md` のタスク進捗・次タスク・「今できること」を1行で。read-only / advisory。`workflow_session_start.sh` が利用。 |
| `lib/next-task.sh` | `PLAN.md` から「依存がすべて完了済みの未チェックタスク」の id を1つ印字。read-only。 |
| `lib/pyrun.sh` | Python ツールの実行 prefix を返す。uv プロジェクト内（`pyproject.toml`/`uv.lock` 有）なら `uv run --no-sync <tool>`、外なら `uvx <tool>`。`autofix.sh`/`verify-gate.sh` が利用。 |

---

## autofix（PostToolUse Edit/Write）— `autofix.sh`
- 編集対象が実在する `*.py` のときだけ作動。プロジェクトルートで（`CLAUDE_PROJECT_DIR`）
  `ruff check --fix <file>` → `ruff format <file>` を実行（pre-commit と同じ設定が効くように）。
- ツール実行 prefix は `lib/pyrun.sh`（uv プロジェクト内は `uv run --no-sync ruff`）。
- PostToolUse は編集を巻き戻せないため、`additionalContext` で
  「ruff auto-fixed and formatted … Re-read it before editing again.」と通知するだけ。
  hard な床は `verify-gate.sh` の `ruff format --check` / `ruff check`。fail-open。

## check-weak-tests（PostToolUse Edit/Write）— `check-weak-tests.py`
- `uv run --script`（PEP 723, requires-python>=3.10）。AST でテスト関数を走査。
- **弱いテスト**を検出: (1) `assert` も `pytest.raises` も `assert*` 呼び出しも無い `test*` 関数、
  (2) 定数を assert している（`assert True` 等のトートロジー）。
- **2 モード**:
  - stdin（PostToolUse）: 編集されたテストファイルについて `additionalContext` で **advisory 警告**。
  - `files <a.py> ...`（pre-commit ゲート）: 所見を stderr に出し、あれば **exit 1（HARD）**。
- フックとして使うのは前者。後者は同じスクリプトを pre-commit から呼ぶ hard 経路。

## context_compactor（PostToolUse Grep/Glob/Bash）— `context_compactor.py`
- 巨大なツール出力を**保守的に**圧縮してコンテキストを節約。**plain string の `tool_response`
  のみ**対象（構造化出力・画像は触らない）。**>=25% 削れる時だけ** `updatedToolOutput` を返すので、
  ファイル内容など model が依存する正確な出力を壊さない。
- トリガ: `CC_COMPACT_CHARS`(既定 12000) 文字 または `CC_COMPACT_LINES`(240) 行超。
  失敗出力（Traceback / `=== FAILURES ===` / `N failed` / `AssertionError`）は **4倍閾値**で
  ほぼ逐語的に温存。
- 圧縮手法: 完全重複行の畳み込み → （`CC_COMPACT_SIMILAR=1` 時のみ）数値・hex・タイムスタンプを
  正規化した類似行畳み込み → head/tail（既定 `CC_COMPACT_HEAD`=120 / `CC_COMPACT_TAIL`=60）。
  JSON 出力は形状サマリ（`CC_COMPACT_JSON_SAMPLE`=6 件）に。1 行巨大出力は先頭 800 + 末尾 200 字。
- kill switch: `CC_COMPACT_DISABLE=1`（全停止）、`CC_COMPACT_SKIP_TOOLS=Bash,Grep`（ツール除外）、
  `CC_COMPACT_ENABLE_READ=1`（Read も対象に＝既定は Read を圧縮しない）。fail-open。

## memory_session_start / _end — `memory_session_start.sh` / `memory_session_end.sh`
- いずれも `~/dotfiles/claude-memory`（`cc-memory` パッケージ）への薄いシム。`mise exec -- uv run`
  優先、無ければ `uv run`、どちらも無ければ `exit 0`。
- **start (SessionStart)**: `cc-memory hook session-start` を exec し、このプロジェクト関連の
  長期記憶＋解決済みスコープパスを注入。
- **end (SessionEnd)**: `cc-memory hook session-end` を exec し、セッションを 1 件の
  低重要度 episodic memory（files/commands/goal/outcome）として決定論的に記録（`/dream` が後で精錬）。
  SessionEnd は block/inject 不可なので logging-only。
- データは機械ローカルの SQLite `$CC_MEMORY_DB`（既定 `~/.local/share/cc-memory/memory.db`）。
  repo には絶対に入れない。詳細は [./memory.md](./memory.md)。

## learn_session_start / _end — `learn_session_start.sh` / `learn_session_end.sh`
- 共有スクリプト `claude/skills/learn/session_analyzer.py`（`python3` 直叩き）。
- **start**: `session_analyzer.py nudge` の出力があれば `additionalContext` で注入
  （多数セッション/反復修正が前回 `/learn` 以降に溜まった時の **gentle nudge**。自動編集はしない）。
- **end**: `session_analyzer.py journal` を実行し、scrub 済み 1 行ダイジェスト
  （session id, cwd, #corrections, #files）を learn journal に追記。クロスセッションの再発を
  `/learn` が拾えるようにする。logging-only。
- データは `$CC_LEARN_HOME`（既定 `~/.local/state/cc-learn`）の `journal/YYYY-MM.jsonl` +
  `last-learn.json`。`/learn` 本体は [../claude/skills/learn/SKILL.md](../claude/skills/learn/SKILL.md)。

## workflow_session_start（SessionStart）— `workflow_session_start.sh`
- `lib/status.sh` の 1 行サマリを `additionalContext` で注入（**LLM コストゼロ**）。
- 再起動・resume 後のドリフトと、拒否される往復を未然に防ぐ。このリポジトリで未 engaged
  （state=none）なら何も言わない。advisory / fail-open。

## discipline_subagent（SubagentStart）— `discipline_subagent.sh`
- subagent は親の `CLAUDE.md` も model 起動の skill も**継承しない**ため、エンジニアリング規律
  （「推測せず file:line を読む」「the ladder ＝ YAGNI→既存再利用→stdlib→…最小実装」
  「trust boundary の検証・データ損失防止・security を簡略化しない」「外科的変更」
  「fresh evidence で完了」）を `additionalContext` で**毎 subagent 起動時に 1 回**注入する。
  SubagentStart は context-only なのでブロックはしない。fail-open。

---

## Env toggle 早見表

| Var | 既定 | 効果 | 使用箇所 |
|---|---|---|---|
| `CC_GATE_XDIST` | `auto` | green gate の `pytest -n` ワーカ数 | `verify-gate.sh` |
| `WF_ARCHIVE` | `0` | `1` で verified 時に spec docs を `.workflow/archive/` へ複製 | `lib/wf.sh` |
| `CC_COMPACT_DISABLE` | unset | `1` で compactor 全停止 | `context_compactor.py` |
| `CC_COMPACT_SKIP_TOOLS` | `""` | カンマ区切りで対象ツール除外（例 `Bash,Grep`） | 〃 |
| `CC_COMPACT_ENABLE_READ` | unset | `1` で Read 出力も圧縮対象（既定は除外） | 〃 |
| `CC_COMPACT_SIMILAR` | unset | `1` で類似行畳み込みを有効化 | 〃 |
| `CC_COMPACT_CHARS` / `_LINES` | `12000` / `240` | 圧縮トリガ閾値 | 〃 |
| `CC_COMPACT_HEAD` / `_TAIL` | `120` / `60` | head/tail で残す行数 | 〃 |
| `CC_COMPACT_JSON_SAMPLE` | `6` | JSON 形状サマリで見せる要素数 | 〃 |
| `CC_MEMORY_DB` | `~/.local/share/cc-memory/memory.db` | 記憶 DB パス（機械ローカル） | `cc_memory/core.py`（hook が間接利用） |
| `CC_LEARN_HOME` | `~/.local/state/cc-learn` | learn journal の保存先（機械ローカル） | `skills/learn/session_analyzer.py`（hook が間接利用） |
| `CLAUDE_PROJECT_DIR` | （CC が設定） | プロジェクトルート。未設定時は `git rev-parse --show-toplevel` か `pwd` にフォールバック | 全ワークフロー系 |
| `CC_TDD_JUDGE` | — | **現行コードに存在しない。** TDD 強制は `tdd-guard.sh` + `mark-red.sh` の完全 deterministic（LLM judge は無い） | — |

> 注: `CC_TDD_JUDGE` はこの環境のデプロイ済みフックには登録されていない（`grep` 確認済み）。
> TDD のチェックはすべて文字列/JSON ベースの決定論で、判定に LLM を呼ぶ経路は無い。

---

## hard と advisory の整理

- **hard（迂回しにくい / 結果を強制）**:
  `gate-prereq` `branch-guard` `tdd-guard` `state-guard`（4 本は `jq` 欠落で fail-CLOSED）、
  `verify-gate`（green gate）、`review-capture`（reviewed への唯一・偽造不能な経路）。
  pre-commit から呼ぶ `check-weak-tests.py files ...` も hard。
- **advisory / recorder / logging（壊れても作業を止めない）**:
  `autofix`（通知のみ。床は verify-gate）、`check-weak-tests`（フック時は警告のみ）、
  `mark-red`（記録のみ）、`context_compactor`（圧縮提案）、`*_session_start/_end`、
  `workflow_session_start`、`discipline_subagent`。
- **正直な限界**: OS サンドボックスが無いため Bash ガードは抑止力（難読化で回避余地）。
  純粋な test-first の「順序」は advisory 寄りで、hard なのは
  「赤の記録が無ければ production を編集できない（anti-cheat）」と「緑でないと verified に到れない
  （green-gate）」という結果側の不変条件。
