#!/bin/sh
# 受け入れ検査（ARK-48）: 受け入れ検証の段階（acceptor・/accept・hook の関門・文書）が要件どおりか。
# hook は隔離した HOME・XDG_STATE_HOME と一時リポジトリで、実物と同じ形の hook 入力を渡して観測する
# （この repo の作業ツリーと ~/.local/state は触らない）。失敗が 1 つでもあれば exit 1
#   sh tests/acceptance/harness-accept.sh
set -eu
D="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$D/bin/harness-hook"
UV="$HOME/.local/libexec/uv"; [ -x "$UV" ] || UV="$(mise which uv 2>/dev/null || true)"
[ -x "$UV" ] || { echo "FAIL uv の実体が見つからない"; exit 1; }
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" CLAUDECODE=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM 2>/dev/null || true
mkdir -p "$HOME/.local/libexec" "$HOME/.local/bin"
ln -s "$UV" "$HOME/.local/libexec/uv"; ln -s "$HOOK" "$HOME/.local/bin/harness-hook"

fail=0
ng() { echo "FAIL $1"; fail=1; }
has() { grep -Eq -- "$2" "$D/$1" || ng "$1 に「$2」が無い"; }   # has <file> <grep の拡張正規表現>
all() { f="$1"; shift  # all <file> <語>...: すべての語を含む行がある
  awk -v ws="$*" 'BEGIN { n = split(ws, w, " ") } { ok = 1; for (i = 1; i <= n; i++) if (!index($0, w[i])) ok = 0; if (ok) { hit = 1; exit } } END { exit !hit }' "$D/$f" \
    || ng "$f に「$*」をすべて含む行が無い"; }

# ---------- AC1 / AC2 / AC3 / AC6 / AC7 / AC8 / AC11: 文書 ----------
# 文書は言い回しの変更で壊れないよう、文をまるごと一致させず要となる語で確かめる。
# 見出し・判定行・frontmatter・ファイル名など、hook や Claude Code が読む書式だけは字句どおりに確かめる
C=config/claude
# AC1: 受け入れ条件は成果物の種類ごとの確かめられる性質 + 本物の入力かサンプル
for f in $C/CLAUDE.md $C/skills/issue/SKILL.md; do
  for w in 件数 一意性 参照の整合 再現性 境界 CLI API 画面 本物の入力 サンプル; do has "$f" "$w"; done
done
has $C/skills/issue/SKILL.md '確かめられない'
# AC2: acceptor の規則と出力形式
A=$C/agents/acceptor.md
all $A 実装 先に 読まない
all $A 不合格 直さない
all $A 変えてよい tests/
all $A 検査スクリプト 実際に実行
for w in '^受け入れ: <判定>$' '^- \[AC1\] 合格 — ' '^## 条件ごとの結果' '^## 成果物のサンプル' '^## 検査スクリプト'; do has $A "$w"; done
# AC3: /accept は fork で acceptor
has $C/skills/accept/SKILL.md '^context: fork$'
has $C/skills/accept/SKILL.md '^agent: acceptor$'
# AC6: 流れ 実装 → /accept → /verify → /review（この順に並ぶ行がある）
has $C/CLAUDE.md '/accept.*/verify.*/review.*コミット'
all $C/skills/verify/SKILL.md /accept 合格
has $C/skills/implement/SKILL.md '/accept.*/verify.*/review'
has $C/skills/diagnose/SKILL.md '/accept.*/verify'
has README.md '/accept.*/verify.*/review'
# 関門の証拠を述べる行（証拠・レビュー・コミット）には受け入れも入っている（受け入れを落とした説明が残っていない）
for f in README.md CLAUDE.md; do
  bad="$(awk '/証拠/ && /(reviewer|レビュー)/ && /(コミット|pre-commit)/ && !/受け入れ/ {print FILENAME ":" FNR}' "$D/$f")"
  [ -z "$bad" ] || ng "$bad の関門の説明に受け入れ検証が無い"
done
# AC7: reviewer は受け入れの報告と検査スクリプトを見る
all $C/agents/reviewer.md 受け入れ 報告
all $C/agents/reviewer.md 検査スクリプト 条件 確かめ
has $C/skills/review/SKILL.md 'harness-last-accept'
# AC8: 完了報告で観測値とサンプル
all $C/CLAUDE.md 完了報告 観測値 サンプル
# AC11: バックグラウンドのサブエージェントを待つなら、その旨を書いて終えてよい
all $C/CLAUDE.md バックグラウンド サブエージェント 待つ 終え

# ---------- AC10: install.sh の LINKS と実際のリンク ----------
DOTFILES_LINKS_ONLY=1 sh "$D/install.sh" >/dev/null
for p in .claude/agents/acceptor.md .claude/skills/accept; do
  [ -L "$HOME/$p" ] && [ -e "$HOME/$p" ] || ng "install.sh 後に $p がリンクされていない"
done
[ -f "$HOME/.claude/skills/accept/SKILL.md" ] || ng "~/.claude/skills/accept/SKILL.md が読めない"

# ---------- AC4 / AC5: hook ----------
R="$TMP/repo"; G="git -C $R -c user.name=t -c user.email=t@t"
mkdir -p "$R/tests"; $G init -q -b main; echo base > "$R/tests/test_a.py"; echo 'uv run pytest -q' > "$R/.harness-verify"   # 検証コマンドの宣言
$G add -A; $G commit -q -m init; $G switch -q -c feat/x
# 写しを保存する（保存した時の HEAD も記録される）。条件を減らす版は承認を求められる（ARK-51 AC26）ので、準備として前の版は消す
req() { _p=$(cd "$R" && "$HOOK" requirements-path); rm -rf "$_p" "$_p.history"; printf "$1" | (cd "$R" && "$HOOK" requirements-save) >/dev/null; }
req 'AC1: 要件と受け入れ条件\n'   # 承認済みの要件の写し（関門が求める。受け入れは写しの AC 番号と突き合わせる）
SID="acc-$$"
common() { printf '"session_id":"%s","cwd":"%s","transcript_path":"/dev/null"' "$SID" "$R"; }
turn() { printf '{%s,"hook_event_name":"UserPromptSubmit","prompt":"x"}' "$(common)" | "$HOOK" turn; }
verify() { printf '{%s,"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"uv run pytest -q"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}' "$(common)" | "$HOOK" bash; }
ver() { (cd "$R" && sh "$D/config/claude/skills/review/snapshot.sh" 2>/dev/null) || true; }   # 今の作業ツリー全体の版
withver() { # withver <報告>: 版の行（した版: …）を今の版にする。無ければ先頭に足す（hook は報告の版が今の版のときだけ記録する。ARK-51）
  case "$1" in *した版:*) printf '%s' "$1" | sed "s/した版: [0-9a-z]*/した版: $(ver)/" ;; *) printf 'レビューした版: %s\\n%s' "$(ver)" "$1" ;; esac; }
sub() { printf '{%s,"hook_event_name":"SubagentStop","agent_type":"%s","last_assistant_message":"%s"}' "$(common)" "$1" "$(withver "$2")" | "$HOOK" review-done; }
REV='## 判定\n仕様適合: 承認\nテスト: 承認\n品質・保守性: 承認'
PASS='受け入れ検証した版: abc\n入力: サンプル\n## 条件ごとの結果\n- [AC1] 合格 — cmd → 500 行\n- [AC2] 合格 — cmd → 重複 0\n## 成果物のサンプル\n| id,name\n## 判定\n受け入れ: 合格'
stop() { printf '{%s,"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"done"}' "$(common)" | "$HOOK" stop; }
blocked() { case "$(stop)" in *'"decision": "block"'*) return 0 ;; *) return 1 ;; esac; }
commit_ok() { (cd "$R" && "$HOOK" pre-commit) >/dev/null 2>&1; }
change() { turn; echo "$1" > "$R/app.py"; echo "$1" > "$R/tests/test_app.py"; }
LAST="$R/.git/harness-last-accept"

# 検証・受け入れ・レビューがそろえば、Stop は通し、pre-commit もコミットを許す
change v1; verify; sub acceptor "$PASS"; sub reviewer "$REV"
blocked && ng "AC5: 3 つそろっているのに Stop が差し戻した"
$G add -A; commit_ok || ng "AC5: 3 つそろっているのに pre-commit が拒否した"
[ "$(cat "$LAST" 2>/dev/null)" = "$(printf '%b' "$(withver "$PASS")")" ] || ng "AC4: harness-last-accept に報告がそのまま保存されていない"

# 受け入れだけが無い → Stop は /accept を理由に差し戻し、pre-commit も /accept を理由に拒否
change v2; verify; sub reviewer "$REV"
out="$(stop)"; case "$out" in *'"decision": "block"'*/accept*) ;; *) ng "AC5: 受け入れ無しで Stop が /accept を理由に差し戻さない: $out" ;; esac
$G add -A; msg="$(cd "$R" && "$HOOK" pre-commit 2>&1 || true)"
commit_ok && ng "AC5: 受け入れ無しで pre-commit が通した"
case "$msg" in */accept*) ;; *) ng "AC5: pre-commit の拒否理由に /accept が無い: $msg" ;; esac
# 受け入れを足せば通る
sub acceptor "$PASS"; blocked && ng "AC5: 受け入れを足しても Stop が差し戻す"; commit_ok || ng "AC5: 受け入れを足しても pre-commit が拒否"

# 検証だけ・レビューだけが無い場合も止める
change v3; sub acceptor "$PASS"; sub reviewer "$REV"; $G add -A
blocked || ng "AC5: 検証なしで Stop が通した"; commit_ok && ng "AC5: 検証なしで pre-commit が通した"
change v4; verify; sub acceptor "$PASS"; $G add -A
blocked || ng "AC5: レビューなしで Stop が通した"; commit_ok && ng "AC5: レビューなしで pre-commit が通した"

# 受け入れ済みにしない報告（検証とレビューはそろえた状態で、受け入れだけを差し替える）
rejects() { # rejects <説明> <acceptor の報告>
  n=$((n + 1)); change "r$n"; verify; sub reviewer "$REV"; sub acceptor "$2"; $G add -A
  blocked || ng "$1 なのに受け入れ済みになった（Stop が通した）"
  commit_ok && ng "$1 なのに受け入れ済みになった（pre-commit が通した）"
  [ "$(cat "$LAST" 2>/dev/null)" = "$(printf '%b' "$(withver "$2")")" ] || ng "$1 の報告が harness-last-accept に保存されていない"
}
# 受け入れ済みにする報告（同じく、受け入れだけを差し替える）
accepts() { # accepts <説明> <acceptor の報告>
  n=$((n + 1)); change "a$n"; verify; sub reviewer "$REV"; sub acceptor "$2"; $G add -A
  blocked && ng "$1 なのに受け入れ済みにならない（Stop が差し戻した）"
  commit_ok || ng "$1 なのに受け入れ済みにならない（pre-commit が拒否した）"
}
n=0
S='## 条件ごとの結果\n'   # 条件の行を置く節
V='\n## 判定\n受け入れ: 合格'
accepts '（前提）節の中の条件がすべて合格で判定も合格' "$S- [AC1] 合格 — a → b\n- [AC2] 合格 — a → b$V"
rejects 'AC4: 判定が不合格' "$S- [AC1] 合格 — a → b\n- [AC2] 不合格 — 期待 / 実際\n## 判定\n受け入れ: 不合格"
rejects 'AC4: 判定行なし' "$S- [AC1] 合格 — a → b\n- [AC2] 合格 — a → b"
rejects 'AC4: 条件の行に不合格（判定は合格）' "$S- [AC1] 合格 — a → b\n- [AC2] 不合格 — 期待 / 実際$V"
rejects 'AC4: 条件の行に未確認（判定は合格）' "$S- [AC1] 合格 — a → b\n- [AC2] 未確認 — 理由$V"
rejects 'AC4: 節はあるが条件の行なし' "$S$V"
rejects 'AC4: reviewer の形の報告' "$REV"

# ---------- AC12: 条件の行は「条件ごとの結果」の節の中だけ、状態はダッシュに依らず最初の語で読む ----------
# 節の外の [AC 行は数えない（外に不合格・未確認があっても、節の中がすべて合格なら受け入れ済み）
accepts 'AC12: 節の外（検査スクリプト・サンプル）にだけ不合格・未確認の [AC 行がある' \
  "$S- [AC1] 合格 — a → b\n- [AC2] 合格 — a → b\n## 検査スクリプト\n- [AC2] 不合格 — の場合の検査は x.sh\n[AC3] 未確認 — 例\n## 成果物のサンプル\n| - [AC9] 不合格 — x$V"
# 節の外にしか条件の行が無い / 節が無い → 受け入れ済みにしない（fail-closed）
rejects 'AC12: 条件の行が節の外にしか無い' "## 検査スクリプト\n- [AC1] 合格 — a → b\n- [AC2] 合格 — a → b$V"
rejects 'AC12: 節の見出しが無い（前回の形の報告）' "- [AC1] 合格 — a → b\n- [AC2] 合格 — a → b$V"
# ダッシュの種類に依らず、最初の語で合格を読む
accepts 'AC12: 半角ハイフン' "$S- [AC1] 合格 - a → b\n- [AC2] 合格 - a → b$V"
accepts 'AC12: エンダッシュ・水平線・空白なしのダッシュ' "$S- [AC1] 合格 – a\n- [AC2] 合格 ― b\n- [AC3] 合格—c\n- [AC4] 合格 −$V"
accepts 'AC12: 空白なしの水平線（U+2015）・マイナス（U+2212）・ハイフン（U+2010）' "$S- [AC1] 合格―a\n- [AC2] 合格−b\n- [AC3] 合格‐c$V"
# 最初の語が合格でなければ、ダッシュが何でも受け入れ済みにしない
rejects 'AC12: 半角ハイフンの不合格' "$S- [AC1] 合格 - a\n- [AC2] 不合格 - 期待 / 実際$V"
rejects 'AC12: エンダッシュの未確認' "$S- [AC1] 合格 – a\n- [AC2] 未確認 – 理由$V"
rejects 'AC12: 最初の語が知らない状態（保留）' "$S- [AC1] 合格 — a\n- [AC2] 保留 — 理由$V"
rejects 'AC12: 最初の語が合格で始まる別の語（合格見込み）' "$S- [AC1] 合格 — a\n- [AC2] 合格見込み — 理由$V"
rejects 'AC12: 節の中に不合格、節の外に合格' "$S- [AC1] 不合格 - a\n## 検査スクリプト\n- [AC1] 合格 — a$V"
# 節の中は小見出し（### …）の下も含む。「条件ごとの結果」の節が 2 つあれば両方を読む（fail-closed）
rejects 'AC12: 節の小見出しの下に不合格' "$S- [AC1] 合格 — a\n### 補足\n- [AC2] 不合格 — a$V"
rejects 'AC12: 条件ごとの結果の節が 2 つあり、2 つ目に不合格' "$S- [AC1] 合格 — a\n## 検査スクリプト\nx\n$S- [AC2] 不合格 — a$V"
# 再検証で足した境界: 深い小見出しの下、上位の見出しで節が終わること、残りのダッシュ（U+2011〜U+2014）
rejects 'AC12: 節の 2 段下の小見出し（####）の下に不合格' "$S- [AC1] 合格 — a\n### 補足\n#### 詳細\n- [AC2] 不合格 — a$V"
rejects 'AC12: # の節の下の ## 小見出しに不合格' "# 条件ごとの結果\n- [AC1] 合格 — a\n## 補足\n- [AC2] 未確認 — a$V"
accepts 'AC12: 節は上位の見出し（#）で終わり、その後の不合格は数えない' "$S- [AC1] 合格 — a\n# 付録\n- [AC2] 不合格 — 例$V"
accepts 'AC12: 空白なしの U+2011・U+2012・U+2013・U+2014' "$S- [AC1] 合格‑a\n- [AC2] 合格‒b\n- [AC3] 合格–c\n- [AC4] 合格—d$V"
rejects 'AC12: 空白なしのダッシュの不合格・未確認' "$S- [AC1] 合格—a\n- [AC2] 不合格―b\n- [AC3] 未確認−c$V"

# ---------- AC11: バックグラウンドのサブエージェントを待つなら書いて終えてよい。コミットの関門は弱めない ----------
change y1; verify; $G add -A
out="$(stop)"
case "$out" in *'"decision": "block"'*バックグラウンドのサブエージェント*終えてよい*) ;; *) ng "AC11: Stop の差し戻し文に、バックグラウンドのサブエージェントを待つなら終えてよいことが無い: $out" ;; esac
# 待つ旨を書いて終える（2 回目の Stop は stop_hook_active）→ 止めない
out="$(printf '{%s,"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"バックグラウンドのサブエージェントの完了を待つ"}' "$(common)" | "$HOOK" stop)"
case "$out" in *'"decision": "block"'*) ng "AC11: 待つ旨を書いた 2 回目の Stop も差し戻した: $out" ;; esac
# その後もコミットは止める。拒否文には「待つなら終えてよい」を入れない
msg="$(cd "$R" && "$HOOK" pre-commit 2>&1 || true)"
commit_ok && ng "AC11: 待つ旨を書いて終えた後、証拠なしで pre-commit が通した"
case "$msg" in *バックグラウンド*|*終えてよい*) ng "AC11: pre-commit の拒否文に終えてよい旨がある: $msg" ;; esac
case "$msg" in *コミットできない*) ;; *) ng "AC11: pre-commit の拒否文が想定外: $msg" ;; esac

# ---------- ARK-50 AC1: 写しの AC 番号がすべて報告に「合格」で出ていないと受け入れ済みにしない ----------
req 'AC1: a\nAC2: b\nAC10: c\n'
accepts 'ARK-50 AC1: 写しの AC1・AC2・AC10 がすべて合格（写しに無い AC3 も報告にある）' "$S- [AC1] 合格 — a\n- [AC2] 合格 — a\n- [AC3] 合格 — a\n- [AC10] 合格 — a$V"
rejects 'ARK-50 AC1: 写しの AC10 が報告に無い（AC1 はある）' "$S- [AC1] 合格 — a\n- [AC2] 合格 — a$V"
rejects 'ARK-50 AC1: 写しの AC10 の代わりに AC11 がある' "$S- [AC1] 合格 — a\n- [AC2] 合格 — a\n- [AC11] 合格 — a$V"
rejects 'ARK-50 AC1: 写しの AC2 が節の外にだけある' "$S- [AC1] 合格 — a\n- [AC10] 合格 — a\n## 検査スクリプト\n- [AC2] 合格 — a$V"
# 写しに AC 番号が 1 つも無い → 受け入れ済みにせず、理由に番号の付け方
req '要件\n- 受け入れ条件（番号なし）\n'
rejects 'ARK-50 AC1: 写しに AC 番号が無い' "$S- [AC1] 合格 — a$V"
msg="$(cd "$R" && "$HOOK" pre-commit 2>&1 || true)"
case "$msg" in *'受け入れ条件に AC1, AC2'*'番号を付ける'*) ;; *) ng "ARK-50 AC1: 写しに AC 番号が無いときの拒否理由に番号の付け方が無い: $msg" ;; esac
case "$(stop)" in *'受け入れ条件に AC1, AC2'*'番号を付ける'*) ;; *) ng "ARK-50 AC1: 写しに AC 番号が無いときの Stop の理由に番号の付け方が無い" ;; esac
req 'AC1: 要件と受け入れ条件\n'

# reviewer が受け入れの形で終わっても受け入れ済み・レビュー済みにしない（acceptor だけが受け入れを記録する）
change w1; verify; sub reviewer "$PASS"; sub reviewer "$REV"; $G add -A
blocked || ng "AC4: reviewer の終了で受け入れ済みになった"

# 受け入れの後に内容を変えれば、受け入れは無効（内容に対して記録）
change x1; verify; sub acceptor "$PASS"; sub reviewer "$REV"
echo x2 > "$R/app.py"; verify; sub reviewer "$REV"; $G add -A
blocked || ng "AC4: 受け入れ後に内容を変えても受け入れ済みのまま"

[ "$fail" = 0 ] && echo "harness-accept: ok"
exit "$fail"
