---
name: verify
description: 変更後の検証手順。プロジェクトのテスト・型チェック・lint・ビルドを見つけて実行し、コマンドと結果をそのまま示す。コードを変えたら完了前に必ず実行する
---

コードを変えた後、完了を宣言する前に実行する。結果を見ていないものを「通った」と言わない。

1. 検証コマンドを見つける（既にあるものを使う。新しく入れない）
   - `pyproject.toml` / `setup.cfg` → `uv run pytest -q`、`uv run ruff check .`、`uv run mypy` or `pyright`（設定があるもの）
   - `package.json` → `scripts` の `test` / `lint` / `typecheck` / `build`
   - `Cargo.toml` → `cargo test`、`cargo clippy`
   - `go.mod` → `go test ./...`、`go vet ./...`
   - `Makefile` / `justfile` → `test` / `check` ターゲット
   - シェルスクリプト → `sh -n` / `bash -n`、あれば `shellcheck`
   - dotfiles → `sh tests/*.sh`
2. 変更に関係するテストを先に、次に全体を実行する。失敗したら直してから再実行する（テストを弱めて通さない）
3. テスト基盤が無い場合: 壊れたら落ちる最小の検査を 1 つ書いて実行する（assert で動く小さなスクリプトか、テストファイル 1 つ。フレームワークは入れない）
4. 報告は「実行したコマンド」と「結果（通過数・失敗数、または末尾数行）」だけ。長い出力は貼らない

検証できない理由がある場合（環境が無い、実行に本番資源が要る等）は、最終回答に「検証不要: 理由」ではなく「未検証: 理由と、代わりに確認したこと」を書く。
