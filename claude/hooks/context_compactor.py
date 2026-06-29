#!/usr/bin/env python3
"""context_compactor.py — PostToolUse(Grep|Glob|Bash): shrink oversized tool output.

Honest, conservative, fail-open. Only ever compacts a PLAIN-STRING tool_response and
only emits a replacement when it saves >=25% — so it can never corrupt structured output
the model depends on (e.g. exact file contents). Failure output (tracebacks / pytest
failures) is kept near-verbatim via a 4x threshold.

Kill switches (env): CC_COMPACT_DISABLE=1, CC_COMPACT_SKIP_TOOLS=Bash,Grep,
                     CC_COMPACT_ENABLE_READ=1, CC_COMPACT_SIMILAR=1
"""
from __future__ import annotations

import json
import os
import re
import sys

TRIGGER_CHARS = int(os.environ.get("CC_COMPACT_CHARS", "12000"))
TRIGGER_LINES = int(os.environ.get("CC_COMPACT_LINES", "240"))
HEAD = int(os.environ.get("CC_COMPACT_HEAD", "120"))
TAIL = int(os.environ.get("CC_COMPACT_TAIL", "60"))
JSON_SAMPLE = int(os.environ.get("CC_COMPACT_JSON_SAMPLE", "6"))
MIN_SAVING = 0.25
VERBATIM = re.compile(
    r"Traceback \(most recent call last\)|=+ FAILURES =+|\b\d+ failed\b|AssertionError"
)


def collapse_exact(lines: list[str]) -> list[str]:
    out: list[str] = []
    i, n = 0, len(lines)
    while i < n:
        j = i
        while j + 1 < n and lines[j + 1] == lines[i]:
            j += 1
        out.append(lines[i])
        if j > i:
            out.append(f"        … ({j - i + 1}× the line above)")
        i = j + 1
    return out


_NORM = [
    (re.compile(r"0x[0-9a-fA-F]+"), "0xHEX"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\S*"), "<TS>"),
    (re.compile(r"\b\d+\b"), "<N>"),
]


def _sig(line: str) -> str:
    for rx, rep in _NORM:
        line = rx.sub(rep, line)
    return line


def collapse_similar(lines: list[str]) -> list[str]:
    out: list[str] = []
    i, n = 0, len(lines)
    while i < n:
        j, sig = i, _sig(lines[i])
        while j + 1 < n and _sig(lines[j + 1]) == sig:
            j += 1
        out.append(lines[i])
        if j > i:
            out.append(f"        … ({j - i + 1}× similar lines)")
        i = j + 1
    return out


def head_tail(lines: list[str]) -> list[str]:
    if len(lines) <= HEAD + TAIL:
        return lines
    elided = len(lines) - HEAD - TAIL
    marker = f"        … elided {elided} of {len(lines)} lines — narrow the scope or Read the file directly …"
    return lines[:HEAD] + [marker] + lines[-TAIL:]


def try_json(text: str) -> str | None:
    t = text.strip()
    if not (t.startswith("{") or t.startswith("[")) or len(text) < TRIGGER_CHARS:
        return None
    try:
        obj = json.loads(t)
    except Exception:
        return None

    def summarize(o):
        if isinstance(o, dict):
            keys = list(o.keys())
            shown = {k: summarize(o[k]) for k in keys[:JSON_SAMPLE]}
            if len(keys) > JSON_SAMPLE:
                shown[f"…(+{len(keys) - JSON_SAMPLE} keys)"] = "…"
            return shown
        if isinstance(o, list):
            head = [summarize(x) for x in o[:JSON_SAMPLE]]
            if len(o) > JSON_SAMPLE:
                head.append(f"…(+{len(o) - JSON_SAMPLE} of {len(o)} items)")
            return head
        if isinstance(o, str) and len(o) > 200:
            return o[:200] + "…"
        return o

    return "// compacted JSON shape:\n" + json.dumps(summarize(obj), indent=2, ensure_ascii=False)


def compact(text: str) -> str | None:
    nlines = text.count("\n") + 1
    factor = 4 if VERBATIM.search(text) else 1
    if len(text) < TRIGGER_CHARS * factor and nlines < TRIGGER_LINES * factor:
        return None
    js = try_json(text)
    if js is not None:
        return js
    lines = text.split("\n")
    if nlines <= 3 and len(text) > TRIGGER_CHARS:  # one enormous line
        return text[:800] + f"\n        … elided {len(text) - 1000} chars …\n" + text[-200:]
    lines = collapse_exact(lines)
    if os.environ.get("CC_COMPACT_SIMILAR") == "1" and not VERBATIM.search(text):
        lines = collapse_similar(lines)
    lines = head_tail(lines)
    return "\n".join(lines)


def main() -> int:
    if os.environ.get("CC_COMPACT_DISABLE") == "1":
        return 0
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    tool = data.get("tool_name") or data.get("tool") or ""
    if tool == "Read" and os.environ.get("CC_COMPACT_ENABLE_READ") != "1":
        return 0
    skip = [s.strip() for s in os.environ.get("CC_COMPACT_SKIP_TOOLS", "").split(",") if s.strip()]
    if tool and tool in skip:
        return 0
    resp = data.get("tool_response")
    if not isinstance(resp, str) or not resp:  # only plain-string output — never corrupt structured/image
        return 0
    try:
        new = compact(resp)
    except Exception:
        return 0
    if new is None or len(new) >= len(resp) * (1 - MIN_SAVING):
        return 0
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": new}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
