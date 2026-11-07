# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit==0.15.2"]
# ///
# install.sh が uv で呼ぶ: Codex の config.toml を、テンプレートと既存の結合にする。
#   uv run --no-config --managed-python --quiet --script merge-config.py <テンプレート> <config.toml> <ホーム>
# テンプレートのキーはテンプレートの値にし、ほかのキーと表は値ごと残す。意味が既存と同じなら書かない。
# 書くときは既存を <config.toml>.bak.<日時> に退避する（ハードリンク）。
# 終了コード 0 = 書いた、または書く必要が無い。1 = 止めた（標準エラーに理由）か、予期しない例外。
import itertools
import os
import sys
import tempfile
import time
import tomllib

import tomlkit


def same(a, b):
    """型まで同じか（1・1.0・true を区別する）。dict はキーの集合、list は順に比べる"""
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(map(same, a, b))
    return a == b


def merge(e, t):
    """テンプレート t のキーは t の値（両方が表なら再帰）。e にだけあるキーは残す"""
    r = dict(e)
    for k, tv in t.items():
        ev = e.get(k)
        r[k] = merge(ev, tv) if isinstance(tv, dict) and isinstance(ev, dict) else tv
    return r


def apply(doc, e, t):
    """merge と同じことを tomlkit の文書 doc（e はその tomllib の読み）にその場で行う。同じ値には触らない"""
    for k, tv in t.items():
        ev = e.get(k)
        if isinstance(tv, dict) and isinstance(ev, dict):
            apply(doc[k], ev, tv)
        elif not same(ev, tv):
            doc[k] = tv


def main(template: str, config: str, home: str) -> None:
    with open(template, "rb") as f:
        t = tomllib.loads(f.read().decode("utf-8").replace("@HOME@", home))
    try:
        with open(config, "rb") as f:
            base = f.read().decode("utf-8")
        exists = True
    except FileNotFoundError:
        exists = False
        with open(template, "rb") as f:
            base = f.read().decode("utf-8").replace("@HOME@", home)
    except UnicodeDecodeError as err:
        sys.exit(f"install.sh: {config}: UTF-8 の TOML として読めない（書かずに止める）: {err}")
    try:
        e = tomllib.loads(base)
    except tomllib.TOMLDecodeError as err:
        sys.exit(f"install.sh: {config}: UTF-8 の TOML として読めない（書かずに止める）: {err}")

    em = e.get("mcp_servers")
    for name, tv in t.get("mcp_servers", {}).items():
        ev = em.get(name) if isinstance(em, dict) else None
        if isinstance(ev, dict) and "command" in ev and "url" in tv:
            sys.exit(f"install.sh: {config}: [mcp_servers.{name}] が command 方式で、テンプレートの url と混ぜると Codex が起動しない（書かずに止める。表を消すか url 方式に直す）")

    want = merge(e, t)
    if exists and same(e, want):
        return
    doc = tomlkit.parse(base)
    apply(doc, e, t)
    new = tomlkit.dumps(doc)
    if not same(tomllib.loads(new), want):
        sys.exit(f"install.sh: {config}: 書き出しを読み直すと結合の結果と違う（書かずに止める）")

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config), prefix=".config.toml.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(new)
            f.flush()
            os.fsync(f.fileno())
        if exists:
            # リンク先を渡す: Linux の CPython 3.11〜3.13 の os.link はシンボリックリンクをたどらない
            src = os.path.realpath(config)
            stamp = time.strftime("%Y%m%d%H%M%S")
            for i in itertools.chain([""], (f".{n}" for n in itertools.count(1))):
                bak = f"{config}.bak.{stamp}{i}"
                try:
                    os.link(src, bak)
                    break
                except FileExistsError:
                    pass
            print(f"backup: {config} -> {bak}")
        os.replace(tmp, config)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


main(*sys.argv[1:])
