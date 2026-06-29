---
name: learn
description: Review the current session and propose durable improvements — new skills, CLAUDE.md lines, or hook/guardrail rules — written to ~/dotfiles with your approval. Run when a session taught you something reusable.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Edit, Write, Glob, Grep, AskUserQuestion, Bash(python3:*), Bash(uv run:*), Bash(mise exec:*), Bash(git add:*), Bash(git status:*), Bash(git diff:*), Bash(git restore:*), Bash(bash:*)
---

# /learn — promote session learnings to ~/dotfiles

## Step 0 — DATA (auto-extracted from this session)
```!
A="$HOME/dotfiles/claude/skills/learn/session_analyzer.py"
python3 "$A" analyze --session "${CLAUDE_SESSION_ID:-unknown}" --cwd "$PWD"
```

## Step 1 — DEDUP
The candidates above are repeated corrections, repeatedly-read files / repeated greps (missing context), and repeated throwaway scripts. Before proposing anything, grep existing config so you EDIT rather than duplicate:
- skills: `~/dotfiles/claude/skills/*/SKILL.md`
- global rules: `~/dotfiles/claude/CLAUDE.md`
- guardrails: `~/dotfiles/claude/hooks/` and `settings.json` deny rules

## Step 2 — CLASSIFY (pick the LIGHTEST home for each learning)
- a repeated correction / missing fact → one line in **CLAUDE.md** (global) or the project `./CLAUDE.md`
- a repeated multi-step workflow → **edit an existing skill**, or (only if it recurs across ≥2 sessions) a new skill
- a "never do X" that bit you → a **deny rule** or a guardrail hook
- a repeated helper script → vendor it under `bin/` with a `.sh`/`.py` extension

## Step 3 — PROPOSE (one at a time)
For each candidate worth adopting, show the exact diff (or new file), and secret-scan every snippet first:
```
printf '%s' "<snippet>" | python3 "$HOME/dotfiles/claude/skills/learn/session_analyzer.py" scan
```
If `scan` exits non-zero, ABORT that item. Then ask Approve / Edit / Skip via `AskUserQuestion`.

## Step 4 — WRITE (approved items only)
Write approved changes into **`~/dotfiles/…`** only — never `~/.claude` directly (install.sh relinks). Be conservative: a new top-level skill needs a clear ≥2-session recurrence or the user's explicit ask; otherwise prefer a CLAUDE.md line or an edit to an existing skill (respect the skill description budget).

## Step 5 — RELINK + STAGE (run AFTER writing; never auto-commit)
```bash
bash "$HOME/dotfiles/install.sh" >/dev/null 2>&1 || true
git -C "$HOME/dotfiles" add <the exact paths you wrote>
git -C "$HOME/dotfiles" status --short
```
Stage only — do not commit or push. Tell the user a new top-level skill needs a Claude Code restart to load.

## Step 6 — RECORD
```bash
python3 "$HOME/dotfiles/claude/skills/learn/session_analyzer.py" mark-learned --session "${CLAUDE_SESSION_ID:-unknown}"
```
