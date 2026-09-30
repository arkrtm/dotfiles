#!/bin/sh
# 受け入れ検査（ARK-50）: 最終の採点の指摘を直したもの。関門の対象の拡張子（AC2）と文書（AC3 の reviewer、AC6〜AC15）。
# AC1 は harness-accept.sh、AC3〜AC5・AC16（の判定）は harness-parity.sh の該当する節にある（同じ振る舞いの検査に足した）。
# 文書は言い回しの変更で壊れないよう、要となる語で確かめる。hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで動かす。
# 失敗が 1 つでもあれば exit 1
#   sh tests/acceptance/harness-final.sh
set -eu
D="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$D/bin/harness-hook"
UV="$HOME/.local/libexec/uv"; [ -x "$UV" ] || UV="$(mise which uv 2>/dev/null || true)"
[ -x "$UV" ] || { echo "FAIL uv の実体が見つからない"; exit 1; }
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" CLAUDECODE=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM 2>/dev/null || true
mkdir -p "$HOME/.local/libexec"; ln -s "$UV" "$HOME/.local/libexec/uv"

fail=0
ng() { echo "FAIL $1"; fail=1; }
has() { grep -Eq -- "$2" "$D/$1" || ng "$1 に「$2」が無い"; }   # has <file> <grep の拡張正規表現>
all() { f="$1"; shift  # all <file> <語>...: すべての語を含む行がある
  awk -v ws="$*" 'BEGIN { n = split(ws, w, " ") } { ok = 1; for (i = 1; i <= n; i++) if (!index($0, w[i])) ok = 0; if (ok) { hit = 1; exit } } END { exit !hit }' "$D/$f" \
    || ng "$f に「$*」をすべて含む行が無い"; }
C=config/claude; S=$C/skills

# ---------- AC2: 関門の対象の拡張子 ----------
# 証拠の無い変更で、コードの拡張子は pre-commit が拒否し Stop が差し戻す。文書（Markdown・画像・テキスト）は通す
R="$TMP/repo"; mkdir -p "$R"; git init -q -b main "$R"; echo 'true' > "$R/.harness-verify"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m init; git -C "$R" switch -q -c feat/x
printf 'AC1: x\n' | (cd "$R" && "$HOOK" requirements-save) >/dev/null
common() { printf '"session_id":"fin-%s","cwd":"%s","transcript_path":"/dev/null"' "$$" "$R"; }
turn() { printf '{%s,"hook_event_name":"UserPromptSubmit","prompt":"x"}' "$(common)" | "$HOOK" turn; }
blocked() { case "$(printf '{%s,"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"done"}' "$(common)" | "$HOOK" stop)" in *'"decision": "block"'*) return 0 ;; *) return 1 ;; esac; }
commit_ok() { (cd "$R" && "$HOOK" pre-commit) >/dev/null 2>&1; }
try() { # try <path>: 1 ファイルだけを足してステージし、pre-commit と Stop の結果を「gate」か「pass」で返す。その後は元に戻す
  turn; mkdir -p "$R/$(dirname "$1")"; echo "x" > "$R/$1"; git -C "$R" add -A
  if commit_ok; then c=pass; else c=gate; fi; if blocked; then b=gate; else b=pass; fi
  rm -f "$R/$1"; git -C "$R" add -A; echo "$c$b"; }
for e in xml html htm css scss sass less tf tfvars hcl r R kts gradle groovy proto graphql gql nix cmake mk ps1 bat cmd vim el clj hs ml jl pl pm zig sol; do
  [ "$(try "src/a.$e")" = gategate ] || ng "AC2: .$e の変更で、証拠が無いのに pre-commit か Stop が通した"
done
for p in docs/a.md README.md img/a.png notes.txt; do
  [ "$(try "$p")" = passpass ] || ng "AC2: 文書 $p の変更で、pre-commit か Stop が止めた"
done

# ---------- AC3（文書）: reviewer は宣言された検証コマンドが全体の検証かを見る ----------
all $C/agents/reviewer.md .harness-verify harness-verify 全体 lint

# ---------- AC6: /review interim ----------
has $S/review/SKILL.md 'interim'
all $S/review/SKILL.md interim 中間
all $S/review/SKILL.md 受け入れ 見ない
all $S/review/SKILL.md 証拠にならない /accept /verify /review
all $S/implement/SKILL.md interim 受け入れ 証拠 /accept /verify /review

# ---------- AC7: /wrap-up は作業ブランチの上で統合の前。流れ（CLAUDE.md・README の図）と wrap-up/SKILL.md が一致 ----------
all $S/wrap-up/SKILL.md 作業ブランチ 統合 前 main
has $S/wrap-up/SKILL.md '^description: .*統合.*前.*作業ブランチ'
all $C/CLAUDE.md 流れ コミット /wrap-up 統合の判断
all $C/CLAUDE.md /wrap-up 作業ブランチ main
# 流れの 1 行・README の全体図では、/wrap-up が統合（マージ）より前に出る
order() { # order <file> <前の語> <後の語> <範囲の正規表現（awk）>: 範囲の中で、前の語が後の語より先に出る
  awk -v a="$2" -v b="$3" -v r="$4" '$0 ~ r { on = 1 } on { s = s $0 "\n" } on && /^```$/ { exit } END { i = index(s, a); j = index(s, b); exit !(i && j && i < j) }' "$D/$1" \
    || ng "$1 の流れで「$2」が「$3」より前に無い"; }
awk '/^流れ/ { i = index($0, "/wrap-up"); j = index($0, "統合の判断"); exit !(i && j && i < j) }' "$D/$C/CLAUDE.md" || ng "CLAUDE.md の流れの行で /wrap-up が統合の判断より前に無い"
order README.md '/wrap-up' '統合の判断' '^依頼 → 規模の判定'

# ---------- AC8: 設定・依存の版だけの変更 ----------
all $S/tdd/SKILL.md 設定 依存 版
all $S/tdd/SKILL.md 受け入れ条件 全体の検証
all $C/agents/reviewer.md 設定・依存の版 RED

# ---------- AC9: 受け入れの検査の衛生 ----------
all $C/agents/acceptor.md 既存の検査 更新・統合
all $C/agents/acceptor.md 増やしすぎない

# ---------- AC10: 判断の集約と進捗 ----------
all $S/implement/SKILL.md '`## 判断`' 本文 裁定 完了報告 全件
all $C/CLAUDE.md 完了報告 判断
all $C/CLAUDE.md メインで直接実装 チェックリスト

# ---------- AC11: /implement の 2 回 BLOCKED と計画の見直し ----------
all $S/implement/SKILL.md 2 BLOCKED 上位のモデル implementer 見直
all $S/implement/SKILL.md 決めていない TBD 適宜

# ---------- AC12: /design の自己点検と子 issue ----------
all $S/design/SKILL.md 空欄 矛盾 曖昧さ 範囲
all $S/design/SKILL.md 独立 子 issue

# ---------- AC13: reviewer と acceptor のモデルを固定（frontmatter）----------
for a in reviewer acceptor; do
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm && /^model: opus$/ { hit = 1 } END { exit !hit }' "$D/$C/agents/$a.md" \
    || ng "AC13: agents/$a.md の frontmatter に model: opus が無い"
done
for s in accept review; do grep -q '^model:' "$D/$S/$s/SKILL.md" && ng "AC13: skills/$s の frontmatter の model が agent の固定を上書きする"; done

# ---------- AC14: 指摘の受け取り方・基点のブランチ・PR ----------
all $C/CLAUDE.md 不明な指摘 確かめてから
all $C/CLAUDE.md YAGNI grep
all $C/CLAUDE.md PR スレッド 返信
all $C/CLAUDE.md 基点のブランチ origin/HEAD
all $C/CLAUDE.md 'gh pr create'

# ---------- AC15: ハーネス自体の不具合の調べ方 ----------
all $S/diagnose/SKILL.md ハーネス 関門 止める 通す
all $S/diagnose/SKILL.md log Read
for w in harness-last-accept harness-last-review harness-red-log requirements-path; do has $S/diagnose/SKILL.md "$w"; done

[ "$fail" = 0 ] && echo "harness-final: ok"
exit "$fail"
