#!/bin/sh
# ハーネスの一貫性の検査: skill・agent の frontmatter、文中のスラッシュコマンド、install.sh の LINKS、
# settings.json の SubagentStop の matcher と bin/harness-hook の agent 名の定数、流れの段の順序（CLAUDE.md の流れの 1 行・
# 手順の番号・README の流れの図）、README に書いた e2e の場面の数（tests/e2e-flow.sh）が食い違っていないこと
#   sh tests/skills.sh [-v] [<リポジトリのトップ>]   既定はこのリポジトリ。失敗した項目と要約 1 行だけを出す（-v で通った項目も）
# 検査そのものの否定のテスト（一時ディレクトリに写して 1 か所ずつ壊し、FAIL が出ること）も毎回走る
set -eu
VERBOSE=; [ "${1:-}" != -v ] || { VERBOSE=1; shift; }
ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
# skill のほかに書いてよいスラッシュコマンド（Claude Code の同梱・プラグイン）。/名前:名前 の形は検査しない
BUILTIN="code-review security-review simplify run clear compact reload-plugins permissions hooks config remember dream recall"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passed=0; fail=0
ok() { passed=$((passed + 1)); [ -z "$VERBOSE" ] || echo "ok   $1"; }
ng() { fail=$((fail + 1)); echo "FAIL $1"; }
expect() { # expect <説明> <test の条件…>
  desc=$1; shift
  if "$@"; then ok "$desc"; else ng "$desc"; fi
}

fm() { # fm <ファイル>: frontmatter（1 行目の --- から次の --- まで）の中身。閉じた frontmatter が無ければ終了コード 1
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { closed = 1; exit } NR > 1 { print } END { exit !closed }' "$1"
}
field() { fm "$1" 2>/dev/null | sed -n "/^$2:/{s/^$2:[[:space:]]*//;s/[[:space:]]*\$//;p;}" | head -n 1; }  # field <ファイル> <キー>
has() { printf '%s\n' "$2" | grep -qxF -- "$1"; }  # has <語> <1 行 1 語の一覧>
in_order() { # in_order <文> <印…>: 印がこの順に文の中に現れる（それぞれ前の印より後に）
  rest=$1; shift
  for m in "$@"; do
    case "$rest" in *"$m"*) rest=${rest#*"$m"} ;; *) return 1 ;; esac
  done
}

checks() { # checks <リポジトリのトップ>
  c="$1/config/claude"; skills=
  for d in "$c"/skills/*/; do
    s=$(basename "$d"); f="${d}SKILL.md"; skills="$skills $s"
    if ! fm "$f" >/dev/null 2>&1; then ng "skills/$s/SKILL.md に frontmatter（1 行目の --- から --- まで）が無い"; continue; fi
    v=$(field "$f" name); expect "skills/$s: name（$v）がディレクトリ名と一致する" [ "$v" = "$s" ]
    v=$(field "$f" description); expect "skills/$s: description が空でない" [ -n "$v" ]
    a=$(field "$f" agent)
    [ -z "$a" ] || expect "skills/$s: agent の定義 agents/$a.md がある" [ -f "$c/agents/$a.md" ]
  done
  for f in "$c"/agents/*.md; do
    a=$(basename "$f" .md)
    if ! fm "$f" >/dev/null 2>&1; then ng "agents/$a.md に frontmatter（1 行目の --- から --- まで）が無い"; continue; fi
    v=$(field "$f" name); expect "agents/$a: name（$v）がファイル名と一致する" [ "$v" = "$a" ]
    v=$(field "$f" description); expect "agents/$a: description が空でない" [ -n "$v" ]
  done
  # 文中の /名前（バッククォートの内外とも）。直前が行頭・空白・記号・日本語の文字（C ロケールで 0x80 以上のバイト）で、直後が / でも . でもないもの。
  # パス（/dev/null、~/.claude、a/b、http://x/y、$(…)/x、<dir>/x）と /名前:名前（プラグイン）は拾わない
  while read -r at cmd; do
    [ -n "$cmd" ] || continue
    case " $skills $BUILTIN " in
      *" $cmd "*) ok "$at /$cmd がある" ;;
      *) ng "$at /$cmd は config/claude/skills/ にも許可リスト（BUILTIN）にも無い" ;;
    esac
  done <<EOF
$(cd "$1" && LC_ALL=C awk '{
  for (i = 1; i <= length($0); i++) {
    if (substr($0, i, 1) != "/" || (i > 1 && substr($0, i - 1, 1) ~ /[A-Za-z0-9.~\/_)}>-]/)) continue
    if (!match(substr($0, i + 1), /^[A-Za-z][A-Za-z0-9_-]*/)) continue
    q = substr($0, i + 1 + RLENGTH, 2)
    if (q !~ /^[\/.]/ && q !~ /^:[A-Za-z0-9]/) print FILENAME ":" FNR ":", substr($0, i + 1, RLENGTH)
  }
}' config/claude/CLAUDE.md config/claude/skills/*/SKILL.md config/claude/agents/*.md)
EOF
  links=$(awk '/^LINKS="/ { f = 1; next } f && /^"/ { exit } f { print $1 }' "$1/install.sh")
  for p in "$c"/skills/*/ "$c"/agents/*.md; do
    p="config/claude/${p#"$c"/}"; p=${p%/}
    expect "install.sh の LINKS に $p がある" has "$p" "$links"
  done
  # 流れの段の順序が、CLAUDE.md の流れの 1 行・手順の番号・README の流れの図で一致すること
  flow=$(grep -m 1 '^流れ（' "$c/CLAUDE.md" || true)
  expect "CLAUDE.md の流れの 1 行の段の順序（ブランチ → 要件の固定 → /accept → /verify → /review → コミット → /wrap-up → 統合）" \
    in_order "$flow" '→ ブランチ' '→ 要件の固定' '→ `/accept`' '→ `/verify`' '→ `/review`' '→ コミット' '→ `/wrap-up`' '→ 統合'
  steps=$(sed -n 's/^[0-9][0-9]*\. \*\*\([^*]*\)\*\*.*/\1/p' "$c/CLAUDE.md" | tr '\n' ' ')
  expect "CLAUDE.md の手順の番号の順序（$steps）" [ "$steps" = "ブランチ 要件の固定 TDD 受け入れ検証 検証 レビュー コミット 締め 統合 " ]
  diagram=$(awk '/^### 流れの全体図/ { f = 1; next } f && /^```/ { n++; if (n == 2) exit; next } f && n == 1' "$1/README.md")
  expect "README の流れの図の段の順序" \
    in_order "$diagram" '→ ブランチ' '→ 要件の写しを固定' '→ /accept' '→ /verify' '→ /review' '→ コミット' '→ /wrap-up' '→ 統合'
  # README に書いた e2e の場面の数が、tests/e2e-flow.sh の場面（使い方の行の [a|b|…]）の数と一致すること
  scenes=$(sed -n 's/^#   sh tests\/e2e-flow.sh .*\[\([a-z|]*\)\].*/\1/p' "$1/tests/e2e-flow.sh" | head -n 1 | tr '|' '\n' | grep -c . || true)
  expect "README の e2e の場面の数（tests/e2e-flow.sh の ${scenes} 場面）" grep -q "の ${scenes} 場面）" "$1/README.md"
  # bin/harness-hook の agent 名の定数（REVIEWER = "reviewer" の形。agents/<名前>.md があるもの）は、SubagentStop で hook が動くこと
  matcher=$(awk '/"SubagentStop"/ { f = 1 } f && match($0, /"matcher": *"[^"]*"/) { m = substr($0, RSTART, RLENGTH); sub(/^"matcher": *"/, "", m); sub(/"$/, "", m); print m; exit } f && /^[[:space:]]*[]][[:space:]]*,?[[:space:]]*$/ { exit }' "$c/settings.json")
  for a in $(grep -E '^[A-Z][A-Z0-9_]*(, *[A-Z][A-Z0-9_]*)* = "' "$1/bin/harness-hook" | grep -oE '"[^"]*"' | tr -d '"'); do
    [ -f "$c/agents/$a.md" ] || continue
    expect "settings.json の SubagentStop の matcher（$matcher）に $a（bin/harness-hook の定数）がある" has "$a" "$(printf '%s\n' "$matcher" | tr '|' '\n')"
  done
}

checks "$ROOT"

# 否定のテスト: 検査に要るファイルを一時ディレクトリに写し、1 か所ずつ壊して、その FAIL が出ること
T="$TMP/repo"
fresh() { # 壊す前の写しを作る
  rm -rf "$T"; mkdir -p "$T/config/claude" "$T/bin" "$T/tests"
  cp -R "$ROOT/config/claude/skills" "$ROOT/config/claude/agents" "$ROOT/config/claude/CLAUDE.md" "$ROOT/config/claude/settings.json" "$T/config/claude/"
  cp "$ROOT/install.sh" "$ROOT/README.md" "$T/"; cp "$ROOT/bin/harness-hook" "$T/bin/"; cp "$ROOT/tests/e2e-flow.sh" "$T/tests/"
}
edit() { # edit <ファイル> <sed の式>（sed -i は GNU と BSD で書き方が違うので使わない）
  sed "$2" "$1" > "$TMP/edit"; mv "$TMP/edit" "$1"
}
run() { out=$(VERBOSE=; checks "$T"); }
failed() { printf '%s\n' "$out" | grep '^FAIL ' | grep -qF -- "$1"; }  # failed <文言>: 直前の run がその文言を含む FAIL を出した
for d in "$ROOT"/config/claude/skills/*/; do s=$(basename "$d"); break; done

fresh; edit "$T/config/claude/skills/$s/SKILL.md" "s/^name:.*/name: not-$s/"; run
expect "否定: skills/$s の name がディレクトリ名と違えば FAIL" failed "skills/$s: name"
fresh; for f in "$T"/config/claude/skills/*/SKILL.md; do edit "$f" 's/^agent:.*/agent: no-such-agent/'; done; run
expect "否定: skill の agent の定義が無ければ FAIL" failed "agents/no-such-agent.md"
fresh; edit "$T/config/claude/skills/$s/SKILL.md" 's|^description: |description: （/no-such-in-description）|'; run
expect "否定: description のバッククォートの外の存在しないスラッシュコマンドは FAIL" failed "/no-such-in-description"
fresh; cat > "$T/config/claude/CLAUDE.md" <<'EOF'
`/dev/null` `/tmp/x` `/Users/a/b` `/plugin:cmd` `"$(git rev-parse --git-dir)/harness-x"` `/no-such-in-code ARK-nn`
/dev/null ~/.claude/skills tests/acceptance.sh http://x/y a/b <git-dir>/harness-y /plugin:cmd は拾わず、（/no-such-in-body）と /no-such-at-space x は拾う
EOF
run
expect "否定: バッククォートの中の存在しないスラッシュコマンドは FAIL" failed "/no-such-in-code"
expect "否定: 本文のバッククォートの外の存在しないスラッシュコマンドは FAIL" failed "/no-such-in-body"
expect "否定: 本文のバッククォートの外の存在しないスラッシュコマンド（後ろが空白）は FAIL" failed "/no-such-at-space"
picked=$(printf '%s\n' "$out" | grep '^FAIL config/claude/CLAUDE.md:' | grep -vF /no-such-) || true
expect "否定: パスとプラグインのコマンドは拾わない $picked" [ -z "$picked" ]
fresh; edit "$T/install.sh" "\\|^config/claude/skills/$s[[:space:]]|d"; run
expect "否定: LINKS に skills/$s が無ければ FAIL" failed "LINKS に config/claude/skills/$s "
fresh; edit "$T/config/claude/settings.json" '/"SubagentStop"/,/]/s/"matcher": *"[^"]*"/"matcher": "nobody"/'; run
expect "否定: SubagentStop の matcher に agent が無ければ FAIL" failed "SubagentStop の matcher"

fresh; edit "$T/config/claude/CLAUDE.md" '/^流れ（/s/→ ブランチ → 要件の固定/→ 要件の固定 → ブランチ/'; run
expect "否定: CLAUDE.md の流れの 1 行で要件の固定がブランチより前なら FAIL" failed "CLAUDE.md の流れの 1 行の段の順序"
fresh; edit "$T/config/claude/CLAUDE.md" 's/^1\. \*\*ブランチ\*\*/1. **要件の固定X**/'; run
expect "否定: CLAUDE.md の手順の番号が入れ替わっていれば FAIL" failed "CLAUDE.md の手順の番号の順序"
fresh; edit "$T/README.md" 's|→ ブランチ（基点から）|→ @|; s|→ 要件の写しを固定|→ ブランチ（基点から）|; s|→ @|→ 要件の写しを固定|'; run
expect "否定: README の流れの図でブランチと要件の固定を入れ替えれば FAIL" failed "README の流れの図の段の順序"
fresh; edit "$T/tests/e2e-flow.sh" 's/^\(#   sh tests\/e2e-flow.sh .*\)\]$/\1|extra]/'; run
expect "否定: e2e の場面が増えたのに README の場面の数が古ければ FAIL" failed "README の e2e の場面の数"

echo "skills: ok $passed, FAIL $fail"
[ "$fail" -eq 0 ]
