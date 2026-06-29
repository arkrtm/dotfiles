#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""session_analyzer.py — mine Claude Code transcripts for things worth promoting to a
skill / CLAUDE.md line / hook rule. Dependency-free and defensive (transcript JSONL is an
undocumented, evolving format — every access is best-effort).

Commands:
  analyze --session <id> --cwd <path>                -> candidates JSON (for /learn)
  journal                                            -> append a scrubbed 1-line digest (SessionEnd, stdin)
  nudge                                              -> one-line reminder since last /learn (SessionStart)
  mark-learned --session <id>                        -> advance the watermark
  scan                                               -> stdin secret gate: exit 2 if a structured secret

Data: $CC_LEARN_HOME (default ~/.local/state/cc-learn): journal/YYYY-MM.jsonl + last-learn.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Iterable

CORRECTION = re.compile(
    r"(?i)^\s*(no[,.\s]|don'?t\b|do not\b|stop\b|revert\b|undo\b|that'?s (wrong|not right)|"
    r"why did you\b|you (broke|removed|deleted)\b|not what i\b|that'?s not what)"
)
STRUCTURED = [
    re.compile(r"(?i)(api[_-]?key|secret|token|password|passwd|client[_-]?secret|private[_-]?key)[\"']?\s*[:=]\s*\S"),
    re.compile(r"://[^\s:/@]+:[^\s:/@]+@"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}"),
]


def learn_home() -> Path:
    return Path(os.environ.get("CC_LEARN_HOME", str(Path.home() / ".local" / "state" / "cc-learn"))).expanduser()


def projects_root() -> Path:
    return Path.home() / ".claude" / "projects"


def slug_of(cwd: str) -> str:
    return str(Path(cwd).expanduser().resolve()).replace("/", "-")


def _iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    try:
        with path.open(encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except Exception:
                    continue
    except Exception:
        return


def _walk(obj: Any) -> Iterable[dict[str, Any]]:
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from _walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk(v)


def _text(obj: Any) -> str:
    if isinstance(obj, str):
        return obj
    parts: list[str] = []
    if isinstance(obj, dict):
        if isinstance(obj.get("text"), str):
            parts.append(obj["text"])
        else:
            for v in obj.values():
                parts.append(_text(v))
    elif isinstance(obj, list):
        for v in obj:
            parts.append(_text(v))
    return " ".join(p for p in parts if p)


def _transcripts(session: str, cwd: str) -> list[Path]:
    root = projects_root() / slug_of(cwd)
    found: list[Path] = []
    if root.exists():
        main = root / f"{session}.jsonl"
        if main.exists():
            found.append(main)
        found += [p for p in root.glob(f"**/{session}*.jsonl") if p not in found]
    if not found:
        found = [p for p in projects_root().glob(f"**/{session}*.jsonl")]
    return found


def _has_tool(obj: dict[str, Any]) -> bool:
    return any((n.get("name") or n.get("tool_name")) for n in _walk(obj))


def analyze(session: str, cwd: str) -> dict[str, Any]:
    corrections: list[str] = []
    greps: dict[str, int] = {}
    reads: dict[str, int] = {}
    scripts: dict[str, int] = {}
    tools = 0
    prev_assistant_tool = False
    for path in _transcripts(session, cwd):
        for obj in _iter_jsonl(path):
            for node in _walk(obj):
                name = node.get("name") or node.get("tool_name")
                inp = node.get("input") or node.get("tool_input")
                if not (name and isinstance(inp, dict)):
                    continue
                tools += 1
                if name == "Grep" and inp.get("pattern"):
                    greps[str(inp["pattern"])] = greps.get(str(inp["pattern"]), 0) + 1
                elif name == "Read" and inp.get("file_path"):
                    reads[str(inp["file_path"])] = reads.get(str(inp["file_path"]), 0) + 1
                elif name == "Bash" and inp.get("command"):
                    cmd = str(inp["command"])
                    if re.search(r"python3? -c|<<'?[A-Z]+|/tmp/|mktemp", cmd):
                        key = re.sub(r"\d+", "N", cmd[:60])
                        scripts[key] = scripts.get(key, 0) + 1
            role = obj.get("role") or (obj.get("message") or {}).get("role")
            content = obj.get("content")
            if content is None and isinstance(obj.get("message"), dict):
                content = obj["message"].get("content")
            text = _text(content).strip()
            if role == "user" and text and prev_assistant_tool and CORRECTION.search(text):
                corrections.append(text[:120])
            prev_assistant_tool = role == "assistant" and _has_tool(obj)
    return {
        "session": session,
        "cwd": cwd,
        "tool_count": tools,
        "repeated_corrections": corrections[:10],
        "missing_context": {
            "repeated_reads": sorted([f for f, c in reads.items() if c >= 3]),
            "repeated_greps": sorted([p for p, c in greps.items() if c >= 3]),
        },
        "helper_scripts": sorted([k for k, c in scripts.items() if c >= 2]),
        "single_session": True,
    }


def journal() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    sid = data.get("session_id", "?")
    cwd = data.get("cwd") or os.getcwd()
    tx = data.get("transcript_path")
    corr = 0
    files: set[str] = set()
    if tx and Path(tx).exists():
        prev = False
        for obj in _iter_jsonl(Path(tx)):
            for node in _walk(obj):
                name = node.get("name") or node.get("tool_name")
                inp = node.get("input") or node.get("tool_input")
                if name in ("Edit", "Write") and isinstance(inp, dict) and inp.get("file_path"):
                    files.add(str(inp["file_path"]))
            role = obj.get("role") or (obj.get("message") or {}).get("role")
            content = obj.get("content")
            if content is None and isinstance(obj.get("message"), dict):
                content = obj["message"].get("content")   # MEDIUM 2: payload is under message.content
            text = _text(content).strip()
            if role == "user" and prev and CORRECTION.search(text):
                corr += 1
            prev = role == "assistant" and _has_tool(obj)
    line = {"ts": time.time(), "session": sid, "cwd": cwd, "corrections": corr, "files": len(files)}
    jdir = learn_home() / "journal"
    jdir.mkdir(parents=True, exist_ok=True)
    with (jdir / f"{time.strftime('%Y-%m')}.jsonl").open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(line) + "\n")
    return 0


def nudge() -> int:
    last = 0.0
    lf = learn_home() / "last-learn.json"
    if lf.exists():
        try:
            last = float(json.loads(lf.read_text()).get("ts", 0))
        except Exception:
            last = 0.0
    n_sessions = n_corr = 0
    jdir = learn_home() / "journal"
    if jdir.exists():
        for jf in jdir.glob("*.jsonl"):
            for obj in _iter_jsonl(jf):
                if float(obj.get("ts", 0)) > last:
                    n_sessions += 1
                    n_corr += int(obj.get("corrections", 0))
    if n_sessions == 0:
        return 0
    print(f"{n_sessions} sessions and {n_corr} repeated corrections since your last /learn — consider running /learn.")
    return 0


def mark_learned(session: str) -> int:
    h = learn_home()
    h.mkdir(parents=True, exist_ok=True)
    (h / "last-learn.json").write_text(json.dumps({"ts": time.time(), "session": session}))
    print("marked")
    return 0


def scan() -> int:
    text = sys.stdin.read()
    for rx in STRUCTURED:
        if rx.search(text):
            print("ABORT: snippet contains a likely secret; refusing to write it.", file=sys.stderr)
            return 2
    # high-entropy tokens -> mask (never block on these alone)
    masked = re.sub(r"\b(?![0-9a-fA-F]{40}\b)[A-Za-z0-9_\-]{32,}\b", "«redacted»", text)
    sys.stdout.write(masked)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="session_analyzer.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("analyze")
    a.add_argument("--session", required=True)
    a.add_argument("--cwd", default=os.getcwd())
    sub.add_parser("journal")
    sub.add_parser("nudge")
    m = sub.add_parser("mark-learned")
    m.add_argument("--session", required=True)
    sub.add_parser("scan")
    args = p.parse_args()
    if args.cmd == "analyze":
        print(json.dumps(analyze(args.session, args.cwd), ensure_ascii=False, indent=2))
        return 0
    if args.cmd == "journal":
        return journal()
    if args.cmd == "nudge":
        return nudge()
    if args.cmd == "mark-learned":
        return mark_learned(args.session)
    if args.cmd == "scan":
        return scan()
    return 1


if __name__ == "__main__":
    sys.exit(main())
