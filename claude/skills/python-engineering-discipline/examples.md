# python-engineering-discipline — examples

各原則の before→after。SKILL.md 本体から必要時に参照する。短く保つ。

## 目次
1. 推測で動かない（原則1）
2. 外科的変更（原則4）
3. 証拠で完了する（原則5）

## 1. 推測で動かない
**Bad**: 「`config.load()` はたぶん dict を返すので…」と読まずに実装を進める。
**Good**: `config.py` を開き `load()` の戻り型（`Config` dataclass）を確認してから実装する。回答時も該当 `file:line` を引く。

## 2. 外科的変更
**Bad**: バグ修正のついでに無関係な関数を rename・型注釈追加・再フォーマット → diff が膨らみレビュー不能・回帰リスク増。
**Good**: バグの行だけ修正。整形は ruff に任せる。別の改善は別コミット／別ブランチに分ける。

## 3. 証拠で完了する
**Bad**: 「実装したので通るはずです」と未実行で完了宣言する。
**Good**: `uv run pytest -q tests/test_x.py` の緑出力と `git diff --stat` を提示してから完了とする。subagent の「成功」報告も diff で確認する。
