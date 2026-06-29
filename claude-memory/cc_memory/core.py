"""cc_memory.core — searchable, per-directory long-term memory.

Backend: sqlite + FTS5 (always), optional sqlite-vec + fastembed for semantic search.
Data lives at $CC_MEMORY_DB (default ~/.local/share/cc-memory/memory.db) — NEVER in a repo.
Consolidation (/dream) is "CLI emits candidates -> session model reasons -> CLI applies",
applied in a single transaction. Forgetting is reversible (archive table only; no hard delete).
"""

from __future__ import annotations

import json
import math
import os
import re
import sqlite3
import subprocess
import time
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

DEFAULT_DB = Path.home() / ".local" / "share" / "cc-memory" / "memory.db"
VALID_TYPES = ("episodic", "semantic", "procedural")
_VEC_OK = False


def db_path() -> Path:
    return Path(os.environ.get("CC_MEMORY_DB", str(DEFAULT_DB))).expanduser()


# --------------------------------------------------------------------------- connection
def connect(path: str | os.PathLike[str] | None = None) -> sqlite3.Connection:
    p = Path(path) if path else db_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(p))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=3000")        # M-4: MCP + hooks may overlap
    conn.execute("PRAGMA synchronous=NORMAL")        # M-4
    _maybe_load_vec(conn)
    init_db(conn)
    return conn


def _maybe_load_vec(conn: sqlite3.Connection) -> bool:
    global _VEC_OK
    _VEC_OK = False
    try:
        import sqlite_vec  # type: ignore
    except Exception:
        return False  # extension not installed -> never touch enable_load_extension on the common path
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        _VEC_OK = True
    except Exception:
        _VEC_OK = False
    finally:
        try:
            conn.enable_load_extension(False)  # always re-disable
        except Exception:
            pass
    return _VEC_OK


def fts_available(conn: sqlite3.Connection) -> bool:
    try:
        conn.execute("CREATE VIRTUAL TABLE IF NOT EXISTS _fts_probe USING fts5(x)")
        conn.execute("DROP TABLE IF EXISTS _fts_probe")
        return True
    except Exception:
        return False


_DDL = """
CREATE TABLE IF NOT EXISTS memories(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope TEXT NOT NULL,
  ts REAL NOT NULL,
  last_accessed REAL NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('episodic','semantic','procedural')),
  content TEXT NOT NULL,
  concepts TEXT NOT NULL DEFAULT '[]',
  files TEXT NOT NULL DEFAULT '[]',
  importance REAL NOT NULL DEFAULT 0.5,
  confidence REAL NOT NULL DEFAULT 0.6,
  frequency INTEGER NOT NULL DEFAULT 1,
  source TEXT NOT NULL DEFAULT 'manual',
  session_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_mem_scope ON memories(scope);
CREATE INDEX IF NOT EXISTS idx_mem_scope_type ON memories(scope, type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mem_session_end
  ON memories(session_id, source) WHERE source='session-end';
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts
  USING fts5(content, concepts, content='memories', content_rowid='id');
CREATE TRIGGER IF NOT EXISTS mem_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, content, concepts) VALUES (new.id, new.content, new.concepts);
END;
CREATE TRIGGER IF NOT EXISTS mem_ad AFTER DELETE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, content, concepts)
    VALUES('delete', old.id, old.content, old.concepts);
END;
CREATE TRIGGER IF NOT EXISTS mem_au AFTER UPDATE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, content, concepts)
    VALUES('delete', old.id, old.content, old.concepts);
  INSERT INTO memories_fts(rowid, content, concepts) VALUES (new.id, new.content, new.concepts);
END;
CREATE TABLE IF NOT EXISTS archive(
  id INTEGER PRIMARY KEY, scope TEXT, ts REAL, last_accessed REAL, type TEXT, content TEXT,
  concepts TEXT, files TEXT, importance REAL, confidence REAL, frequency INTEGER, source TEXT,
  session_id TEXT, archived_at REAL
);
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
"""


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(_DDL)
    if _VEC_OK:
        conn.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS memories_vec "
            "USING vec0(memory_id INTEGER PRIMARY KEY, scope TEXT, embedding FLOAT[384])"
        )
    conn.commit()


# --------------------------------------------------------------------------- scope
def resolve_scope(cwd: str | None = None) -> str:
    d = Path(cwd or os.getcwd()).expanduser().resolve()
    try:
        top = subprocess.run(
            ["git", "-C", str(d), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=3,
        ).stdout.strip()
        if top:
            return top
    except Exception:
        pass
    return str(d)


# --------------------------------------------------------------------------- secret guard
_STRUCTURED = [
    re.compile(r"(?i)(api[_-]?key|secret|token|password|passwd|client[_-]?secret|private[_-]?key)[\"']?\s*[:=]\s*\S"),
    re.compile(r"://[^\s:/@]+:[^\s:/@]+@"),  # URL credentials  scheme://user:pass@host
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}"),
]


def _shannon(s: str) -> float:
    if not s:
        return 0.0
    n = len(s)
    return -sum((v / n) * math.log2(v / n) for v in Counter(s).values())


def _high_entropy_tokens(line: str) -> list[str]:
    hits: list[str] = []
    for tok in re.findall(r"[A-Za-z0-9_\-./+=]{24,}", line):
        if re.fullmatch(r"[0-9a-fA-F]{40}", tok):          # H-3: git SHA (exactly 40 hex) -> skip
            continue
        if (re.fullmatch(r"[0-9a-fA-F]{24,}", tok) and _shannon(tok) > 3.0) or _shannon(tok) > 4.5:
            hits.append(tok)
    return hits


def find_secrets(text: str) -> tuple[list[str], list[str]]:
    """(structured, entropy). structured -> reject candidates; entropy -> mask only (H-3)."""
    structured, entropy = [], []
    for line in text.splitlines():
        if any(rx.search(line) for rx in _STRUCTURED):
            structured.append("structured-secret-pattern")  # MEDIUM 5: never echo the secret text itself
        entropy += _high_entropy_tokens(line)
    return structured, entropy


def guard_content(text: str, mode: str = "reject") -> str:
    structured, entropy = find_secrets(text)
    if structured and mode == "reject":
        raise ValueError("refusing to store likely secret (matched a structured secret pattern)")
    out = text
    for tok in set(entropy):
        out = out.replace(tok, "«redacted»")
    if structured and mode == "mask":
        for rx in _STRUCTURED:
            out = rx.sub("«redacted-secret»", out)
    return out


# --------------------------------------------------------------------------- writes
def remember(
    conn: sqlite3.Connection,
    *,
    content: str,
    scope: str,
    type: str = "episodic",
    concepts: list[str] | None = None,
    files: list[str] | None = None,
    importance: float = 0.5,
    confidence: float = 0.6,
    source: str = "manual",
    session_id: str | None = None,
    secret_mode: str = "reject",
    commit: bool = True,
) -> int:
    if type not in VALID_TYPES:
        raise ValueError(f"type must be one of {VALID_TYPES}, got {type!r}")
    content = guard_content(content, mode=secret_mode)
    now = time.time()
    cur = conn.execute(
        "INSERT INTO memories(scope,ts,last_accessed,type,content,concepts,files,"
        "importance,confidence,frequency,source,session_id) VALUES(?,?,?,?,?,?,?,?,?,1,?,?)",
        (scope, now, now, type, content, json.dumps(concepts or []), json.dumps(files or []),
         importance, confidence, source, session_id),
    )
    if commit:
        conn.commit()
    return int(cur.lastrowid)


def archive_memory(conn: sqlite3.Connection, mid: int, commit: bool = True) -> bool:
    m = conn.execute("SELECT * FROM memories WHERE id=?", (mid,)).fetchone()
    if not m:
        return False
    conn.execute(
        "INSERT OR REPLACE INTO archive(id,scope,ts,last_accessed,type,content,concepts,files,"
        "importance,confidence,frequency,source,session_id,archived_at) "
        "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (m["id"], m["scope"], m["ts"], m["last_accessed"], m["type"], m["content"], m["concepts"],
         m["files"], m["importance"], m["confidence"], m["frequency"], m["source"], m["session_id"],
         time.time()),
    )
    conn.execute("DELETE FROM memories WHERE id=?", (mid,))
    if commit:
        conn.commit()
    return True


def restore_archived(conn: sqlite3.Connection, mid: int, commit: bool = True) -> bool:
    a = conn.execute("SELECT * FROM archive WHERE id=?", (mid,)).fetchone()
    if not a:
        return False
    conn.execute(
        "INSERT OR REPLACE INTO memories(id,scope,ts,last_accessed,type,content,concepts,files,"
        "importance,confidence,frequency,source,session_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (a["id"], a["scope"], a["ts"], a["last_accessed"], a["type"], a["content"], a["concepts"],
         a["files"], a["importance"], a["confidence"], a["frequency"], a["source"], a["session_id"]),
    )
    conn.execute("DELETE FROM archive WHERE id=?", (mid,))
    if commit:
        conn.commit()
    return True


# --------------------------------------------------------------------------- reads
def _fts_query(q: str) -> str:
    terms = re.findall(r"\w+", q)
    return " OR ".join(f'"{t}"' for t in terms) if terms else '""'


def recall(
    conn: sqlite3.Connection,
    query: str,
    scope: str | None = None,
    limit: int = 8,
    types: Iterable[str] | None = None,
) -> list[dict[str, Any]]:
    relevance: dict[int, float] = {}
    try:
        sql = ("SELECT m.id AS id, bm25(memories_fts) AS rank FROM memories_fts "
               "JOIN memories m ON m.id = memories_fts.rowid WHERE memories_fts MATCH ?")
        params: list[Any] = [_fts_query(query)]
        if scope:
            sql += " AND m.scope=?"
            params.append(scope)
        sql += " ORDER BY rank LIMIT 50"
        for r in conn.execute(sql, params):
            relevance[r["id"]] = -float(r["rank"])      # bm25: lower is better
    except Exception:
        relevance = {}
    if not relevance:                                   # fallback: substring
        sql = "SELECT id FROM memories WHERE content LIKE ?"
        params = [f"%{query}%"]
        if scope:
            sql += " AND scope=?"
            params.append(scope)
        for r in conn.execute(sql + " LIMIT 50", params):
            relevance[r["id"]] = 0.3
    if not relevance:
        return []
    ids = list(relevance)
    type_sql, tparams = "", []
    if types:
        types = list(types)
        type_sql = " AND type IN (%s)" % ",".join("?" * len(types))
        tparams = types
    rows = conn.execute(
        "SELECT * FROM memories WHERE id IN (%s)%s" % (",".join("?" * len(ids)), type_sql),
        ids + tparams,
    ).fetchall()
    now = time.time()
    rel_max = max(relevance.values()) or 1.0
    scored: list[tuple[float, sqlite3.Row]] = []
    for m in rows:
        recency = math.exp(-(now - m["last_accessed"]) / (14 * 86400))   # τ = 14d
        freq_sat = m["frequency"] / (m["frequency"] + 3)
        rel = relevance[m["id"]] / rel_max
        score = 0.25 * recency + 0.25 * m["importance"] + 0.15 * freq_sat + 0.35 * rel
        scored.append((score, m))
    scored.sort(key=lambda x: -x[0])
    top = scored[:limit]
    for _, m in top:
        conn.execute("UPDATE memories SET last_accessed=?, frequency=frequency+1 WHERE id=?", (now, m["id"]))
    conn.commit()
    return [{**dict(m), "score": round(s, 3)} for s, m in top]


def digest(conn: sqlite3.Connection, scope: str, top: int = 8) -> list[dict[str, Any]]:
    rows = conn.execute(
        "SELECT * FROM memories WHERE scope=? "
        "ORDER BY importance * 0.5 + (frequency * 1.0 / (frequency + 3)) * 0.5 DESC, last_accessed DESC "
        "LIMIT ?",
        (scope, top),
    ).fetchall()
    return [dict(r) for r in rows]


# --------------------------------------------------------------------------- meta
def _meta_get(conn: sqlite3.Connection, key: str, default: str | None = None) -> str | None:
    r = conn.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return r["value"] if r else default


def _meta_set(conn: sqlite3.Connection, key: str, value: str, commit: bool = True) -> None:
    conn.execute(
        "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, value),
    )
    if commit:
        conn.commit()


# --------------------------------------------------------------------------- dream
def dream_emit(conn: sqlite3.Connection, scope: str) -> dict[str, Any]:
    since = float(_meta_get(conn, f"last_dream:{scope}", "0") or 0)
    episodic = [
        dict(r) for r in conn.execute(
            "SELECT * FROM memories WHERE scope=? AND type='episodic' AND ts > ? ORDER BY ts",
            (scope, since),
        ).fetchall()
    ]
    existing = [
        dict(r) for r in conn.execute(
            "SELECT id,type,content,concepts FROM memories WHERE scope=? AND type IN ('semantic','procedural')",
            (scope,),
        ).fetchall()
    ]
    return {"scope": scope, "since": since, "episodic": episodic, "existing": existing}


def dream_apply(conn: sqlite3.Connection, scope: str, ops: dict[str, Any]) -> dict[str, int]:
    report = {"created": 0, "promoted": 0, "reflected": 0, "forgotten": 0}
    with conn:                                          # H-1: one transaction
        for s in ops.get("create_semantic", []):
            remember(conn, content=s["content"], scope=scope, type="semantic",
                     concepts=s.get("concepts"), importance=s.get("importance", 0.6),
                     confidence=s.get("confidence", 0.7), source="dream", secret_mode="mask", commit=False)
            report["created"] += 1
        for p in ops.get("create_procedural", []):
            remember(conn, content=p["content"], scope=scope, type="procedural",
                     concepts=p.get("concepts"), importance=p.get("importance", 0.6),
                     confidence=p.get("confidence", 0.7), source="dream", secret_mode="mask", commit=False)
            report["promoted"] += 1
        for r in ops.get("reflections", []):
            remember(conn, content=r["content"], scope=scope, type="semantic",
                     concepts=r.get("concepts"), importance=r.get("importance", 0.7),
                     confidence=r.get("confidence", 0.6), source="reflect", secret_mode="mask", commit=False)
            report["reflected"] += 1
        for mid in list(ops.get("consume_episodic_ids", [])) + list(ops.get("archive_ids", [])):
            if archive_memory(conn, int(mid), commit=False):
                report["forgotten"] += 1
        _meta_set(conn, f"last_dream:{scope}", str(time.time()), commit=False)
    return report


# --------------------------------------------------------------------------- transcript ingest (session-end)
def _iter_jsonl(path: str) -> Iterable[dict[str, Any]]:
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
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


def _text_of(obj: Any) -> str:
    parts: list[str] = []
    if isinstance(obj, str):
        return obj
    if isinstance(obj, dict):
        if isinstance(obj.get("text"), str):
            parts.append(obj["text"])
        for v in obj.values():
            parts.append(_text_of(v))
    elif isinstance(obj, list):
        for v in obj:
            parts.append(_text_of(v))
    return " ".join(p for p in parts if p)


def ingest_transcript(
    conn: sqlite3.Connection, transcript_path: str, scope: str, session_id: str, commit: bool = True
) -> int | None:
    files: set[str] = set()
    commands: list[str] = []
    first_user: str | None = None
    last_assistant: str | None = None
    for obj in _iter_jsonl(transcript_path):
        for node in _walk(obj):
            name = node.get("name") or node.get("tool_name")
            inp = node.get("input") or node.get("tool_input")
            if isinstance(inp, dict):
                if name in ("Edit", "Write", "MultiEdit", "NotebookEdit") and inp.get("file_path"):
                    files.add(str(inp["file_path"]))
                if name == "Bash" and inp.get("command"):
                    commands.append(str(inp["command"])[:120])
        role = obj.get("role") or (obj.get("message") or {}).get("role")
        content = obj.get("content")
        if content is None and isinstance(obj.get("message"), dict):
            content = obj["message"].get("content")
        text = _text_of(content).strip()
        if role == "user" and text and first_user is None and not text.startswith("<"):
            first_user = text
        if role == "assistant" and text:
            last_assistant = text
    if not files and not commands:                      # L-2: empty session -> skip
        return None
    parts: list[str] = []
    if first_user:
        parts.append(f"goal: {first_user[:300]}")
    if files:
        parts.append("files: " + ", ".join(sorted(files))[:400])
    if commands:
        parts.append("commands: " + "; ".join(commands[:8])[:400])
    if last_assistant:
        parts.append(f"outcome: {last_assistant[:300]}")
    content = guard_content("\n".join(parts), mode="mask")
    try:
        return remember(
            conn, content=content, scope=scope, type="episodic", files=sorted(files),
            importance=0.3, confidence=0.4, source="session-end", session_id=session_id,
            secret_mode="mask", commit=commit,
        )
    except sqlite3.IntegrityError:                      # idempotent per (session_id, source)
        return None


# --------------------------------------------------------------------------- backup / reindex
def export_scope(conn: sqlite3.Connection, scope: str | None = None) -> str:
    sql = "SELECT * FROM memories"
    params: list[Any] = []
    if scope:
        sql += " WHERE scope=?"
        params = [scope]
    return "\n".join(json.dumps(dict(r)) for r in conn.execute(sql, params))


def import_dump(conn: sqlite3.Connection, text: str, commit: bool = True) -> int:
    n = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            m = json.loads(line)
            remember(
                conn, content=m["content"], scope=m["scope"], type=m.get("type", "episodic"),
                concepts=json.loads(m.get("concepts", "[]")), files=json.loads(m.get("files", "[]")),
                importance=m.get("importance", 0.5), confidence=m.get("confidence", 0.6),
                source=m.get("source", "import"), secret_mode="mask", commit=False,
            )
            n += 1
        except Exception:
            continue
    if commit:
        conn.commit()
    return n


def reindex(conn: sqlite3.Connection) -> dict[str, Any]:
    """Rebuild FTS (and re-embed for vec when available — stub until fastembed wired)."""
    conn.execute("INSERT INTO memories_fts(memories_fts) VALUES('rebuild')")
    conn.commit()
    return {"fts": "rebuilt", "vec": _VEC_OK}
