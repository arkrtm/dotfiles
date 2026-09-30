---
name: review
description: 作業中の変更を reviewer サブエージェントに敵対的レビューさせる。コードを書いたら完了前に必ず実行する（Stop hook が未実施を差し戻す）。指摘が「重大」「中」なら直して再実行
context: fork
agent: reviewer
background: false
argument-hint: "[レビュー対象の補足（任意）]"
---

作業ディレクトリの変更を敵対的にレビューする。

1. 変更を集める（コミット済みかどうかに関わらず、作業中の差分すべて）:
   - `git status --porcelain --untracked-files=all`
   - `git diff HEAD` と、未追跡ファイルは中身を Read
   - 差分が無ければ「レビュー対象の変更がない」とだけ答える
2. 変更した関数・クラスの呼び出し元を `Grep` で探し、影響範囲を読む
3. テストファイルを読み、何を検証していて何を検証していないかを確かめる
4. システムプロンプトの観点と出力形式に従って指摘と判定を返す

補足があれば考慮する: $ARGUMENTS
