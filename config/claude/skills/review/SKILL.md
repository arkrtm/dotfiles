---
name: review
description: reviewer サブエージェントによる敵対的レビュー（仕様適合 + 品質・保守性）。コードを書いたら完了前に必ず実行する（Stop hook が未実施を差し戻す）。`/review branch` は main からの差分全体を対象にする（M で複数コミット・L の完了前に必須）。「重大」「中」の指摘は直して再実行
context: fork
agent: reviewer
background: false
argument-hint: "[branch] [補足（任意）]"
---

コード変更を敵対的にレビューする。引数: $ARGUMENTS

1. 対象を決める
   - 引数に `branch` が**ない**: 作業中の差分（`git status --porcelain --untracked-files=all`、`git diff HEAD`、未追跡ファイルは Read）
   - 引数に `branch` が**ある**: ブランチ全体（`git diff $(git merge-base main HEAD 2>/dev/null || git merge-base master HEAD)...HEAD` と、あれば作業中の差分も）。この場合は個々の行より、**全体の一貫性・構造の劣化・重複・命名のぶれ**を優先して見る
   - 差分が無ければ「レビュー対象の変更がない」とだけ答える
2. 変更した関数・クラスの呼び出し元と、同じ役割の既存コードを `Grep` で探して読む
3. テストファイルを読み、何を検証していて何を検証していないかを確かめる
4. システムプロンプトの観点（軸 1・軸 2）と出力形式に従って、指摘と 2 つの判定を返す
