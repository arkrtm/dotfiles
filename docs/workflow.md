# Enforced Dev Workflow

仕様 → 設計 → TDD 実装 → 検証 を、hook で機械的に強制するワークフロー。非自明な変更だけに適用され、自明な変更は素通しする（escape hatch）。本書は実際のコード（`claude/hooks/*`, `claude/skills/*`, `settings.json`）が「実際に何をするか」を記述する。

関連: settings / hook 登録は `./hooks.md`、skill 一覧は `./skills.md`、Python ツールチェーンは `./python.md` を参照（兄弟ドキュメント）。

---

## 1. ステージマシン

唯一の真実は `$proj/.workflow/state.json`（machine-local、`wf.sh init` が `.gitignore` に `.workflow/` を自動追記するので **commit されない**）。状態の読み書きは全て `claude/hooks/lib/wf.sh` 経由。

| state | rank | 意味 | このstateに入る経路 |
|---|---|---|---|
| `none` | -1 | **未エンゲージ**（`/spec` 未実行）。全gateが素通し | 初期状態 |
| `idle` | 0 | エンゲージ済み・要件作成中 | `wf.sh init`（`/spec` が実行） |
| `requirements_approved` | 1 | GATE 1 通過 | `wf.sh approve-requirements`（`/approve-requirements`） |
| `branched` | 2 | feature branch 上 | `wf.sh normalize`（**自動**、下記） |
| `design_approved` | 3 | GATE 2 通過・本番コード解禁 | `wf.sh approve-design`（`/approve-design`） |
| `implementing` | 4 | TDD ループ中 | `wf.sh implementing`（`/tdd-implement`） |
| `reviewed` | 5 | レビュー pass・Stop green-gate 待ち | `review-capture.sh`（後述）**のみ** |
| `verified` | 6 | 完了（authoritative green） | `verify-gate.sh`（Stop hook）**のみ** |

rank は単調増加の閾値として使う（多くの gate が `rank >= N` で判定）。

### 自動遷移: `requirements_approved → branched`

専用の skill は無い。`gate-prereq.sh` が毎回の Edit/Write で `wf.sh normalize` を呼び、「state が `requirements_approved` かつ現在ブランチが `main`/`master` 以外」なら `branched` に昇格する（`wf.sh:50-58`）。つまり **GATE 1 後に `git switch -c feat/<slug>` してファイルを触れば自動で branched になる**。

### 2つの人間承認ゲート（model からは押せない）

| Gate | skill | 検証内容（`wf.sh`） |
|---|---|---|
| **GATE 1** | `/approve-requirements` | `REQUIREMENTS.md` 存在 / `[NEEDS CLARIFICATION` 残存なし / `### R<n>:` 見出しあり / 各要件に `R<n>.<m> (WHEN\|IF\|WHILE\|WHERE) … SHALL` を1つ以上（`approve_requirements`, `wf.sh:62-70`） |
| **GATE 2** | `/approve-design` | `DESIGN.md`+`PLAN.md` 存在 / `PLAN.md` に placeholder（`TBD/TODO/FIXME/implement later`）なし / **REQUIREMENTS.md の全 `R<n>.<m>` がいずれかの task の `Requirements:` 行で被覆** / 各 task に `(test)` と `(verify)`（`approve_design`, `wf.sh:72-83`） |

両 skill の frontmatter は `disable-model-invocation: true` + `user-invocable: true`。**model は呼べず、人間だけが実行できる**。検証に落ちると `wf: …` をstderrに出して state は進まない。

### 2つの machine-only 遷移（agent からは偽造不可）

`reviewed` と `verified` は permission システムの外で走る hook だけが書ける。

- `implementing → reviewed`: `review-capture.sh`（SubagentStop）が、`adversarial-reviewer` の最終メッセージから `<REVIEW_VERDICT>{…}</REVIEW_VERDICT>` を抽出して `.workflow/review.json` に保存し、`verdict=="pass"` なら `wf.sh to_reviewed` を呼ぶ（`to_reviewed` が review.json を再検証）。**identity は fail-closed**: `subagent_type == "adversarial-reviewer"` 以外は何もしない（`review-capture.sh:15`）。他の subagent がマーカーを印字しても無効。
- `reviewed → verified`: `verify-gate.sh`（Stop）の Phase 2 green のみが `wf.sh verified` を stamp する。

### mutator の直叩き防止

`wf.sh` の mutator（`set/init/approve-*/implementing/reviewed/to_reviewed/verified`）は skill markdown の `` ```! `` ブロック（`!cmd` preprocessing = model のターン前に bash 実行）からのみ到達する設計。Bash tool 経由の呼び出しは `state-guard.sh` が deny する（`wf.sh:7-8`, `state-guard.sh:13-16`）。

---

## 2. ステップ・バイ・ステップ（how-to）

```text
/spec  →  (/clarify)  →  /approve-requirements  →  git switch -c feat/<slug>
       →  /design  →  (/design-review)  →  /approve-design  →  /tdd-implement  →  /verify
```

| # | コマンド | 何が起きるか | 結果 state |
|---|---|---|---|
| 1 | `/spec <feature>` | `wf.sh init`（→`idle`）、ユーザに `AskUserQuestion` でヒアリング、EARS形式で `REQUIREMENTS.md` を書く。**本番コードは書かない** | `idle` |
| 2 | `/clarify`（任意） | `@requirements-analyst`（read-only, fresh context）で曖昧点を洗い出し → `[NEEDS CLARIFICATION: …]` を挿入 → ユーザと解消 | `idle` |
| 3 | `/approve-requirements` | **GATE 1（人間）**。EARS構造を検証して合格なら昇格 | `requirements_approved` |
| 4 | `git switch -c feat/<slug>` | feature branch を作る。次の Edit/Write で `normalize` が自動昇格 | →`branched`（自動） |
| 5 | `/design` | `DESIGN.md`（アーキ/データフロー/エラー処理/テスト戦略）と `PLAN.md`（junior-proof, TDD-ready, 要件トレーサビリティ）を書く | `branched` |
| 6 | `/design-review`（任意） | `@design-reviewer`（read-only, fresh context）が設計の健全性・過剰設計・設計レベルの失敗モード（並行性/冪等性/rollback/移行）・分解と依存順・TDD適性を洗い出し → ユーザと `DESIGN.md`/`PLAN.md` を修正。**advisory: state を動かさず GATE 2 を inform するだけ**（`/clarify` の設計版） | `branched` |
| 7 | `/approve-design` | **GATE 2（人間）**。PLAN被覆を検証して合格なら昇格。**本番コード解禁** | `design_approved` |
| 8 | `/tdd-implement` | `wf.sh implementing`。`next-task.sh` が次の actionable task id を表示。task毎に red→green→refactor | `implementing` |
| 9 | `/verify` | fresh evidence（pytest/ruff/pyright/diff）→ `/code-review` → `@adversarial-reviewer`。verdict pass で `reviewed`、Stop green-gate で `verified` | `reviewed`→`verified` |

`SessionStart` の `workflow_session_start.sh` が、resume 時に現在 stage・次タスク・今許可される操作を `additionalContext` で注入する（再開時のドリフト防止、advisory）。

---

## 3. 何が・いつ・どの hook でブロックされるか

全 PreToolUse 系 guard は **`state == none`（未エンゲージ）なら素通し**（trivial-change escape hatch）。`gate-prereq/branch-guard/tdd-guard/state-guard` は `jq` 必須で **fail-CLOSED**（無ければ `exit 2`）。

| 操作 | ブロック条件 | hook（event/matcher） | 種別 |
|---|---|---|---|
| `.workflow/` を直接 Edit/Write | エンゲージ中は常に（canonical path で `./`・`../`・symlink も検査） | `gate-prereq.sh`（PreToolUse Edit/Write） | HARD |
| 本番コードの Edit/Write | `rank < 3`（design未承認）。`*.py` は `docs/` 配下でも min=3 | `gate-prereq.sh` | HARD |
| `DESIGN.md`/`PLAN.md` の Edit/Write | `rank < 2`（branch未作成） | `gate-prereq.sh` | HARD |
| `*.md` ドキュメントの Edit/Write | min=0（要件文書等は常に許可） | `gate-prereq.sh`（除外） | — |
| `main`/`master` 上でコードを Edit/Write | エンゲージ中、対象が `*.md`/`docs/`/`.workflow/` 以外 | `branch-guard.sh`（PreToolUse Edit/Write） | HARD |
| テストの削除（`def test` 数が減る） | `rank>=3` かつ tests/ or `test_*.py`/`*_test.py` | `tdd-guard.sh`（PreToolUse Edit/Write） | HARD |
| `@pytest.mark.skip/xfail` `pytest.skip(` `collect_ignore` の追加（黙らせ） | 旧版に無く新版に追加される場合 | `tdd-guard.sh` | HARD |
| 本番 `*.py` を red 記録なしで編集 | `rank>=3` かつ `.workflow/red.json` の `failing` が空 | `tdd-guard.sh` | HARD |
| `fix/*` ブランチで再現テストより先に本番編集 | `tests/` 配下の差分が無い（G-REG-1） | `tdd-guard.sh` | HARD |
| Bash で `wf.sh` mutator を呼ぶ | 常時 | `state-guard.sh`（PreToolUse Bash） | HARD |
| Bash で `.workflow/` に書く（`>>`/`tee`/`cp`/`mv`/`sed -i`/`python`/`jq`/`printf`/`echo`…） | 常時 | `state-guard.sh` | HARD |
| Bash でコードを書く（リダイレクト/`tee`/`sed -i`/`open(…,'w')`/`write_text`/`os.replace`/`shutil` → `.py/.pyi/.toml/.cfg/.ini`） | エンゲージ中（`.workflow/`・`/tmp/`・`scratchpad` は除外） | `state-guard.sh` | HARD |
| ターン終了（Stop） | `state==reviewed` かつ green-gate が red | `verify-gate.sh`（Stop） | HARD |
| 弱いテスト（assertion無し/定数assert）のコミット | pre-commit の `weak-tests` で検出時 | `check-weak-tests.py files`（pre-commit） | HARD |

PostToolUse 系（react するだけ、ブロック不可）:

| hook | event | 役割 | 種別 |
|---|---|---|---|
| `autofix.sh` | PostToolUse Edit/Write | `.py` 編集後に `ruff check --fix` + `ruff format`。`additionalContext` で「再読込せよ」と通知 | advisory |
| `check-weak-tests.py`（stdin mode） | PostToolUse Edit/Write | 編集したテストの tautological/assertion-free を AST で警告 | advisory |
| `mark-red.sh` | PostToolUse Bash | pytest の red/green を `.workflow/red.json` に記録 | advisory recorder |

---

## 4. TDD 強制 ── どこまでが HARD か（正直版）

**HARD（hook が deny / block する）:**
- テスト削除・`skip`/`xfail`/`collect_ignore` 追加による黙らせは `tdd-guard.sh` が **deny**。
- 本番 `*.py` 編集は `.workflow/red.json` に **失敗テストが記録されている**ことを要求（無ければ deny）。→ 「red が先に存在する」ことは強制される。
- Stop の green-gate（`verify-gate.sh`）は `reviewed` の間ターンを red で終わらせない。

**ADVISORY（規律であって機械強制ではない）:**
- **純粋な test-first（コードより前に "正しい" テストを書く）は advisory**。hook が見るのは「red が記録済みか」だけで、「そのテストが今書く本番コードを実際に検証しているか」までは保証しない。CLAUDE.md / skill の指示が担保する。

### red/green 記録の非対称性（fake-green 対策）

`mark-red.sh` は `pytest` 実行を観測して `.workflow/red.json` を書くが:
- **clean な invocation だけ信用する**: `;` `&&` `||` `|` `` ` `` `$(` `echo` を含むコマンドは何も記録しない（出力を偽造できるため、`mark-red.sh:14-16`）。
- **narrowed run（`-k`/`-x`/`--lf`/`--ff`/`--testmon`）は RED だけ記録し GREEN を無視**する（`mark-red.sh:22-27`）。内側ループを速くしつつ「狭い緑」で gate を抜けさせない。
- authoritative GREEN（`failing:[]`）は **無制約の full run** だけが記録する。green 記録後は `failing` が空になるので、次に本番 `.py` を触るには再び red にするか refactor escape が要る。

---

## 5. Escape hatch（逃げ道）

| hatch | 効果 | クリアされる契機 |
|---|---|---|
| **trivial-change = `/spec` しない** | state が `none` のまま → 全 PreToolUse guard が `exit 0`。**gate もブランチ制約も TDD も一切かからない**。typo・1行・自明な doc 用 | `/spec` を実行するまで永続 |
| **`touch .workflow/allow-refactor`** | 振る舞いを変えない pure green refactor として、red 記録なしでも本番 `.py` 編集を許可（`tdd-guard.sh:41`） | **green cycle 毎にクリア**。`verify-gate.sh:51` が green 成立時に `rm -f .workflow/allow-refactor`。恒久ではない |

---

## 6. Green gate の中身（`verify-gate.sh`, Stop hook）

`state == reviewed` の間だけ作動（`verified` 後は skip）。`uv` が無ければ no-op。Python ツールは `lib/pyrun.sh` で「uv project なら `uv run --no-sync <tool>`、project 外なら `uvx <tool>`」を解決。

- **Phase 1（cheap red）**: `pytest --lf -x -q`。last-failed が赤なら即 block。
- **Phase 2（authoritative green、全部緑で初めて `verified`）**:
  1. `pytest -n <CC_GATE_XDIST:-auto> -q --cov --cov-branch --cov-report=xml`（xdist 並列）
  2. `ruff format --check .`
  3. `ruff check .`
  4. `uvx pyright`
  5. `diff-cover coverage.xml --compare-branch <base> --fail-under 90` ── base は upstream `@{u}` との merge-base（無ければ `main`）。**新規/変更行の branch coverage 90% 未満で落ちる**

全て緑なら: `repair.n` を0に、`allow-refactor` 削除、green checkpoint（`git add -A` → `gitleaks protect --staged` で secret があれば block → `git commit -m "checkpoint: green" --no-verify` → `git tag -f green-<branch>`）、`wf.sh verified`。

**3連続 red で auto-rollback**（`repair.n` が唯一の loop-breaker）: 作業ツリーを当ブランチ最後の green tag（`green-<branch>`）へ `git reset --hard`、壊れた WIP は `rescue/<ts>-<pid>` ブランチに退避。tag が無い等で復元できなければ、ループせず gracefully 諦める。

---

## 7. Per-repo pre-commit テンプレート

`claude/templates/.pre-commit-config.yaml` を対象 repo にコピーし、一度だけ `uvx pre-commit install`。`rev:` は placeholder なので **コピー後に `uvx pre-commit autoupdate`** で現行版に固定（バージョンを推測しない）。これは CI を持たない repo のローカル品質ゲート。

| hook | 内容 |
|---|---|
| `ruff-check` (`--fix`) / `ruff-format` | lint + format（hook の autofix と同じ設定） |
| `detect-private-key` / `gitleaks` | secret 混入の検出 |
| `end-of-file-fixer` / `trailing-whitespace` / `check-merge-conflict` / `check-added-large-files` | 基本衛生 |
| `uv-lock-check` (`uv lock --check`) | `pyproject.toml`/`uv.lock` 整合 |
| `pyright` (`uvx pyright`) | 型チェック |
| `weak-tests` | `check-weak-tests.py files` を `tests/*.py` に適用。tautological/assertion-free テストがあれば **exit 1（HARD）** |

`check-weak-tests.py` は2モード: pre-commit の `files` 引数モードは HARD（stderr + exit 1）、stdin（PostToolUse）モードは advisory 警告のみ。

---

## 8. 残存する限界（正直に）

- **OS sandbox が無いため、`state-guard.sh` の文字列 guard は回避可能**。`base64 | sh`・`eval`・難読化された書き込みは string-match を擦り抜けうる（`state-guard.sh:4-5` が明言）。これは**敵対的アクターを止める仕組みではなく、"親切心からの"/事故的な bypass のハードルを上げるもの**。
- 同様に Bash 系の guard 一般は「決定論的だが擦り抜け可能な抑止（deterrent）」。
- 本当に偽造困難な hard floor は **permission システムの外で走る2つ**: `review-capture.sh`（SubagentStop, identity fail-closed）と `verify-gate.sh`（Stop, 独立に full suite を再実行）。これらは main agent / Bash / Edit からは forge できない。
- まとめ: **anti-cheat deny + Stop green-gate は HARD、pure test-first は advisory**。
