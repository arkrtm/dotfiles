---
name: verify
description: 変更後の検証手順。/accept（受け入れ検証）の後に、受け入れ検査を含むテスト一式・型チェック・lint・ビルドを実行し、コマンドと結果をそのまま示す。コードを変えたら完了前に必ず実行する
---

コードを変えた後、`/accept` で受け入れ検証に合格してから、完了を宣言する前に実行する。結果を見ていないものを「通った」と言わない。

1. 受け入れ条件ごとの確認は `/accept`（acceptor が成果物を実際に動かす）が行い、検査スクリプトを tests/ に残している。/verify はそれを含むテスト一式を通す。受け入れ検証がまだなら、先に `/accept`
2. 検証コマンドを見つける（既にあるものを使う。新しく入れない）。リポジトリのトップに `.harness-verify` があれば、そこに書かれたコマンドをすべて実行する（hook は、書かれたコマンドがすべて同じ内容に対して成功したときだけ検証済みとする）
   - `pyproject.toml` / `setup.cfg` → `uv run pytest -q`、`uv run ruff check .`、`uv run mypy` or `pyright`（設定があるもの）
   - `package.json` → `scripts` の `test` / `lint` / `typecheck` / `build`
   - `Cargo.toml` → `cargo test`、`cargo clippy`
   - `go.mod` → `go test ./...`、`go vet ./...`
   - `Makefile` / `justfile` → `make test` / `just test`（`check`、`lint` も可）
   - Gradle / Maven / Swift / PHP → `./gradlew test`、`mvn test`、`swift test`、`phpunit`
   - シェルスクリプト → `shellcheck`、または `tests/` 配下の検査スクリプト（`sh -n` のような構文チェックだけでは証拠にならない）
   - dotfiles → `.harness-verify` に書いたコマンドすべて。install.sh・shell 設定・mise の設定を変えたら `sh tests/install-nosudo.sh` も（docker が要る。mac からは `DOCKER='ssh nas docker' sh tests/install-nosudo.sh`）。`config/nvim` を変えたら `sh tests/nvim.sh` も
3. 変更に関係するテストを先に、次に全体を実行する。全体の検証コマンドどうしが独立なら、1 回の応答でまとめて並列に実行する。失敗したら直してから再実行する（テストを弱めて通さない。検証コマンドが失敗すると、それまでの証拠は消える）
   - **検証コマンドは単独で実行する**: パイプ（`| tail`）、`;`、`||`、`>/dev/null`、バックグラウンド実行を付けない（`cd dir && cmd` は可）。付けると終了コードが証拠にならず、hook が「検証済み」にしない。出力を減らしたいときは `-q` などのオプションを使う
   - `--collect-only` や `--version`、構文チェックだけ（`sh -n`）は検証にならない
   - サブエージェントの中で実行した検証は証拠にならない（hook が記録しない）。最後はメインの会話で実行する
4. テスト基盤が無い場合: 壊れたら落ちる最小の検査を `tests/` に 1 つ書き、`sh tests/<名前>.sh`（または既にあるテストランナー）で実行する（フレームワークは入れない。`tests/` の外に置いたスクリプトを `python check.py` のように実行しても、hook は検証と認識しない）
5. 報告: 「実行したコマンド → 結果（通過数・失敗数、または末尾数行）」。長い出力は貼らない。受け入れ条件ごとの観測値と成果物のサンプルは、`/accept` の報告から完了報告に載せる

検証できない理由がある場合（環境が無い、実行に本番資源が要る等）は、コミットせずに、理由と代わりに確認したことをユーザーに伝えて相談する。
