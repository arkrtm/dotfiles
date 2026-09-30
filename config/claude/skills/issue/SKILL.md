---
name: issue
description: Linear の issue を起点に作業する。issue を読んで In Progress にし、要件を確認してから着手し、終わったら結果をコメントして状態を更新する
disable-model-invocation: true
argument-hint: "<ARK-nn> [補足]"
arguments: [issue]
---

Linear の issue $issue を起点に作業する。

1. 読む: `get_issue`（関連・親子も含む）とコメント。既存の決定事項があれば従う
2. 着手を記録: 状態を In Progress、担当を me にする
3. 要件を固める: 不明点・複数に解釈できる点・前提をすべて洗い出し、AskUserQuestion でまとめて質問する。**完全に理解するまで設計・実装に入らない**。合意した要件を 3〜6 行で復唱してから進む
4. 規模を判定（CLAUDE.md の S/M/L）して、その手順で作業する
5. 完了時に issue へコメントする（見出し: やったこと／検証（コマンドと結果）／レビュー結果／残件・判断待ち）。状態は「Done にしてよいか」をユーザーに確認してから変える
6. 途中で決定・方針変更があれば、その都度コメントで残す（この会話は他の端末から見えない前提）

補足: $ARGUMENTS
