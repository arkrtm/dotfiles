"""cc_memory.mcp_server — FastMCP stdio server exposing memory_recall / memory_remember.

Wired via: claude mcp add --scope user cc-memory -- mise exec -- \
           uv run --project ~/dotfiles/claude-memory cc-memory mcp
"""

from __future__ import annotations

import sys

from . import core


def run() -> int:
    try:
        from mcp.server.fastmcp import FastMCP
    except Exception as e:  # pragma: no cover - requires the 'mcp' package
        print(f"cc-memory mcp requires the 'mcp' package (uv sync the project): {e}", file=sys.stderr)
        return 1

    mcp = FastMCP("cc-memory")

    @mcp.tool()
    def memory_recall(query: str, scope: str = "", limit: int = 8) -> list[dict]:
        """Recall long-term memories relevant to `query` for THIS project.

        Pass the project's absolute path as `scope` — the SessionStart message prints the exact
        path. Leave it empty to use the current directory's project scope. Returns scored memories.
        """
        conn = core.connect()
        return core.recall(conn, query, scope=scope or core.resolve_scope(), limit=limit)

    @mcp.tool()
    def memory_remember(
        content: str,
        scope: str = "",
        type: str = "semantic",
        concepts: list[str] | None = None,
        files: list[str] | None = None,
        importance: float = 0.6,
    ) -> dict:
        """Store a durable memory for THIS project.

        Pass the project's absolute path as `scope` (printed at SessionStart). `type` is
        semantic (a fact), procedural (a how-to), or episodic (an event). Likely secrets are
        refused. Use this when you learn something worth remembering across sessions.
        """
        if type not in core.VALID_TYPES:
            return {"error": f"type must be one of {core.VALID_TYPES}"}
        conn = core.connect()
        try:
            mid = core.remember(conn, content=content, scope=scope or core.resolve_scope(),
                                type=type, concepts=concepts, files=files,
                                importance=importance, source="mcp")
        except ValueError as e:
            return {"error": str(e)}
        return {"id": mid, "scope": scope or core.resolve_scope()}

    mcp.run()
    return 0
