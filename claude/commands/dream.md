---
description: Consolidate cc-memory — promote/refine episodic memories into durable semantic, procedural, and reflective ones
allowed-tools: Bash($HOME/.claude/hooks/lib/ccmem.sh:*), Write
---
Run a **dream** (memory consolidation) for this project's cc-memory scope. The model reasons in
the middle; the CLI only emits candidates and applies your decisions.

**Step 1 — emit candidates.** Run (unquoted path so the permission rule matches):
```bash
$HOME/.claude/hooks/lib/ccmem.sh dream --emit-candidates
```
This returns `{scope, since, episodic:[…], existing:[…]}`: the `episodic` memories logged since the
last dream, and the `existing` semantic/procedural memories already stored.

**Step 2 — reason (do this carefully, do not invent facts).** Read every `episodic` item and:
- Cluster ones that point to the same durable truth.
- **Promote** a recurring/durable fact → `create_semantic`; a recurring how-to/recipe →
  `create_procedural`; a genuine cross-cutting insight → `reflections`.
- **Dedupe against `existing`** — do NOT recreate a fact already stored. If an existing memory is
  now stale or superseded, list its id in `archive_ids`.
- For each episodic item you have folded into a new semantic/procedural/reflection, add its id to
  `consume_episodic_ids` (it gets archived so the next dream won't re-examine it).
- Keep each new memory crisp and self-contained. Be conservative: only promote what is clearly
  worth keeping across sessions.

**Step 3 — apply.** Pipe your operations JSON to the CLI (omit any empty arrays). Even a no-op run
should be applied so the `since` watermark advances:
```bash
$HOME/.claude/hooks/lib/ccmem.sh dream --apply - <<'OPS'
{
  "create_semantic":   [{"content": "…", "concepts": ["a","b"], "importance": 0.6, "confidence": 0.7}],
  "create_procedural": [{"content": "…", "concepts": ["a","b"], "importance": 0.6, "confidence": 0.7}],
  "reflections":       [{"content": "…", "concepts": ["a","b"], "importance": 0.7, "confidence": 0.6}],
  "consume_episodic_ids": [12, 13],
  "archive_ids": [5]
}
OPS
```

**Step 4 — report** the returned counts (`created` / `promoted` / `reflected` / `forgotten`) in one
line, and list (briefly) what you promoted so the user can sanity-check it.
