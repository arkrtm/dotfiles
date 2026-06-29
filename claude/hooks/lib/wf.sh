#!/usr/bin/env bash
# wf.sh — workflow state machine. Single source of truth = $proj/.workflow/state.json.
# Ranks: none(-1) idle(0) requirements_approved(1) branched(2) design_approved(3)
#        implementing(4) reviewed(5) verified(6)
# Subcommands: path|get|rank|init|set|normalize|require <n>|approve-requirements|
#              approve-design|implementing|reviewed|verified
# NOTE: mutators must only be reached via skill `!cmd` preprocessing (state-guard.sh
# denies calling them through the Bash tool).
set -uo pipefail

proj="${CLAUDE_PROJECT_DIR:-}"
[ -z "$proj" ] && proj="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WF_DIR="$proj/.workflow"
STATE_FILE="$WF_DIR/state.json"

die(){ printf 'wf: %s\n' "$*" >&2; exit 1; }

rank_of(){
  case "$1" in
    none) echo -1;; idle) echo 0;; requirements_approved) echo 1;; branched) echo 2;;
    design_approved) echo 3;; implementing) echo 4;; reviewed) echo 5;; verified) echo 6;;
    *) echo -1;;
  esac
}

get(){
  [ -f "$STATE_FILE" ] || { echo none; return; }
  local s; s="$(jq -r '.state // "none"' "$STATE_FILE" 2>/dev/null)"
  { [ -n "$s" ] && [ "$s" != null ]; } && echo "$s" || echo none
}

_set(){
  mkdir -p "$WF_DIR"
  local tmp; tmp="$(mktemp "$WF_DIR/.state.XXXXXX")"
  jq -n --arg s "$1" --arg t "$(date -u +%FT%TZ)" '{state:$s,updated:$t}' >"$tmp" && mv -f "$tmp" "$STATE_FILE"
  echo "$1"
}

init(){
  mkdir -p "$WF_DIR"
  [ -f "$STATE_FILE" ] || _set idle >/dev/null
  if [ -f "$proj/.gitignore" ]; then
    grep -qxF '.workflow/' "$proj/.gitignore" || printf '\n.workflow/\n' >>"$proj/.gitignore"
  else
    printf '.workflow/\n' >"$proj/.gitignore"
  fi
  get
}

normalize(){
  local s br; s="$(get)"
  br="$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
  if [ "$s" = requirements_approved ] && [ -n "$br" ] && [ "$br" != main ] && [ "$br" != master ]; then
    _set branched
  else
    echo "$s"
  fi
}

require(){ local need="$1"; [ "$(rank_of "$(get)")" -ge "$need" ]; }

approve_requirements(){
  local r="$proj/REQUIREMENTS.md"
  [ -f "$r" ] || die "REQUIREMENTS.md not found"
  grep -q '\[NEEDS CLARIFICATION' "$r" && die "Unresolved [NEEDS CLARIFICATION] remain. Run /clarify."
  grep -Eq '^### R[0-9]+:' "$r" || die "No EARS requirement headings (### R<n>: ...). Use the /spec template."
  awk '/^### R[0-9]+:/{h++;ok[h]=0} /R[0-9]+\.[0-9]+ +(WHEN|IF|WHILE|WHERE).+SHALL/{ok[h]=1} END{for(i=1;i<=h;i++) if(!ok[i]) exit 1}' "$r" \
    || die "Each requirement needs >=1 numbered EARS criterion (R<n>.<m> WHEN/IF/WHILE/WHERE ... SHALL)."
  _set requirements_approved
}

approve_design(){
  local d="$proj/DESIGN.md" p="$proj/PLAN.md"
  { [ -f "$d" ] && [ -f "$p" ]; } || die "DESIGN.md and PLAN.md required"
  grep -Eqw 'TBD|TODO|FIXME|implement later' "$p" && die "PLAN.md has placeholders (TBD/TODO/FIXME/implement later)."
  local reqs planned missing
  reqs="$(grep -Eo 'R[0-9]+\.[0-9]+' "$proj/REQUIREMENTS.md" 2>/dev/null | sort -u)"
  planned="$(grep -E '^[[:space:]]*Requirements:|· *Requirements:' "$p" | grep -Eo 'R[0-9]+\.[0-9]+' | sort -u)"
  missing="$(comm -23 <(printf '%s\n' "$reqs") <(printf '%s\n' "$planned") | grep -v '^$' || true)"
  [ -n "$missing" ] && die "Requirements not covered by any task: $(echo "$missing"). Add tasks or mark out-of-scope."
  { grep -q '(test)' "$p" && grep -q '(verify)' "$p"; } || die "Each task must embed a (test) and a (verify) sub-step."
  _set design_approved
}

to_reviewed(){
  local rev="$WF_DIR/review.json"
  [ -f "$rev" ] || die "No review.json. Run /code-review + @adversarial-reviewer first."
  [ "$(jq -r '.verdict' "$rev" 2>/dev/null)" = pass ] || die "Review verdict is not 'pass'. Resolve findings, then re-review."
  _set reviewed
}

set_verified(){
  _set verified >/dev/null
  if [ "${WF_ARCHIVE:-0}" = 1 ]; then
    local slug dst; slug="$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')"
    dst="$WF_DIR/archive/$(date +%F)-$slug"; mkdir -p "$dst"
    cp "$proj/REQUIREMENTS.md" "$proj/DESIGN.md" "$proj/PLAN.md" "$dst/" 2>/dev/null || true
  fi
  echo verified
}

cmd="${1:-get}"; shift 2>/dev/null || true
case "$cmd" in
  path)                 echo "$STATE_FILE" ;;
  get)                  get ;;
  rank)                 rank_of "$(get)" ;;
  init)                 init ;;
  set)                  [ -n "${1:-}" ] || die "set <state>"; _set "$1" ;;
  normalize)            normalize ;;
  require)              [ -n "${1:-}" ] || die "require <minrank>"; require "$1" ;;
  approve-requirements) approve_requirements ;;
  approve-design)       approve_design ;;
  implementing)         _set implementing ;;
  reviewed|to_reviewed) to_reviewed ;;
  verified)             set_verified ;;
  *)                    die "unknown subcommand: $cmd" ;;
esac
