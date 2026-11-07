#!/bin/sh
# install.sh の Codex の config.toml の生成の受け入れ検査（DOTFILES_CODEX_CONFIG_ONLY=1 で生成だけを走らせる。HOME は空白を含む一時ディレクトリ）:
# 無ければテンプレートの値で作り、退避もリンクも作らない。既存のうちテンプレートに無いキーと表（Codex の CLI・デスクトップが書くもの）は値と型ごと残し、
# テンプレートのキーはテンプレートの値にする（表の配列の見出し・コメント・書式・表の並びは保つ）。意味が同じなら（並び・書式が違っても）書き換えない。
# 書き換えるときは既存を 1 つ退避し（同じ秒の退避は消さない）、600 で書く。command 方式の [mcp_servers.linear]・壊れた TOML・意味の変わる書き出しは、書かずに止まる。
# PATH の python3 が 3.9（tomllib が無い）でも、呼んだ場所や dotfiles の上の場所の uv の設定が壊れていても動く。uv が無ければ失敗する（飛ばさない）
#   sh tests/acceptance/codex-config.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/codex-config.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
# 安全装置: 生成だけで止まる早期終了が無いと、一時 HOME に対してフルの install が走る（mac では defaults write も）
grep -qF 'DOTFILES_CODEX_CONFIG_ONLY' "$ROOT/install.sh" || { echo "FAIL install.sh に DOTFILES_CODEX_CONFIG_ONLY の早期終了が無い"; exit 1; }
# uv の実体のパス。mise の shim は HOME を替えると起動できない（mise の設定を HOME の下から読む）ので、HOME を替える前に決め、下で一時の bin から使う。
# mise が無い・mise の道具でない（CI の pipx の uv など）ときは PATH の uv
uvbin="$(mise which uv 2>/dev/null || command -v uv)" && [ -x "$uvbin" ] || { echo "FAIL uv が無い（mise が入れる。CI はワークフローで入れる）"; exit 1; }
# uv が取得する Python と tomlkit は、一時 HOME でなくいつもの場所に置く（実行のたびに取得しない）
UV_CACHE_DIR="$("$uvbin" cache dir)" && UV_PYTHON_INSTALL_DIR="$("$uvbin" python dir)" || { echo "FAIL uv の置き場所を得られない"; exit 1; }
export UV_CACHE_DIR UV_PYTHON_INSTALL_DIR

T=""; trap 'trap "" HUP INT TERM; rm -rf ${T:+"$T"}' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
export TMPDIR="$T" # uv run --script は TMPDIR にロックのファイルを残す。scripts/check の残りに数えられないよう、消える場所に置く
umask 022 # 素朴に作れば 644 になる umask で、600 で書くことを見る
# PATH の python3 は 3.9 の偽物（mac の標準と同じく tomllib が無い）。--version 以外で呼ばれたら印を残して失敗する
mkdir "$T/bin" "$T/py39" && ln -s "$uvbin" "$T/bin/uv" || exit 1
for p in python3 python python3.9; do
  cat > "$T/py39/$p" <<SH
#!/bin/sh
[ "\${1:-}" = --version ] && { echo "Python 3.9.6"; exit 0; }
echo used >> "$T/py39-used"
echo "ModuleNotFoundError: No module named 'tomllib'" >&2
exit 1
SH
  chmod 755 "$T/py39/$p"
done
export PATH="$T/bin:$T/py39:$PATH"
# uv の設定（uv.toml・pyproject.toml・.python-version）が壊れていても左右されない: uv はスクリプトの上の場所の uv.toml を読むので、
# 壊れた設定を置いた場所の下に、生成に使うファイルだけを写した dotfiles を置いて走らせる。呼ぶ場所も壊れた設定のある所にする
D="$T/up/dotfiles"
mkdir -p "$D/config/codex" && cp "$ROOT/install.sh" "$D/" && cp "$ROOT/config/codex/config.toml.tmpl" "$ROOT/config/codex/merge-config.py" "$D/config/codex/" || exit 1
for d in "$T/up" "$T/up/cwd"; do
  mkdir -p "$d"; echo 'not [ toml' > "$d/uv.toml"; echo 'not [ toml' > "$d/pyproject.toml"; echo 3.9 > "$d/.python-version"
done
cd "$T/up/cwd" || exit 1

# tj <ファイル>: TOML を tomllib で読み、値を型付きで（1・1.0・true を区別して）JSON にする
TJ='import json, sys, tomllib
def tag(v):
    if isinstance(v, dict): return {k: tag(x) for k, x in v.items()}
    if isinstance(v, list): return [tag(x) for x in v]
    return [type(v).__name__, repr(v)]
print(json.dumps(tag(tomllib.load(open(sys.argv[1], "rb"))), sort_keys=True))'
tj() { uv run --no-config --no-project --managed-python --python '>=3.11' --quiet python -I -c "$TJ" "$1"; }
n=0
# fresh: 新しい HOME（空白を含む）。put <ファイル>: それを既存の config.toml として置く
fresh() { n=$((n + 1)); H="$T/home $n"; CT="$H/.codex/config.toml"; mkdir "$H"; }
put() { mkdir -p "$H/.codex" && cp "$1" "$CT"; }
# inst: 写した dotfiles の、生成だけの install.sh（出力は $T/out。写しは worktree でない）。終了コードを返す
inst() { env HOME="$H" DOTFILES_CODEX_CONFIG_ONLY=1 sh "$D/install.sh" > "$T/out" 2>&1; }
tmpl() { sed "s|@HOME@|$H|g" "$ROOT/config/codex/config.toml.tmpl"; }
baks() { ls "$CT".bak.* 2>/dev/null | wc -l | tr -d ' '; }
mode() { ls -l "$1" | cut -c1-10; }
# hold: 今の config.toml を写し、mtime を 2000 年に戻す。unchanged: その後にバイトも mtime も変わっていない
hold() { cp "$CT" "$T/keep"; touch -t 200001010000 "$CT"; touch -t 200001010001 "$T/ref"; }
unchanged() { cmp -s "$CT" "$T/keep" && [ -z "$(find "$CT" -newer "$T/ref")" ]; }
only_conf() { [ "$(ls -A "$H/.codex")" = config.toml ]; }

# 1. config.toml が無い → テンプレートの値で作り、HOME には .codex/config.toml だけ（退避もリンクも無い）。600。2 回目は書き換えない
fresh; inst; rc=$?; tmpl > "$T/want"
[ "$rc" = 0 ] && [ "$(tj "$CT")" = "$(tj "$T/want")" ] && ok "無ければテンプレートの値で作る" || ng "無いとき: rc=$rc $(cat "$T/out")"
[ "$(cd "$H" && find . | sort)" = "$(printf '.\n./.codex\n./.codex/config.toml')" ] && ok "退避もリンクも作らない" || ng "HOME に置いたもの: $(cd "$H" && find . | sort)"
[ "$(mode "$CT")" = "-rw-------" ] && ok "600 で書く" || ng "権限: $(mode "$CT")"
hold; inst; rc=$?
[ "$rc" = 0 ] && unchanged && [ "$(baks)" = 0 ] && ok "2 回目はバイトも mtime も変えず、退避しない" || ng "2 回目: rc=$rc $(cat "$T/out")"

# 2. Codex が書く形 → テンプレートに無いキーと表は値と型ごと残り、テンプレートのキーはテンプレートの値。見出し・コメント・書式・並びを保つ。退避は 1 つで元のまま
fresh
cat > "$T/codex.toml" <<'EOF'
model = "old"
notify = ["/Applications/Codex.app/Contents/Resources/notify", "--from-desktop"]

# 手で足したメモ
[desktop]
open_count = 3
zoom = 1.5
show_tips = false
last_opened = 2026-11-01T09:30:00Z

[plugins."github@openai-bundled"]
enabled = true

[marketplaces.openai-bundled]
source_type = "local"
source = '/Applications/Codex.app/Contents/Resources/plugins'

[sandbox_workspace_write]
writable_roots = ["/old"]
network_access = true

[mcp_servers.node_repl]
command = "/Applications/Codex.app/Contents/Resources/node_repl"
args = ["--stdio"]

[mcp_servers.node_repl.env]
NODE_REPL_TOKEN = "s3cret"

[[skills.config]]
path = "/Users/u/.codex/skills/a/SKILL.md"
enabled = false

[[skills.config]]
path = "/Users/u/.codex/skills/b/SKILL.md"
enabled = true

[hooks.state."a:session_start:0:0"]
trusted_hash = "sha256:aa"

[projects."/x"]
trust_level = "trusted"

[tui]
screen_reader_detection_done = true
EOF
cat > "$T/want" <<EOF
model = "gpt-6.1-sol"
model_reasoning_effort = "xhigh"
notify = ["/Applications/Codex.app/Contents/Resources/notify", "--from-desktop"]

[desktop]
open_count = 3
zoom = 1.5
show_tips = false
last_opened = 2026-11-01T09:30:00Z

[plugins."github@openai-bundled"]
enabled = true

[plugins."ponytail@ponytail"]
enabled = true

[marketplaces.openai-bundled]
source_type = "local"
source = "/Applications/Codex.app/Contents/Resources/plugins"

[marketplaces.ponytail]
source_type = "git"
source = "https://github.com/DietrichGebert/ponytail.git"

[sandbox_workspace_write]
writable_roots = ["$H/.tinymemory"]
network_access = true

[mcp_servers.linear]
url = "https://mcp.linear.app/mcp"

[mcp_servers.node_repl]
command = "/Applications/Codex.app/Contents/Resources/node_repl"
args = ["--stdio"]

[mcp_servers.node_repl.env]
NODE_REPL_TOKEN = "s3cret"

[[skills.config]]
path = "/Users/u/.codex/skills/a/SKILL.md"
enabled = false

[[skills.config]]
path = "/Users/u/.codex/skills/b/SKILL.md"
enabled = true

[hooks.state."a:session_start:0:0"]
trusted_hash = "sha256:aa"

[projects."/x"]
trust_level = "trusted"

[tui]
screen_reader_detection_done = true
EOF
put "$T/codex.toml"; inst; rc=$?
[ "$rc" = 0 ] && [ "$(tj "$CT")" = "$(tj "$T/want")" ] && ok "テンプレートに無いキーと表は値と型ごと残り、テンプレートのキーはテンプレートの値" || ng "Codex が書く形: rc=$rc $(cat "$T/out") $(cat "$CT")"
[ "$(grep -c '^\[\[skills\.config\]\]$' "$CT")" = 2 ] && ok "[[skills.config]] は表の配列の見出しのまま" || ng "[[skills.config]]: $(cat "$CT")"
grep '^\[' "$T/codex.toml" > "$T/heads"
grep -qxF '# 手で足したメモ' "$CT" && grep -qxF "source = '/Applications/Codex.app/Contents/Resources/plugins'" "$CT" \
  && [ "$(grep -xF -f "$T/heads" "$CT")" = "$(cat "$T/heads")" ] && ok "既存のコメント・書式・表の並びを保つ" || ng "コメント・書式・並び: $(cat "$CT")"
[ "$(baks)" = 1 ] && cmp -s "$CT".bak.* "$T/codex.toml" && [ "$(ls -A "$H/.codex" | wc -l | tr -d ' ')" = 2 ] \
  && ok "退避は 1 つで中身は元のまま、一時ファイルを残さない" || ng "退避: $(ls -A "$H/.codex")"
[ "$(mode "$CT")" = "-rw-------" ] && ok "書き換えても 600" || ng "書き換えの権限: $(mode "$CT")"
hold; inst; rc=$?
[ "$rc" = 0 ] && unchanged && [ "$(baks)" = 1 ] && ok "結合した後の 2 回目は書き換えない" || ng "結合の後の 2 回目: rc=$rc $(cat "$T/out")"

# 3. 意味がテンプレートと同じで、表の並び・書式（リテラル文字列・インラインの表・ドット付きキー・複数行の配列）だけ違う → 書き換えない
same_toml() { cat <<EOF
model_reasoning_effort = "xhigh"
model = 'gpt-6.1-sol'

[mcp_servers]
linear = { url = "https://mcp.linear.app/mcp" }

[sandbox_workspace_write]
writable_roots = [
  "$H/.tinymemory",
]

[marketplaces.ponytail]
source = 'https://github.com/DietrichGebert/ponytail.git'
source_type = "git"

[plugins]
"ponytail@ponytail".enabled = true
EOF
}
fresh; same_toml > "$T/x"; put "$T/x"; hold; inst; rc=$?
[ "$rc" = 0 ] && unchanged && [ "$(baks)" = 0 ] && ok "意味が同じなら並び・書式が違っても書き換えない" || ng "並び・書式だけ違う: rc=$rc $(cat "$T/out")"

# 4. 型は区別する: enabled = 1 は true と同じでない → 書き直してテンプレートの値（true）にする
fresh; same_toml | sed 's/^"ponytail@ponytail".enabled = true$/"ponytail@ponytail".enabled = 1/' > "$T/x"; put "$T/x"; inst; rc=$?; tmpl > "$T/want"
[ "$rc" = 0 ] && [ "$(baks)" = 1 ] && [ "$(tj "$CT")" = "$(tj "$T/want")" ] && ok "型だけ違う値（1 と true）も書き直す" || ng "型の違い: rc=$rc $(cat "$T/out") $(cat "$CT")"

# 5. command 方式の [mcp_servers.linear]（テンプレートの url と混ぜると Codex が起動しない）→ 表の名前を出して止まり、元のまま・退避なし
fresh; printf '[mcp_servers.linear]\ncommand = "npx"\nargs = ["-y", "mcp-remote", "https://mcp.linear.app/mcp"]\n' > "$T/x"; put "$T/x"; hold; inst; rc=$?
[ "$rc" != 0 ] && grep -qF 'mcp_servers.linear' "$T/out" && unchanged && only_conf \
  && ok "command 方式の [mcp_servers.linear] は表の名前を出して止まり、元のまま" || ng "command 方式の linear: rc=$rc $(cat "$T/out") $(ls -A "$H/.codex")"

# 6. 壊れた TOML → 止まり、元のまま・退避なし
fresh; printf 'model = "old"\n[tui\n' > "$T/x"; put "$T/x"; hold; inst; rc=$?
[ "$rc" != 0 ] && grep -qF 'config.toml' "$T/out" && unchanged && only_conf && ok "壊れた TOML は止まり、元のまま" || ng "壊れた TOML: rc=$rc $(cat "$T/out") $(ls -A "$H/.codex")"

# 7. 書き出しの意味が結合と違えば書かない: トップレベルのドット付きキーで親の表を書き、そこへテンプレートの子の表を足す形。
#    結合どおりに書くか、止まって元のままか（tomlkit 0.15.2 は見出しを途中に入れて意味を変えるので、今は止まる）
fresh; printf 'plugins.other.enabled = true\nmcp_servers.node_repl.command = "n"\n\n[tui]\nx = 1\n' > "$T/x"; put "$T/x"
cat > "$T/want" <<EOF
model = "gpt-6.1-sol"
model_reasoning_effort = "xhigh"
plugins.other.enabled = true
plugins."ponytail@ponytail".enabled = true
mcp_servers.node_repl.command = "n"
mcp_servers.linear.url = "https://mcp.linear.app/mcp"

[tui]
x = 1

[marketplaces.ponytail]
source_type = "git"
source = "https://github.com/DietrichGebert/ponytail.git"

[sandbox_workspace_write]
writable_roots = ["$H/.tinymemory"]
EOF
hold; inst; rc=$?
if [ "$rc" = 0 ]; then [ "$(tj "$CT")" = "$(tj "$T/want")" ] && ok "ドット付きキーの親に表を足す形も結合どおり" || ng "意味の違う config.toml を書いた: $(cat "$CT")"
else unchanged && only_conf && ok "書き出しの意味が結合と違えば、書かずに止まる" || ng "読み直しの不一致で元のままでない: $(cat "$T/out") $(ls -A "$H/.codex")"; fi

# 8. 退避の名前は秒単位: これから 10 秒ぶんの名前の退避を先に置く（同じ秒の前の退避の代わり）→ どれも消さず、別の名前で 1 つ退避する
fresh; printf 'model = "old"\n' > "$T/x"; put "$T/x"
for s in $(uv run --no-config --no-project --managed-python --python '>=3.11' --quiet python -I -c 'import time; t = time.time(); print(*(time.strftime("%Y%m%d%H%M%S", time.localtime(t + i)) for i in range(10)))'); do
  echo keep > "$CT.bak.$s"
done
inst; rc=$?
[ "$rc" = 0 ] && [ "$(grep -lx keep "$CT".bak.* | wc -l | tr -d ' ')" = 10 ] && [ "$(grep -lx 'model = "old"' "$CT".bak.* | wc -l | tr -d ' ')" = 1 ] \
  && ls "$CT".bak.*.* >/dev/null 2>&1 && ok "同じ秒の前の退避を消さず、別の名前で退避する" || ng "同じ秒の退避: rc=$rc $(cat "$T/out") $(ls -A "$H/.codex")"

# 9. 一時ファイルを作った後の失敗: config.toml が別のファイルシステム（/dev）のファイルへのシンボリックリンクだと、退避のハードリンクが
#    EXDEV で失敗する → 0 以外で止まり、config.toml（リンクとリンク先）を変えず、一時ファイルを残さない
fresh; mkdir -p "$H/.codex"; ln -s /dev/null "$CT"; inst; rc=$?
[ "$rc" != 0 ] && [ -L "$CT" ] && [ "$(readlink "$CT")" = /dev/null ] && only_conf \
  && ok "一時ファイルを作った後に失敗したら、元のままで一時ファイルを残さない" || ng "一時ファイルの後の失敗: rc=$rc $(cat "$T/out") $(ls -A "$H/.codex")"

[ ! -e "$T/py39-used" ] && ok "PATH の python3（3.9）を使わない" || ng "PATH の python3（3.9）が使われた"

[ "$fail" = 0 ] && echo "acceptance codex-config: ok"
[ "$fail" = 0 ]
