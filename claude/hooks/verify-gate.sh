#!/usr/bin/env bash
# verify-gate.sh — Stop hook: the GREEN gate. HARD. Acts only while state == reviewed.
# Phase 1 cheap red (--lf -x); Phase 2 authoritative green (full xdist + ruff + pyright +
# diff-cover) — only Phase 2 stamps 'verified'. 3 consecutive reds => auto-rollback to this
# branch's last green checkpoint (broken WIP parked on rescue/*).
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command -v jq >/dev/null 2>&1 || exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LIB="$DIR/lib"
in="$(cat)"
proj="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$proj" 2>/dev/null || exit 0
[ "$(bash "$LIB/wf.sh" get 2>/dev/null)" = reviewed ] || exit 0   # only gate at reviewed; skip once verified
command -v uv >/dev/null 2>&1 || exit 0
mkdir -p .workflow
read -r -a PYR  <<<"$(bash "$LIB/pyrun.sh" pytest)"
read -r -a RUFF <<<"$(bash "$LIB/pyrun.sh" ruff)"
br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
tag="green-${br//\//-}"
fail(){ jq -n --arg r "$1" '{decision:"block",reason:$r}'; exit 0; }
green_checkpoint(){
  git add -A >/dev/null 2>&1                                       # MEDIUM 6(a): include new files
  if command -v gitleaks >/dev/null 2>&1 && ! gitleaks protect --staged --no-banner >/dev/null 2>&1; then
    fail "Checkpoint blocked: gitleaks found a secret in staged changes. Remove it, then re-run /verify."  # MEDIUM 6(b)
  fi
  git commit -qm "checkpoint: green" --no-verify >/dev/null 2>&1 && git tag -f "$tag" >/dev/null 2>&1 || true
}

# Phase 1: cheap red
if ! "${PYR[@]}" --lf -x -q >/tmp/cc_vg1.$$ 2>&1; then
  r="$(tail -40 /tmp/cc_vg1.$$)"; rm -f /tmp/cc_vg1.$$
  fail "Last-failed tests are still red:
$r
Fix them, then re-run /verify."
fi
rm -f /tmp/cc_vg1.$$

# Phase 2: authoritative green
base="$(git merge-base HEAD "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo main)" 2>/dev/null || echo HEAD)"
ok=1
"${PYR[@]}" -n "${CC_GATE_XDIST:-auto}" -q --cov --cov-branch --cov-report=xml >/tmp/cc_vg2.$$ 2>&1 || ok=0
if [ "$ok" = 1 ]; then
  "${RUFF[@]}" format --check . >/dev/null 2>&1 || ok=0
  "${RUFF[@]}" check . >/dev/null 2>&1 || ok=0
  uvx pyright >/dev/null 2>&1 || ok=0
  [ "$ok" = 1 ] && { uv run --no-sync diff-cover coverage.xml --compare-branch "$base" --fail-under 90 >/dev/null 2>&1 || ok=0; }
fi

if [ "$ok" = 1 ]; then
  echo 0 >.workflow/repair.n
  rm -f .workflow/allow-refactor                 # HIGH 5: the refactor escape hatch is per-cycle, not permanent
  green_checkpoint
  bash "$LIB/wf.sh" verified >/dev/null 2>&1
  rm -f /tmp/cc_vg2.$$
  exit 0
fi

# red: count, then auto-rollback at 3 (MEDIUM 8: the counter is the only loop-breaker)
n=$(( $(cat .workflow/repair.n 2>/dev/null || echo 0) + 1 )); echo "$n" >.workflow/repair.n
tail="$(tail -30 /tmp/cc_vg2.$$ 2>/dev/null)"; rm -f /tmp/cc_vg2.$$
if [ "$n" -ge 3 ]; then
  if [ -n "$br" ] && [ "$br" != HEAD ] \
     && git rev-parse -q --verify "$tag" >/dev/null 2>&1 \
     && git merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then          # MEDIUM 7: per-branch tag + ancestry gate
    orig="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo)"
    git add -A >/dev/null 2>&1
    stashed=0; git stash push -u -m cc-rescue >/dev/null 2>&1
    git stash list 2>/dev/null | head -1 | grep -q cc-rescue && stashed=1
    if [ -n "$orig" ] && git switch -c "rescue/$(date +%s)-$$" >/dev/null 2>&1; then
      [ "$stashed" = 1 ] && { git stash pop >/dev/null 2>&1 || true; }
      git add -A >/dev/null 2>&1; git commit -qm "WIP: parked after 3 red verify attempts" --no-verify >/dev/null 2>&1 || true
      if git switch "$orig" >/dev/null 2>&1; then git reset --hard "$tag" >/dev/null 2>&1 || true; fi
    else
      [ "$stashed" = 1 ] && { git stash pop >/dev/null 2>&1 || true; }
    fi
    echo 0 >.workflow/repair.n
    fail "3 consecutive red verifies. Working tree restored to last green ($tag); broken WIP parked on rescue/*. Re-read the failures and re-plan before retrying."
  fi
  # no rollback anchor — give up gracefully rather than loop forever
  echo 0 >.workflow/repair.n
  printf '%s\n%s\n' "Quality gate red after 3 attempts and no green checkpoint to restore:" "$tail" >&2
  exit 0
fi
fail "Quality gate red:
$tail
Fix the failing command and re-run /verify."
