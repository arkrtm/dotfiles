#!/usr/bin/env bash
# next-task.sh — print the id of the next actionable task in PLAN.md: an unchecked
# task whose deps are all checked. Read-only view (no .workflow/ state). Advisory.
# PLAN task convention (defined by /design):
#   - [ ] T1 — <title> · Requirements: R1.1 · deps: -
#   - [x] T2 — <title> · Requirements: R2.1 · deps: T1
set -uo pipefail
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
plan="$proj/PLAN.md"
[ -f "$plan" ] || exit 0
awk '
  /^- \[[ xX]\] *T[0-9]+/ {
    done = ($0 ~ /^- \[[xX]\]/)
    match($0, /T[0-9]+/); id = substr($0, RSTART, RLENGTH)
    status[id] = done; order[++n] = id; deps[id] = ""
    if (match($0, /deps:[ ]*[A-Za-z0-9, -]*/)) {
      d = substr($0, RSTART+5, RLENGTH-5); gsub(/[ ]/, "", d); deps[id] = d
    }
  }
  END {
    for (i=1; i<=n; i++) { id=order[i]; if (status[id]) continue
      ready=1; m=split(deps[id], a, ",")
      for (j=1; j<=m; j++) if (a[j] != "" && a[j] != "-" && !status[a[j]]) ready=0
      if (ready) { print id; exit }
    }
  }
' "$plan"
