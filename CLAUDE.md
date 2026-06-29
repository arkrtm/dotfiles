# CLAUDE.md — このリポジトリ (dotfiles 環境そのもの) を編集するとき

ここは Claude Code のカスタム環境の **source of truth**。`~/.claude` に配備済みで GitHub に push される。
グローバルの作業心得は `claude/CLAUDE.md`（北極星）と `python-engineering-discipline` skill に従う。
本ファイルは**この repo 特有の落とし穴**だけを高密度で書く。全体像は [`docs/architecture.md`](docs/architecture.md)。

## 配備モデル（編集前に必ず意識する）
- **`claude/settings.json` は COPY**（symlink ではない）。編集しただけでは live に反映されない。
  **編集後に必ず `./install.sh` を実行**して `~/.claude/settings.json` を更新する。drift は `./install.sh --check` が検出（`update.sh` も pull 前に走らせる）。`/config` で live を変えた場合は逆に repo へ還元すること。
- **`hooks/` `skills/` `agents/` `CLAUDE.md` `statusline.sh` は symlink**。repo を編集すれば即 live（再配備不要）。
  ただし **新規 top-level skill（`skills/<new>/` を足す）は Claude Code の再起動が必要**（既存 skill の本文編集は再起動不要）。
- `claude-memory/` は symlink せず**絶対パス参照**（MCP 登録・hook が `~/dotfiles/claude-memory` を直に指す）。`claude/templates/` は配備されない（手でコピーするテンプレ）。

## hook を書く/直すときの鉄則
- **shell hook は fail-open が既定**: 依存欠落・パースエラー・timeout で通常作業を止めない（黙って `exit 0`）。
  **例外は deny ガード 4 本**（`gate-prereq.sh` / `branch-guard.sh` / `tdd-guard.sh` / `state-guard.sh`）で、**`jq` 欠落時のみ fail-closed (`exit 2`)**。この非対称を壊さない。
- **deny は exit code でなく JSON**: `{"hookSpecificOutput":{...,"permissionDecision":"deny",...}}` を stdout に出して `exit 0`。Stop の拒否は `{"decision":"block","reason":...}`。`exit 2` は fail-closed 経路だけ。
- hook は live の symlink パス（`~/.claude/hooks/…`）から実行される。共有ロジックは **`BASH_SOURCE` 基準で `lib/` を解決**しているので、その相対解決を壊さない（`$0` やハードコードパスに変えない）。
- 先頭の `export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"`（PATH 固定）を消さない（GUI 起動で痩せた PATH 対策）。
- workflow 状態の書き込みは **`lib/wf.sh` の mutator 経由のみ**。`state.json` を hook から直接書かない。`reviewed`/`verified` は permission の外で走る hook（`review-capture.sh` / `verify-gate.sh`）だけが stamp できる設計。
- **必ずオフラインで test**: 実 stdin を模した JSON を食わせて挙動を確認してから依存する。例:
  ```sh
  echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py"}}' | ~/dotfiles/claude/hooks/gate-prereq.sh; echo "exit=$?"
  ```

## Python（cc-memory / `*.py` hook）
- **uv / ruff / pyright strict**。`pip` や素の `python` を直叩きしない。整形・lint・import は ruff（手で整えない）。
- **stdlib-first**（the ladder）。`cc_memory` のランタイム依存は `mcp` のみ、`vec` extra は任意。新規依存を安易に足さない。
- 検証は `assert` でなく `if … raise`（`python -O` で消えるため）。外部入力は境界で検証。
- 完了は fresh evidence で: `( cd claude-memory && uv run pytest && uvx ruff check . && uvx pyright )` が緑を見てから。

## 機密と machine-local（絶対に commit しない）
- 記憶 DB (`~/.local/share/cc-memory/`)、`/learn` journal (`~/.local/state/cc-learn/`)、各 repo の `.workflow/`、`~/.claude.json`、認証・transcript・`.venv` は**この repo に入れない**。
- 二重ガードに守られている前提で**さらに油断しない**: ルート `.gitignore`（機密 hard-deny）、`claude/.gitignore`（allowlist: 全無視→`*.md/*.py/*.sh/*.yaml/*.yml`+`settings.json` だけ許可→機密を最後に再 deny）、`gitleaks`+`detect-private-key` の pre-commit。vendored script は `.sh`/`.py` で終わらないと commit されない。

## 変更を反映する順番（典型）
1. `~/dotfiles/…` を編集（`~/.claude` を直接触らない）。
2. settings.json を触ったら `./install.sh`。それ以外（symlink 物）は即 live。
3. 影響 hook をオフライン stdin で確認 → Python を触ったら uv/ruff/pyright 緑を確認。
4. `./install.sh --check` で drift 無しを確認してから commit/push（自動 commit はしない）。
