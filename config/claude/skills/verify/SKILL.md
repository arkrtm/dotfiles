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
   - `Makefile` / `justfile` → `make test` / `just test`（`check`、`lint` も可）
   - Gradle / Maven / Swift / PHP → `./gradlew test`、`mvn test`、`swift test`、`phpunit`
   - シェルスクリプト → `shellcheck`、または `tests/` 配下の検査スクリプト（`sh -n` のような構文チェックだけでは証拠にならない）
   - dotfiles → `sh tests/harness-hook.sh`、`sh tests/install.sh`。install.sh・shell 設定・mise の設定を変えたら `sh tests/install-nosudo.sh` も（docker が要る。mac からは `DOCKER='ssh nas docker' sh tests/install-nosudo.sh`）
2. 変更に関係するテストを先に、次に全体を実行する。失敗したら直してから再実行する（テストを弱めて通さない）
   - **検証コマンドは単独で実行する**: パイプ（`| tail`）、`;`、`||`、`>/dev/null`、バックグラウンド実行を付けない（`cd dir && cmd` は可）。付けると終了コードが証拠にならず、hook が「検証済み」にしない。出力を減らしたいときは `-q` などのオプションを使う
   - `--collect-only` や `--version`、構文チェックだけ（`sh -n`）は検証にならない
3. テスト基盤が無い場合: 壊れたら落ちる最小の検査を `tests/` に 1 つ書き、`sh tests/<名前>.sh`（または既にあるテストランナー）で実行する（フレームワークは入れない。`tests/` の外に置いたスクリプトを `python check.py` のように実行しても、hook は検証と認識しない）
4. 報告は「実行したコマンド」と「結果（通過数・失敗数、または末尾数行）」だけ。長い出力は貼らない

検証できない理由がある場合（環境が無い、実行に本番資源が要る等）は、コミットせずに、理由と代わりに確認したことをユーザーに伝えて相談する。
