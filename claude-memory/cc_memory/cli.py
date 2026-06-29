"""cc_memory.cli — command line for cc-memory (also the /recall /remember /dream backend
and the SessionStart/SessionEnd hook entry point)."""

from __future__ import annotations

import argparse
import json
import sys

from . import core


def _print(obj: object) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def _split(s: str) -> list[str]:
    return [x.strip() for x in s.split(",") if x.strip()] if s else []


def _read_text(args: argparse.Namespace) -> str:
    if getattr(args, "stdin", False):
        return sys.stdin.read()
    if getattr(args, "file", None):
        with open(args.file, encoding="utf-8") as fh:
            return fh.read()
    if args.text is not None:
        return args.text
    return sys.stdin.read()


def _can_load_ext(conn) -> bool:
    try:
        conn.enable_load_extension(True)
        conn.enable_load_extension(False)
        return True
    except Exception:
        return False


def _hook(event: str) -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    scope = core.resolve_scope(data.get("cwd") or None)
    conn = core.connect()
    if event == "session-start":
        mems = core.digest(conn, scope, top=8)
        tail = f"\n\ncc-memory scope for this project: {scope} — pass this exact path as 'scope' to memory_recall/memory_remember."
        if mems:
            body = "Relevant long-term memory for this project:\n" + "\n".join(
                f"- [{m['type']}] {m['content'][:160]}" for m in mems
            )
        else:
            body = "No stored memory for this project yet."
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": body + tail}}))
        return 0
    if event == "session-end":
        tx = data.get("transcript_path")
        sid = data.get("session_id")   # LOW 4: keep NULL distinct in the partial unique index (no collapse)
        if tx:
            try:
                core.ingest_transcript(conn, tx, scope, sid)
            except Exception:
                pass
        return 0
    return 0


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="cc-memory")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init")
    sub.add_parser("reindex")
    sub.add_parser("mcp")
    sp = sub.add_parser("scope")
    sp.add_argument("--cwd", default=None)

    r = sub.add_parser("remember")
    r.add_argument("text", nargs="?", default=None)
    r.add_argument("--stdin", action="store_true")
    r.add_argument("--file")
    r.add_argument("--scope", default=None)
    r.add_argument("--type", default="episodic")
    r.add_argument("--concepts", default="")
    r.add_argument("--files", default="")
    r.add_argument("--importance", type=float, default=0.5)
    r.add_argument("--confidence", type=float, default=0.6)
    r.add_argument("--source", default="manual")

    rc = sub.add_parser("recall")
    rc.add_argument("query")
    rc.add_argument("--scope", default=None)
    rc.add_argument("--limit", type=int, default=8)
    rc.add_argument("--type", action="append")
    rc.add_argument("--all-scopes", action="store_true")

    dg = sub.add_parser("digest")
    dg.add_argument("--scope", default=None)
    dg.add_argument("--top", type=int, default=8)

    dr = sub.add_parser("dream")
    dr.add_argument("--scope", default=None)
    dr.add_argument("--emit-candidates", action="store_true")
    dr.add_argument("--apply", metavar="FILE", help="operations JSON path, or - for stdin")

    ex = sub.add_parser("export")
    ex.add_argument("--scope", default=None, help="omit to export ALL scopes")
    im = sub.add_parser("import")
    im.add_argument("--file")
    rs = sub.add_parser("restore")
    rs.add_argument("--archive", type=int, required=True)

    hk = sub.add_parser("hook")
    hk.add_argument("event", choices=["session-start", "session-end"])
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.cmd == "mcp":
        from .mcp_server import run
        return run()
    if args.cmd == "hook":
        return _hook(args.event)

    conn = core.connect()
    if args.cmd == "init":
        _print({"db": str(core.db_path()), "fts": core.fts_available(conn),
                "vec": core._VEC_OK, "load_extension": _can_load_ext(conn)})
        return 0
    if args.cmd == "scope":
        print(core.resolve_scope(args.cwd))
        return 0
    if args.cmd == "export":
        print(core.export_scope(conn, args.scope))
        return 0
    if args.cmd == "import":
        text = open(args.file, encoding="utf-8").read() if args.file else sys.stdin.read()
        _print({"imported": core.import_dump(conn, text)})
        return 0
    if args.cmd == "restore":
        _print({"restored": core.restore_archived(conn, args.archive)})
        return 0
    if args.cmd == "reindex":
        _print(core.reindex(conn))
        return 0

    scope = args.scope or core.resolve_scope()
    if args.cmd == "remember":
        try:
            mid = core.remember(conn, content=_read_text(args), scope=scope, type=args.type,
                                concepts=_split(args.concepts), files=_split(args.files),
                                importance=args.importance, confidence=args.confidence, source=args.source)
        except ValueError as e:
            print(f"refused: {e}", file=sys.stderr)
            return 2
        _print({"id": mid, "scope": scope})
        return 0
    if args.cmd == "recall":
        _print(core.recall(conn, args.query, scope=None if args.all_scopes else scope,
                           limit=args.limit, types=args.type))
        return 0
    if args.cmd == "digest":
        _print(core.digest(conn, scope, top=args.top))
        return 0
    if args.cmd == "dream":
        if args.emit_candidates:
            _print(core.dream_emit(conn, scope))
            return 0
        if args.apply:
            raw = sys.stdin.read() if args.apply == "-" else open(args.apply, encoding="utf-8").read()
            _print(core.dream_apply(conn, scope, json.loads(raw)))
            return 0
        print("dream needs --emit-candidates or --apply", file=sys.stderr)
        return 2
    return 1


if __name__ == "__main__":
    sys.exit(main())
