"""bin/geoview（拡張子なし、shebang は Windows で効かない）を uv tool の環境で実行する。

リポジトリは環境変数 DOTFILES、なければ ~/dotfiles。
"""

import os
import runpy
import sys


def main():
    dotfiles = os.environ.get("DOTFILES") or os.path.expanduser("~/dotfiles")
    script = os.path.join(dotfiles, "bin", "geoview")
    if not os.path.isfile(script):
        sys.exit(f"geoview: {script} がない（DOTFILES でリポジトリの場所を指定する）")
    sys.argv[0] = script
    runpy.run_path(script, run_name="__main__")


if __name__ == "__main__":
    main()
