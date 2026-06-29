---
name: dream
description: Consolidate this session's raw memories — dedup, summarize episodic→semantic, promote repeated steps to procedures, reflect, link, and reversibly forget low-value items. Run on demand to tidy long-term memory.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Bash(mise exec:*), Bash(uv run:*)
---

# /dream — consolidate memory

## 1. Gather candidates (deterministic)
```!
P="$HOME/dotfiles/claude-memory"
if command -v mise >/dev/null 2>&1; then mise exec -- uv run --quiet --project "$P" cc-memory dream --emit-candidates
else uv run --quiet --project "$P" cc-memory dream --emit-candidates; fi
```

## 2. Reason (you, now)
From the `episodic` candidates and `existing` semantic/procedural memory above, produce a consolidation `operations` JSON:
- `create_semantic` — durable facts appearing in ≥2 episodes: `[{content, concepts?, importance?, confidence?}]`
- `create_procedural` — how-to steps observed repeatedly: same shape
- `reflections` — non-obvious insights spanning ≥2 episodes: same shape
- `consume_episodic_ids` — episodic ids now captured above (archived reversibly)
- `archive_ids` — stale/low-value ids to forget (reversible)

Be conservative: only promote what's clearly durable; never invent. Skip anything below the ≥2 / high-confidence bar.

## 3. Apply (deterministic, single transaction)
Pipe your operations JSON via stdin (forgetting is reversible: `cc-memory restore --archive <id>`):
```
mise exec -- uv run --quiet --project "$HOME/dotfiles/claude-memory" cc-memory dream --apply - <<'OPS'
{ ...your operations JSON... }
OPS
```
Report the returned counts (created / promoted / reflected / forgotten).
