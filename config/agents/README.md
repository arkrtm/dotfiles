# config/agents

- `config/agents/AGENTS.md`: `~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` にリンクする。全プロジェクト共通の指示（Claude Code・Codex で 1 本。Codex への読み替えも書く）
- `config/agents/skills/issue` `config/agents/skills/wrap-up`: `~/.claude/skills/…` と `~/.agents/skills/…`（Codex が読む）にリンクする。Linear の記録の skill（`/issue ARK-nn` で issue から始める、`/wrap-up` で統合の前に結果を振り分けて残す）
- `config/agents/skills/handoff`: `~/.claude/skills/handoff` だけにリンクする。herdr の中で clear して続ける skill（`config/herdr/README.md` の「常時起動サーバー」）
