#!/bin/sh
# 業務サーバーの署名消しの受け入れ検査: config/git/hooks-nosign/commit-msg が、AI 由来の行（メールアドレスが AI のツールの Co-Authored-By・Claude-Session:・
# Generated with Claude Code・Generated with Codex だけの行・セッションの URL だけの行）を消し、件名・本文・人の共同作者（名前に Claude を含んでも）は残すこと。AI 由来の行が無いメッセージは変えないこと。
# core.hooksPath をフックに向けた一時リポジトリの commit と merge で、メッセージが件名・本文・人の共同作者だけになり、末尾に空行が残らないこと。
# 指さないリポジトリ（私用の端末）では署名が残ること。AGENTS.md に「署名を付けない」が無く、config/git/README.md に業務サーバーの手順とフックが消す行があること
#   sh tests/acceptance/git-nosign.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/git-nosign.sh  通った項目も
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/config/git/hooks-nosign/commit-msg"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# 端末の ~/.gitconfig（業務サーバーの hooksPath など）に左右されないよう、空の設定で動かす
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# 本文の 2・3 行目は文中で Claude Code とセッションの URL に触れる普通の文、人の共同作者の 2 人目は名前に Claude を含む（どれも消さない）
MSG='fix token check

Keeps the expiry check testable.
Fixtures generated with Claude Code are checked by hand.
See https://claude.ai/code/session_0123abc for the failing run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Co-authored-by: Codex <noreply@openai.com>
Co-Authored-By: Taro <taro@example.com>
Co-Authored-By: Claude Martin <claude.martin@example.com>
Claude-Session: https://claude.ai/code/session_0123abc

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Generated with Claude Code
Generated with [Codex](https://openai.com/codex/).
Generated with Codex.

https://claude.ai/code/session_0123abc'
# AI 由来の行を消した後に残るメッセージ
WANT='fix token check

Keeps the expiry check testable.
Fixtures generated with Claude Code are checked by hand.
See https://claude.ai/code/session_0123abc for the failing run.

Co-Authored-By: Taro <taro@example.com>
Co-Authored-By: Claude Martin <claude.martin@example.com>'

# フックを直接: 消して残る空行は git の cleanup が詰めるので、git stripspace を通して比べる。絵文字の行は C ロケールでも消える
printf '%s\n' "$MSG" > "$T/msg"
LC_ALL=C sh "$HOOK" "$T/msg"
[ "$(git stripspace < "$T/msg")" = "$WANT" ] && ok "フック: 件名・本文・人の共同作者だけが残る" || ng "フック: AI 由来の行が残るか、ほかの行が消えた: $(sed -n l "$T/msg")"
printf '%s\n' "$WANT" > "$T/plain"; cp "$T/plain" "$T/plain.orig"
sh "$HOOK" "$T/plain"
cmp -s "$T/plain" "$T/plain.orig" && ok "フック: AI 由来の行が無いメッセージは変わらない" || ng "フック: AI 由来の行が無いメッセージが変わった: $(sed -n l "$T/plain")"

# UTF-8 として不正なバイト（Latin-1 の é）を含む行は、UTF-8 のロケールでも消えない（grep が binary 扱いして黙って落とさない）
printf 'fix: caf\351\n\nbody caf\351\n\nClaude-Session: https://claude.ai/code/session_0123abc\n' > "$T/latin"
printf 'fix: caf\351\n\nbody caf\351\n' > "$T/latin.want"
LC_ALL=C.UTF-8 sh "$HOOK" "$T/latin"
git stripspace < "$T/latin" | cmp -s - "$T/latin.want" && ok "フック: UTF-8 でないバイトを含む件名・本文は残り、AI の行だけ消える" || ng "フック: UTF-8 でないバイトを含む行が消えたか、AI の行が残った: $(sed -n l "$T/latin")"

# リポジトリを作り、最初のコミットを置く。$2 が空でなければ hooksPath を指す
repo() {
  git init -q -b main "$1"
  [ -z "$2" ] || git -C "$1" config core.hooksPath "$ROOT/config/git/hooks-nosign"
  git -C "$1" commit -q --allow-empty -m "$MSG"
}
# 最新のコミットのメッセージが $2 と同じか。%B は本文の後に区切りの改行を 1 つ足すので、末尾に空行が残れば改行が 3 つになって違う
same() { git -C "$1" log -1 --format=%B > "$T/got"; printf '%s\n\n' "$2" | cmp -s - "$T/got"; }

repo "$T/work" hook
same "$T/work" "$WANT" && ok "commit: 件名・本文・人の共同作者だけが残り、末尾に空行が無い" || ng "commit: メッセージが違う: $(sed -n l "$T/got")"

git -C "$T/work" switch -q -c feature/x
git -C "$T/work" commit -q --allow-empty -m 'add x'
git -C "$T/work" switch -q main
git -C "$T/work" merge -q --no-ff -m "$MSG" feature/x
[ "$(git -C "$T/work" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] && ok "merge: merge コミットができる" || ng "merge: merge コミットができていない"
same "$T/work" "$WANT" && ok "merge: 件名・本文・人の共同作者だけが残り、末尾に空行が無い" || ng "merge: メッセージが違う: $(sed -n l "$T/got")"

repo "$T/private" ""
same "$T/private" "$MSG" && ok "hooksPath なし: メッセージは変わらない（署名の行は残る）" || ng "hooksPath なし: メッセージが変わった: $(sed -n l "$T/got")"

grep -q '署名' "$ROOT/config/agents/AGENTS.md" && ng "AGENTS.md に署名の記述が残っている" || ok "AGENTS.md に「署名を付けない」が無い"
grep -q 'hooksPath = ~/.config/git/hooks-nosign' "$ROOT/config/git/README.md" && ok "config/git/README.md に業務サーバーの hooksPath の手順がある" || ng "config/git/README.md に業務サーバーの hooksPath の手順が無い"
nosign="$(grep -F '`config/git/hooks-nosign/`' "$ROOT/config/git/README.md" || true)"
for w in 'Co-Authored-By' 'noreply@anthropic.com' 'noreply@openai.com' 'Claude-Session:' 'Generated with Claude Code' 'Generated with Codex' 'https://claude.ai/code/session_'; do
  case "$nosign" in *"$w"*) ok "config/git/README.md のフックの説明に「$w」がある" ;; *) ng "config/git/README.md のフックの説明に「$w」が無い" ;; esac
done

exit $fail
