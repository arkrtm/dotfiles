#!/usr/bin/env bash
# learn_session_end.sh — SessionEnd: append a scrubbed 1-line digest (session id, cwd,
# #corrections, #files) to the learn journal so /learn can spot cross-session recurrence.
# Logging-only, fail-open. Reads the SessionEnd JSON from stdin.
set -uo pipefail
A="$HOME/dotfiles/claude/skills/learn/session_analyzer.py"
[ -f "$A" ] || exit 0
python3 "$A" journal 2>/dev/null || true
exit 0
