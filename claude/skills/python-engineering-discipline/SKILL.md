---
name: python-engineering-discipline
description: Engineering taste and discipline for writing, refactoring, or fixing Python code — apply when implementing features, changing existing code, fixing bugs, answering questions about code, or reviewing a diff. Encodes evidence-over-speculation, think-before-coding, simplicity, surgical changes, and evidence-based completion.
---

# Python エンジニアリングの規律

**エスケープハッチ**: trivial・自明な変更（typo、1行、明白な doc）では儀式を省き、判断で進めてよい。ただし原則1（推測で動かない）は常に守る。

## 1. Ground in Evidence, Never Guess（推測で動かない／根拠を見てから）★最優先
該当する実コードを読まずに作業・回答しない。推測で答えない。変更・回答の前に、関連ファイル・定義・呼び出し元・既存テストを実際に開いて確認する。不明な点は推測でなく、読む／実行する／質問する。
- ✅ セルフチェック: **「この回答・変更は、実際に読んだコード（file:line）に基づいているか? 推測が混じっていないか?」**
- ✅ セルフチェック: **「『たぶんこうなっているはず』で進めていないか? なら今すぐ該当箇所を開く。」**

## 2. Think Before Coding（考えてから書く）
コードを書く前に、達成すべき目的・制約・成功条件を言語化する。曖昧なら質問する。
- ✅ セルフチェック: **「この変更が満たす要件を1文で言えるか?」** 言えないなら止まって確認する。
- ✅ セルフチェック: **「最も単純な解は何か? いきなり複雑な方に飛びついていないか?」**
- 複雑な依頼でも **default できる答えで手を止めない**。lazy 版を出して同じ応答で疑問を呈する（質問だけで停止しない）。

## 3. Simplicity First（まず単純に）
今必要な最小の変更で目的を達成する。抽象化・汎用化・設定可能化は、今この瞬間に必要な分だけ。
- ✅ セルフチェック: **「シニアエンジニアが『これは過剰だ』と言わないか?」**
- ✅ セルフチェック: **「将来のためだけの抽象・汎用化を足していないか?（YAGNI）」**

### 3.1 The Ladder（書く前に・最初に成立した段で止まる）
コードを書く前に上から順に評価し、最初に成立した段で止める:
1. **そもそも要るか?** 投機的な必要 = やらない、一行でそう言う（YAGNI）
2. **このリポに既存か?** helper / util / 型 / パターンを grep してから書く（数ファイル隣の再実装が最頻の slop）
3. **stdlib にあるか?** `itertools` / `functools` / `pathlib` / `dataclasses` / `collections` / `statistics` / `zoneinfo` / `tomllib` を custom より先に
4. **言語/フレームワークのネイティブ機能か?** `@dataclass` / `enum` / `contextlib`、DB・ORM 制約 > アプリ側コード
5. **pyproject に既にある依存で済むか?** 数行で済むものに新規依存を足さない（ただし依存ゼロ教条にもしない — 正しい1つは残す）
6. **1行で済むか?** 1行
7. **初めて:** 動く最小コード
- ✅ セルフチェック: **「pandas/numpy/ORM/フレームワークを3行仕事に持ち込んでいないか? class階層/factory/config を1実装に作っていないか?」**

**lazy ≠ negligent**: ラダーは*解*を縮めるが*読み*は縮めない（原則1）。そして次は**絶対に削らない** — 信頼境界の入力検証 / データ損失を防ぐエラー処理 / セキュリティ / アクセシビリティ / 明示的に依頼されたもの。非自明なロジックには runnable check（小さな `test_*` か `assert` の動作確認）を1つ残す（自明な1行には testにもYAGNI）。

**天井コメント**で意図的な簡略を「無知でなく意図」として証拠化する（後で `grep -rn '# yagni:\|# debt:'` が負債台帳に育つ）:
```python
# yagni: global lock; per-account ロックは throughput が問題化したら
# debt:  素朴な O(n^2); N が増えたら dict index に
```

## 4. Surgical Changes（外科的変更）
依頼に直接紐づく行だけを変える。無関係なリネーム・再フォーマット・型注釈/docstring の後付け・「ついで」リファクタを混ぜない（整形は ruff に任せる）。
- ✅ セルフチェック: **「変更した全行が依頼に直接トレースできるか?」**
- ✅ セルフチェック: **「依頼にない “ついで修正” を混ぜていないか? 混ぜたなら戻すか別コミットに分ける。」**
- **バグ修正は症状でなく根本原因。** 編集前に対象関数の全 caller を grep し、共有関数に1ガード（各 caller に撒くより小さい diff・兄弟 caller も直る）。1実装に interface/factory/config を作らない。

## 5. Evidence-Based Completion（証拠で完了する）
「できた」は主観でなく証拠で示す。関連するテスト・型・lint を実際に走らせ、緑の出力を確認してから完了と宣言する。
- ✅ セルフチェック: **「fresh evidence（実行したテスト出力 / diff）なしに完了宣言していないか?」**
- ✅ セルフチェック: **「自分（や subagent）の “通ったはず” を、実行結果を見ずに信じていないか?」**
- 意図的に省いたものは完了時に **1〜3行で明示**（`# skipped: X — add when Y`）。比較表・feature 列挙・複数バリアントは書かない（出力にも YAGNI）。

具体的な TDD・緑ゲートの手順は `/tdd-implement`・`/verify` skill に従う。詳細な before/after 例は同梱の `examples.md` を必要時に参照する。

## コードの好み（Python 固有・最小）
- 検証に `assert` を使わない（`python -O` で消える）→ `if … raise`。
- 外部入力は pydantic 等で境界検証。None / 境界を明示的に扱う。
- 命名・コメント密度は周囲のコードに合わせる。
- 整形・import 整理・lint は ruff（手で整えない）。
