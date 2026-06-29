---
name: map
description: Print a compact symbol map (top-level defs/classes + docstrings) of this repo's Python files, ranked by import references, to orient before editing. Run on demand.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(python3:*)
---

# /map — repo symbol map

```!
python3 "${CLAUDE_SKILL_DIR:-$HOME/dotfiles/claude/skills/map}/repo_map.py" | head -120
```
The map above lists each Python module's top-level `def`/`class` (with one-line docstring), ranked by how many other modules import it. Use it to locate code, then read the actual file before editing — never guess.
