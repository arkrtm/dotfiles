#!/bin/sh
# ハーネスの流れ全体の E2E（手動で実行する。.harness-verify には入れない）。
# 一時リポジトリに S の依頼を `claude -p` で最初から最後まで流し、手順と関門がそろったかを確かめる。
# 実際のモデルとサブエージェント（acceptor・reviewer）が動くので、数分〜十数分・数十万トークンかかる。
# 入れ子の claude には、一時リポジトリの中の作業として Bash を許可する（コマンド置換を含む検査のコマンドを通すため）。
#   sh tests/e2e-flow.sh [作業ディレクトリ]   （既定は mktemp。stream.jsonl と repo/ が残る）
set -u
command -v claude >/dev/null 2>&1 || { echo "FAIL claude が無い"; exit 1; }
command -v harness-hook >/dev/null 2>&1 || { echo "FAIL harness-hook が無い（dotfiles の install.sh を実行すること）"; exit 1; }
W="${1:-$(mktemp -d)}"; R="$W/repo"
mkdir -p "$R/textstats" "$R/tests"
: > "$R/textstats/__init__.py"; : > "$R/tests/__init__.py"
printf '__pycache__/\n' > "$R/.gitignore"
printf 'python3 -m unittest discover -s tests -t . -q\n' > "$R/.harness-verify"
cat > "$R/tests/test_base.py" <<'EOF'
import unittest


class TestBase(unittest.TestCase):
    def test_package_imports(self):
        import textstats  # noqa: F401
EOF
git -C "$R" init -q -b main
git -C "$R" add -A
git -C "$R" -c user.name=e2e -c user.email=e2e@example.com commit -q -m init
BASE=$(git -C "$R" rev-parse HEAD)

PROMPT='S の依頼です。textstats/words.py に count_words(text) を追加してください。任意の空白文字で区切った語の数を返します。
受け入れ条件:
- AC1: python3 -c "from textstats.words import count_words; print(count_words(\"  a b\\n c \"))" が 3 を出力する
- AC2: count_words("") が 0 を返す
CLAUDE.md の流れどおりにコミットまで進めてください（統合はしない。質問はせずに進める。Linear の issue は作らない）。'

echo "作業ディレクトリ: $W（claude -p を実行中。数分〜十数分かかる）"
(cd "$R" && claude -p "$PROMPT" --output-format stream-json --verbose --max-turns 150 \
  --permission-mode acceptEdits --allowedTools Bash Skill Agent Read Edit Write Glob Grep \
  > "$W/stream.jsonl" 2> "$W/stderr.txt")

passed=0; fail=0
ok() { passed=$((passed + 1)); echo "ok   $1"; }
ng() { fail=$((fail + 1)); echo "FAIL $1"; }
expect() { d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi; }

GD=$(git -C "$R" rev-parse --absolute-git-dir)
BR=$(git -C "$R" symbolic-ref --short -q HEAD || echo HEAD)
expect "main は変わっていない（main 上で編集もコミットもしていない）" [ "$(git -C "$R" rev-parse main)" = "$BASE" ]
expect "作業ブランチ（main 以外）にいる" [ "$BR" != main ]
expect "作業ブランチに main より後のコミットがある" [ -n "$(git -C "$R" log --oneline main..HEAD)" ]
expect "作業ツリーはきれい（すべてコミットした）" [ -z "$(git -C "$R" status --porcelain)" ]
expect "実装がコミットされている（textstats/words.py）" git -C "$R" cat-file -e HEAD:textstats/words.py
expect "受け入れ条件を満たす（AC1: 3 を出力）" [ "$(cd "$R" && python3 -c 'from textstats.words import count_words; print(count_words("  a b\n c "))')" = 3 ]
expect "受け入れ条件を満たす（AC2: 空文字で 0）" [ "$(cd "$R" && python3 -c 'from textstats.words import count_words; print(count_words(""))')" = 0 ]
expect "要件の写しがある" [ -s "$(cd "$R" && harness-hook requirements-path)" ]
expect "受け入れ検証の報告が合格" grep -q '^受け入れ: 合格' "$GD/harness-last-accept"
expect "受け入れ検査が tests/ に残ってコミットされている" sh -c "git -C '$R' ls-tree -r --name-only HEAD tests | grep -qi accept"
expect "レビューの報告が 3 軸とも承認" sh -c "[ \$(grep -cE '^(仕様適合|テスト|品質・保守性): 承認\$' '$GD/harness-last-review') -ge 3 ]"
expect "テストが先に落ちた記録（harness-red-log）がある" [ -s "$GD/harness-red-log" ]
# 宣言した検証コマンドを、メインの会話（サブエージェントでない）が単独で実行したか（cd の前置は可）
declared_ran() {
  python3 - "$W/stream.jsonl" "$(cat "$R/.harness-verify")" <<'PY'
import json, re, sys
path, declared = sys.argv[1], sys.argv[2].strip()
for line in open(path):
    d = json.loads(line)
    if d.get("type") != "assistant" or d.get("parent_tool_use_id"):
        continue
    for b in d["message"]["content"]:
        if b.get("type") == "tool_use" and b.get("name") == "Bash":
            cmd = re.sub(r"^cd \S+ && ", "", (b.get("input") or {}).get("command", "").strip())
            if cmd == declared:
                sys.exit(0)
sys.exit(1)
PY
}
expect "宣言した検証コマンドを、メインの会話で単独で実行した" declared_ran
skills=$(grep -o '"skill":"[a-z:-]*"' "$W/stream.jsonl" | sed 's/.*:"\(.*\)"/\1/' | tr '\n' ' ')
echo "     呼ばれた skill（順）: $skills"
first_accept=$(printf '%s\n' $skills | grep -n '^accept$' | head -1 | cut -d: -f1)
last_review=$(printf '%s\n' $skills | grep -n '^review$' | tail -1 | cut -d: -f1)
order_ok() { [ -n "$first_accept" ] && [ -n "$last_review" ] && [ "$last_review" -gt "$first_accept" ]; }
expect "/accept が呼ばれ、最後の /review はその後" order_ok
echo "e2e-flow: ok $passed, FAIL $fail（記録: $W）"
[ "$fail" = 0 ]
