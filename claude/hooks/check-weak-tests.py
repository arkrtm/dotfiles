#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""check-weak-tests.py — flag tautological / assertion-free test functions via AST.

Modes:
  (default, stdin) PostToolUse hook: warn via additionalContext on the edited test file (advisory)
  files <a.py> ...  pre-commit gate: print findings to stderr, exit 1 if any (HARD)
"""
from __future__ import annotations

import ast
import json
import pathlib
import sys


def weak_findings(src: str, path: str) -> list[str]:
    out: list[str] = []
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if not (isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test")):
            continue
        asserts = [n for n in ast.walk(node) if isinstance(n, ast.Assert)]
        has_raises = any(
            isinstance(n, ast.withitem) and "raises" in ast.dump(n.context_expr)
            for n in ast.walk(node)
        )
        calls_assert = any(
            isinstance(n, ast.Call)
            and (
                (isinstance(n.func, ast.Attribute) and n.func.attr.startswith("assert"))
                or (isinstance(n.func, ast.Name) and n.func.id.startswith("assert"))
            )
            for n in ast.walk(node)
        )
        if not asserts and not has_raises and not calls_assert:
            out.append(f"{path}:{node.lineno}: test '{node.name}' has no assertion / pytest.raises")
            continue
        for a in asserts:
            if isinstance(a.test, ast.Constant):
                out.append(
                    f"{path}:{a.lineno}: test '{node.name}' asserts a constant ({a.test.value!r})"
                )
    return out


def _read(path: str) -> str:
    return pathlib.Path(path).read_text(encoding="utf-8", errors="ignore")


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "files":
        bad: list[str] = []
        for f in args[1:]:
            p = pathlib.Path(f)
            if p.suffix == ".py" and p.exists():
                bad += weak_findings(_read(f), f)
        if bad:
            print("\n".join(bad), file=sys.stderr)
            return 1
        return 0

    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    f = (data.get("tool_input") or {}).get("file_path", "")
    name = pathlib.Path(f).name
    is_test = "tests/" in f.replace("\\", "/") or name.startswith("test_") or name.endswith("_test.py")
    if not (f.endswith(".py") and is_test and pathlib.Path(f).exists()):
        return 0
    try:
        findings = weak_findings(_read(f), f)
    except Exception:
        return 0
    if findings:
        msg = "Weak-test check (advisory):\n" + "\n".join(findings)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
