#!/usr/bin/env bash
# mark-red.sh — PostToolUse(Bash): record pytest red/green into .workflow/red.json.
# Asymmetric: a NARROWED run (-k/-x/--lf/--ff/--testmon) records RED nodeids (to speed
# red-first) but its GREEN is IGNORED (anti fake-green). Only an unrestricted run records
# authoritative GREEN. Never returns updatedToolOutput. Advisory recorder, fail-open.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || exit 0
in="$(cat)"
cmd="$(jq -r '.tool_input.command // ""' <<<"$in")"
grep -Eq '(^| )(uv run )?pytest( |$)' <<<"$cmd" || exit 0
# HIGH 2: only trust a CLEAN pytest invocation. Chaining/echo/redirect/substitution could forge
# the output that we parse, so a non-clean command records NOTHING (the model must run plain pytest).
case "$cmd" in
  *';'*|*'&&'*|*'||'*|*'|'*|*'`'*|*'$('*|*'>'*|*echo*) exit 0 ;;
esac
out="$(jq -r 'if (.tool_response|type)=="string" then .tool_response else (.tool_response.stdout // .tool_response.output // (.tool_response|tostring)) end' <<<"$in" 2>/dev/null)"
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
mkdir -p "$proj/.workflow"; red="$proj/.workflow/red.json"
if grep -Eq '[0-9]+ failed|^ERROR|errors? during collection' <<<"$out"; then result=fail; else result=pass; fi
nodeids="$(grep -Eo 'FAILED [^ ]+' <<<"$out" | sed 's/^FAILED //' | jq -R . | jq -s . 2>/dev/null || echo '[]')"
narrowed='(^| )(-k|-x|--lf|--ff|--testmon)( |=|$)'
ts="$(date -u +%FT%TZ)"
if grep -Eq "$narrowed" <<<"$cmd"; then
  [ "$result" = fail ] && jq -n --argjson f "${nodeids:-[]}" --arg t "$ts" '{failing:$f,narrowed:true,ts:$t}' >"$red"
  exit 0                                            # narrowed GREEN is non-authoritative → ignore
fi
if [ "$result" = fail ]; then
  jq -n --argjson f "${nodeids:-[]}" --arg t "$ts" '{failing:$f,narrowed:false,ts:$t}' >"$red"
else
  jq -n --arg t "$ts" '{failing:[],narrowed:false,green:true,ts:$t}' >"$red"
fi
exit 0
