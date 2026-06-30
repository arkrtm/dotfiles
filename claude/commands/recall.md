---
description: Search cc-memory for memories relevant to a query (this project's scope)
argument-hint: <what to look up>
allowed-tools: Bash($HOME/.claude/hooks/lib/ccmem.sh:*)
---
Search **cc-memory** for what is relevant to:

$ARGUMENTS

Keep the path UNQUOTED so the `Bash($HOME/.claude/hooks/lib/ccmem.sh:*)` permission rule matches,
but pass the query as a SINGLE-QUOTED literal so any shell metacharacters in it (`$VAR`, backticks,
`$(...)`) are searched literally instead of being expanded/executed by the shell. Escape an embedded
single quote as `'\''`. Scope auto-resolves from cwd to this project:
```bash
$HOME/.claude/hooks/lib/ccmem.sh recall '<the query text, single-quoted>' --limit 8
```
Then summarize the hits for the user: most-relevant first, each as a one-liner with its `type`
and score; quote content faithfully. If nothing returns, say so plainly. Add `--all-scopes` only
if the user explicitly wants cross-project results.
