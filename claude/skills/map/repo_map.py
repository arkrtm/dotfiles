#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""repo_map.py — compact Python symbol map ranked by import references. stdlib only."""
from __future__ import annotations

import ast
import collections
import pathlib
import subprocess
import sys


def py_files() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "*.py"], capture_output=True, text=True, check=True
        ).stdout
        files = [line for line in out.splitlines() if line]
        if files:
            return files
    except Exception:
        pass
    return [str(p) for p in pathlib.Path(".").rglob("*.py")]


def main() -> int:
    files = py_files()
    refs: collections.Counter[str] = collections.Counter()
    info: dict[str, list[str]] = {}
    for f in files:
        try:
            tree = ast.parse(pathlib.Path(f).read_text(encoding="utf-8", errors="ignore"))
        except Exception:
            continue
        syms: list[str] = []
        for n in tree.body:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                doc = (ast.get_docstring(n) or "").splitlines()[:1]
                kind = "class" if isinstance(n, ast.ClassDef) else "def"
                syms.append(f"  {kind} {n.name}" + (f" — {doc[0]}" if doc else ""))
            elif isinstance(n, ast.ImportFrom):
                refs[(n.module or "").split(".")[0]] += 1
            elif isinstance(n, ast.Import):
                for a in n.names:
                    refs[a.name.split(".")[0]] += 1
        info[f] = syms
    for f in sorted(files, key=lambda f: -refs.get(pathlib.Path(f).stem, 0)):
        if info.get(f):
            print(f"{f}  (refs={refs.get(pathlib.Path(f).stem, 0)})")
            print("\n".join(info[f]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
