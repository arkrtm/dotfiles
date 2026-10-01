# 全プロジェクト共通の指示

## 作業の哲学

なるべくシンプルに作業する。下の 2 つ（原文のまま取り込み）に従う。両者が食い違う場合は次で判断する:

- **要件の不明点**: 設計・実装に入る前に質問し尽くし、完全に理解してから進む（Karpathy 1 を優先。Ponytail の「止まらず出す」は、要件が明確になった後の実装判断にだけ適用する）
- **検証**: 目標を検証可能な形にして確認するまで繰り返す（Karpathy 4）。残すテストは最小限でよい（Ponytail: ONE runnable check）
- **リファクタ**: 無関係な箇所は触らない（Karpathy 3）。ただし**触った箇所は触る前より整った状態で終える**（TDD の REFACTOR）。それを超える整理は別 issue に切り出して提案する

## 作業の進め方

流れ（どの規模もこの順。S は要件を 1 行で示して進み、`/wrap-up` は M / L だけ）: 依頼 → 規模の判定 → 要件と受け入れ条件の合意 →（L は計画）→ ブランチ → 要件の固定 → TDD で実装 → `/accept`（受け入れ検証）→ `/verify` → `/review` → コミット → `/wrap-up`（作業ブランチの上で）→ 統合の判断（ユーザー）

冒頭で規模を判定して 1 行で示す。**迷ったら重い方**。作業中に目安を超えたら格上げする（下げない）。S でも解釈が複数あれば 1 問聞く。モデル・effort が合わないと思えば一言添える（例:「S なので effort low で十分」）。

| 規模 | 目安 | 要件と計画 | 実装 | 適した effort |
|---|---|---|---|---|
| S | 1〜2 ファイル、意図が明確 | 依頼の原文が要件。受け入れ条件を 1 行で示して進む | そのまま実装。報告は 3 行以内 | low〜medium |
| M | 複数ファイル、または設計判断がある | 質問 → 要件と受け入れ条件を issue の本文に書き、**ユーザーの承認を得てから**実装。設計判断や作り方の候補が複数あれば `/design`（2〜3 案の比較と推奨、設計の合意） | 持ち分の重ならない大きめのタスクが 2 つ以上なら `/implement` | medium〜high |
| L | 新機能、仕様が曖昧、壊すと痛い | M と同じ → plan mode で計画（`/implement` の形）→ 承認を得て計画も issue に保存 | `cw <名前>`（worktree の新しいセッション）で `/issue ARK-nn` → `/implement ARK-nn`。`/code-review` は実装の直後（指摘を直してから `/accept` → `/verify` → `/review`） | high |

受け入れ条件 = 成果物が要件どおりかを、**実際に動かして確かめられる性質**で書いたもの（「入力・操作 → 期待する結果」と確かめ方）。データなら件数・スキーマ・値の範囲・一意性・参照の整合・再現性・境界、CLI なら出力と終了コード、API なら応答、画面なら操作と表示。本物の入力（無理なら本番に近いサンプル）で動かす条件を含める。**いちばん大事な段階は受け入れ検証**: 型やテストが通っても、成果物が要件どおりでなければ完了ではない。

コードを書くときは規模に関わらず（要件の写し・ブランチ・宣言した検証・受け入れ検証・レビューの承認は hook が確かめ、足りなければ Stop が 1 回差し戻し、pre-commit がコミットを止める。TDD は RED の記録を hook が残し、中身は reviewer が見る）:

1. **ブランチ**: main / master では編集しない（hook が拒否する）
   - 新しいブランチは基点のブランチから切る: `git switch -c <種別>/<短い名前> <基点>`（基点は通常 main。`git symbolic-ref --short refs/remotes/origin/HEAD` で確かめる）
   - M / L と `cw` の新しい worktree では、着手時に依存を入れて検証一式を 1 回流し、元から落ちているものがあれば issue に書く
   - メインで直接実装する M / L も、タスクの進捗を issue の本文のチェックリストに残す（compact や中断の後の手がかり）
2. **要件の固定**: ブランチを切った後、コードを書く前に、合意した要件と受け入れ条件（issue の本文と同じ内容。S は依頼の原文と受け入れ条件 1 行）を `harness-hook requirements-save` に標準入力（quoted heredoc）で渡して保存する
   - 写しはブランチごと（main / master の上では保存できない）。git dir の下にあり、Write ツールでは書けない。場所は `harness-hook requirements-path`
   - acceptor と reviewer はここを直接読む（依頼に写さない）。書き換えると、検証・受け入れ・レビューの証拠はすべて無効になる
   - コードの変更を含むコミットの後は写しが古くなる。次のコード変更の前に保存し直す（同じ依頼の続きなら同じ内容でよい。新しい依頼なら新しい要件で）
3. **TDD**（手順と避けるべき書き方は `/tdd`）: 振る舞いを変える変更は、先に落ちるテストを書き（RED。未実装の振る舞いの assert で落ちること。import エラーは RED ではない。失敗したテストの出力は hook が記録し、reviewer が見る）、最小の実装で通し（GREEN）、**必ず整える（REFACTOR: 命名・重複・置き場所・残骸。テストは緑のまま）**。振る舞いを変えない変更は、既存のテストが守っていればよい
4. **受け入れ検証**: 実装したら `/accept`。acceptor が実装を読む前に成果物を実際に動かし、受け入れ条件ごとに観測した値で確かめ、検査スクリプトを tests/ に残す。不合格なら直してもう一度。完了報告では、条件ごとの観測値と成果物のサンプルをユーザーに見せる
5. **検証**: `/accept` の後に `/verify`
   - 証拠になるのは、リポジトリで宣言した全体の検証コマンド（`.harness-verify`、置けなければ `<git-common-dir>/harness-verify`。無ければ最初に作る）が、すべて同じ内容に対して成功したときだけ
   - リポジトリのトップで、単独で実行する（下位のディレクトリでの実行は数えない。パイプ・`;`・`||` を付けない）。検証コマンドが失敗すると証拠は消える
6. **レビュー**: `/review`（仕様適合・テスト・品質・保守性の 3 軸。依頼には検証のコマンドと結果を書く。reviewer は回し直さない）
   - 指摘は鵜呑みにせず、コードで確かめてから直す。誤りなら直さず、根拠を添えて反論する。人・PR・`/code-review` の指摘も同じ。不明な指摘は全部確かめてから着手する。「ちゃんと作る」系の提案は、実際に使われるか grep で確かめる（YAGNI）。PR の指摘にはスレッドで返信する
   - 「重大」「中」を直したら、内容が変わるので `/accept`（再検証）→ `/verify` → `/review fix`（直したことと反論を渡す範囲限定の再レビュー）
   - 「軽」と範囲外は issue（無ければ完了報告）に記録し、往復しない
   - `/review fix` は起点のレビューごとに 2 回まで。なお重大・中が残れば止め、指摘ごとに直すか見送るかをユーザーに裁定してもらう（見送りは issue に記録し、裁定を渡した `/review fix` を 1 回だけ追加）
   - コードを含むコミットが 2 つ以上あり、同じファイルを触るものがあれば、完了前に `/review branch` も通す
   - 受け入れ検証・レビューの間はファイルを変えない（証拠は終わった時点の内容に記録される）
7. **コミット**: pre-commit が、ステージした内容に対する 4 つの証拠（要件の写し、検証の成功、受け入れ検証の合格、3 軸の承認）を確かめる。レビューした内容はすべてステージする。検証できない事情があれば、コミットせずにユーザーに相談する
   - 共通の pre-commit が呼ばれないリポジトリ（リポジトリ側の core.hooksPath。husky など）では、Bash の `git commit` の前に hook が同じ判定をする。それでも関門を通らずにできたコミットは、Stop がそのターンのうちに見つけて差し戻す（push も止める）
   - マージ・cherry-pick・revert の途中のコミットは、自動の結果との差（競合の解消、後から足した変更）に証拠を求める
   - **関門を迂回しない**: `--no-verify`、`commit-tree`、git 設定・hooks・環境変数の差し替え、`~/.local/state/harness` の操作などはしない。hook は代表的な迂回を拒否するが、ガードレールであって抜け道探しの対象ではない。コミットメッセージに迂回の語を書く必要があれば、`git commit -F - <<'EOF'` で渡す（シェルに渡さないヒアドキュメントの本文は検査しない）
   - ファイルの編集は Edit / Write ツールで行う（`sed -i` や `>>` で書き換えない）
8. **締め**: M / L は、コミットの後・統合の前に、作業ブランチの上で `/wrap-up`（Linear・CLAUDE.md・README・tinymemory への振り分けと保存。main の上では編集できない）
9. **統合**: 完了報告（受け入れ条件ごとの観測値、本人に代わって決めたこと＝判断の一覧、残件）で「main へマージ／PR（`gh pr create`）／ブランチのまま残す」をユーザーに選んでもらい、その指示どおりに行う
   - 勝手にしない。破棄は明示の依頼があるときだけで、消えるコミットを示して確認してから
   - main へのマージは fast-forward で行う（`git merge --ff-only`）。基点が先に進んでいて fast-forward にならなければ、基点を作業ブランチに取り込み（`git merge <基点>`。競合は作業ブランチの上で解消する。main の上では編集できない）、`/accept` → `/verify` → `/review` の後にもう一度 fast-forward する
   - マージしたら main で検証一式を流し、通ってから作業ブランチを消す（落ちたらブランチを残して直す）。その後 issue を Done にする
   - `cw` の worktree は、未コミットの変更が無いことを確かめて `git worktree remove`（`--force` は使わない）

ユーザーの判断を待つ（質問・裁定・相談）とき、バックグラウンドのサブエージェントの完了を待つときは、未完成でもその旨を書いてターンを終えてよい。コミットは pre-commit が止める。急ぐように頼まれても、関門は迂回せず、証拠をそろえるか、そろえられない理由を伝えて止まる。

バグ・テストの失敗・ビルドエラーは、原因がすぐに分からなければ `/diagnose`（根本原因を確かめてから直す）。

サブエージェントは用途に合わせる: 調査・探索は Explore、並列の実装は implementer（`/implement`）、受け入れ検証は acceptor（`/accept`）、レビューは reviewer（`/review`）。受け入れ検証とレビューは、関門の審査なので最上位のモデル（agent の定義で固定）。設計の判断を含む実装はセッションと同じモデル（計画どおりに書き写すだけの機械的な実装タスクは、Agent の model で安いモデルを指定してよい）。独立したツール呼び出し（読み取り・検証）は 1 回の応答でまとめて並列に行う。

## Linear（タスク管理）

会話はあとから見返せないので、**後から Linear だけ見れば作業内容と状況が分かる**状態を保つ。遠慮せず issue を作り、状態を更新してよい。

- 作業の起点に issue が無ければ作る（M / L は必須、S は任意。S で issue が無ければコミットメッセージが記録）。issue があれば `/issue ARK-nn` で始める（「ARK-nn をやって」と言われたときも）
- 要件と受け入れ条件、L の計画は、コメントではなく issue の**本文**に書く（最新が 1 か所で分かるように）
- 状態: 着手で In Progress。コミット済み・未マージの間はそのまま（コメントに「未マージ」と書く）。マージした、または統合しないと決めた後に Done（統合の判断と一緒に確認してよい）。手を止める理由があれば Blocked や Backlog に戻す
- コメントは節目だけ: 要件・計画の合意、方針変更、詰まった点、途中で止めるとき（状態と次の手順。tinymemory は端末ごとなので、別の端末で続けるにはここが要る）、完了（`/wrap-up`）
- 子 issue は、セッションやブランチをまたぐ作業に分けるときだけ作る。1 つのブランチで終わる内訳は、本文のチェックリストに書く
- 将来やる / 見送ったことも issue に残す（Backlog）
- Linear が使えない環境では、issue の代わりにリポジトリの `docs/tasks/<短い名前>.md` に、同じ見出し（要件・受け入れ条件・設計・計画・経過）で書く

### Karpathy guidelines

出典: https://github.com/multica-ai/andrej-karpathy-skills （MIT）

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

#### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

#### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

#### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

#### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

### Ponytail, lazy senior dev mode

出典: https://github.com/dietrichgebert/ponytail （MIT License, Copyright (c) 2026 DietrichGebert）

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the code never written.

Before writing any code, stop at the first rung that holds:

1. Does this need to be built at all? (YAGNI)
2. Does it already exist in this codebase? Reuse the helper, util, or pattern that's already here, don't re-write it.
3. Does the standard library already do this? Use it.
4. Does a native platform feature cover it? Use it.
5. Does an already-installed dependency solve it? Use it.
6. Can this be one line? Make it one line.
7. Only then: write the minimum code that works.

The ladder runs after you understand the problem, not instead of it: read the task and the code it touches, trace the real flow end to end, then climb.

Bug fix = root cause, not symptom: a report names a symptom. Grep every caller of the function you touch and fix the shared function once — one guard there is a smaller diff than one per caller, and patching only the path the ticket names leaves a sibling caller still broken.

Rules:

- No abstractions that weren't explicitly requested.
- No new dependency if it can be avoided.
- No boilerplate nobody asked for.
- Deletion over addition. Boring over clever. Fewest files possible.
- Shortest working diff wins, but only once you understand the problem. The smallest change in the wrong place isn't lazy, it's a second bug.
- Question complex requests: "Do you actually need X, or does Y cover it?"
- Pick the edge-case-correct option when two stdlib approaches are the same size, lazy means less code, not the flimsier algorithm.
- Mark deliberate simplifications that cut a real corner with a known ceiling (global lock, O(n²) scan, naive heuristic) with a `ponytail:` comment naming the ceiling and upgrade path.

Not lazy about: understanding the problem (read it fully and trace the real flow before picking a rung, a small diff you don't understand is just laziness dressed up as efficiency), input validation at trust boundaries, error handling that prevents data loss, security, accessibility, the calibration real hardware needs (the platform is never the spec ideal, a clock drifts, a sensor reads off), anything explicitly requested. Lazy code without its check is unfinished: non-trivial logic leaves ONE runnable check behind, the smallest thing that fails if the logic breaks (an assert-based demo/self-check or one small test file; no frameworks, no fixtures). Trivial one-liners need no test.

## スクリーンショット

ユーザーが「スクショ」「スクリーンショット」「今撮った画像」などと言ったら、`~/screenshots/` の最新ファイルを Read ツールで見る（`ls -t ~/screenshots | head` で確認）。

- ユーザーのローカル端末で撮影したものが自動で転送されている。ファイル名は `ss-YYYYmmdd-HHMMSS.png`（撮影時刻）
- 「さっきの 2 枚」なら新しい順に 2 枚。時刻の指定があればファイル名で探す
- 7 日より古いものは自動で削除される
