#!/bin/sh
# scripts/check の「一時ディレクトリの確かめ」の受け入れ検査: scripts/check を一時的な木に写し、tests/{static,install,acceptance}.sh を小さな偽物に置き換えて走らせる
# （本物の検査は走らせず、scripts/check の入れ子もない）。偽物は走ったら印を書き、MODE で何を残すかを変える。確かめること:
#   一時ディレクトリを作れない（mktemp の失敗・相対パス・ディレクトリでない・改行を含む）ときは、検査もプロセスの探索・停止も走らず失敗する
#     （一時ディレクトリは TMPDIR でなく短い /tmp に作るので、偽の mktemp を PATH の先頭に置いて確かめる）
#   何も残さなければ出力なしで通る / ファイルを残せば失敗して出す
#   一時ディレクトリを環境に持つプロセスを残せば、失敗してそのプロセスを出して止める（Linux だけ）
#   環境が TMPDIR=<一時ディレクトリ>/sub のような別のプロセスは、止めない（部分一致で当てない。Linux だけ）
#   TMPDIR が長くても（100 バイト程度）、tests/acceptance/stop-cleanup.sh は ok になる（ソケットのパスが長すぎて tmux が失敗しない。Linux だけ）
# 起こすプロセスはすべて自分の pid で管理し、名前では止めない
#   sh tests/acceptance/check-leftovers.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/check-leftovers.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
# 起こしたプロセスの後片づけ: 記録した pid のうち、コマンドラインがこの検査の sleep のものだけを止める（pid の使い回しで別のものに当てない）
cleanup() {
  [ -n "$T" ] || return 0
  for f in "$T"/pid.*; do
    [ -f "$f" ] || continue
    for p in $(cat "$f"); do
      case "$p" in ''|*[!0-9]*) continue ;; esac
      case "$(ps -o args= -p "$p" 2>/dev/null)" in *"sleep 599."*) kill "$p" 2>/dev/null ;; esac
    done
  done
  for f in "$T"/pid.*.dir; do # 読めなくした一時ディレクトリ（検査が /tmp/check.* に作ったもの）は、権限を戻して消す
    d="$(cat "$f" 2>/dev/null)"; case "$d" in /tmp/check.*) chmod -R u+rwx "$d" 2>/dev/null; rm -rf "$d" ;; esac
  done
  rm -rf "$T"
}
T=""; trap 'trap "" HUP INT TERM; cleanup' EXIT
trap 'exit 1' HUP INT TERM
T="$(trap '' HUP INT TERM; mktemp -d)"
R="$T/r"; mkdir -p "$R/scripts" "$R/tests"
cp "$ROOT/scripts/check" "$R/scripts/check"
for t in static install acceptance; do
  cat > "$R/tests/$t.sh" <<'SH'
first=1; [ -e "$MARK" ] && first=""; echo ran >> "$MARK"
[ -n "$first" ] || exit 0 # 残すのは最初の 1 本だけ（pid の記録を 1 つにする）
case "${MODE:-}" in
  file) echo x > "$TMPDIR/left" ;;
  proc) sleep 599.7 >/dev/null 2>&1 </dev/null & echo $! >> "$PIDF" ;;
  tmuxonly) env -u TMPDIR sleep 599.9 >/dev/null 2>&1 </dev/null & echo $! >> "$PIDF" ;;
  pipe) sleep 599.6 </dev/null & echo $! >> "$PIDF" ;; # 出力をつないだまま子を残す
  locked) echo "$TMPDIR" > "$PIDF.dir"; chmod 000 "$TMPDIR" ;; # 一時ディレクトリを読めなくする
  sub) mkdir "$TMPDIR/sub"; env -u TMUX_TMPDIR TMPDIR="$TMPDIR/sub" sleep 599.8 >/dev/null 2>&1 </dev/null & echo $! >> "$PIDF"
    rmdir "$TMPDIR/sub" ;;
esac
SH
done
# run <MODE> [<偽の mktemp が返す名前>|FAIL]: scripts/check の写しを走らせる。出力は $out、終了コードは $rc、偽の検査が走った印は $MARK。
# 2 つ目があれば PATH の先頭に偽の mktemp を置き、その名前を返させる（FAIL なら何も返さず失敗）
mkdir "$T/bin"
FAKE="$T/bin/mk""temp" # 形の検査が拾う語を、この偽物の名前では書かない
cat > "$FAKE" <<'SH'
#!/bin/sh
[ "$FAKE_OUT" != FAIL ] || exit 1
printf '%s\n' "$FAKE_OUT"
SH
chmod +x "$FAKE"
run() {
  n=$((n + 1)); PF="$T/pid.$1.$n"; rm -f "$MARK"; rc=0 # 実行ごとに別の pid の記録（失敗しても、起こした子を後片づけで止められる）
  out="$(MODE="$1" MARK="$MARK" PIDF="$PF" FAKE_OUT="${2:-}" PATH="${2:+$T/bin:}$PATH" sh "$R/scripts/check" 2>&1)" || rc=$?
}
MARK="$T/mark"; n=0
alive() { s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }
# 子を止めた後に消えるのを少し待つ
gone() { i=0; while alive "$1" && [ "$i" -lt 30 ]; do i=$((i + 1)); sleep 0.1; done; ! alive "$1"; }

run proc FAIL # 作成の失敗（探索や停止が走るなら、proc の残りが出る）
if [ "$rc" = 1 ] && [ ! -e "$MARK" ] && [ ! -e "$PF" ] && printf '%s\n' "$out" | grep -q '^FAIL 一時ディレクトリを作れない'; then
  ok "一時ディレクトリを作れなければ、検査を走らせず失敗する"; else ng "作成の失敗: rc=$rc 印=$([ -e "$MARK" ] && echo あり || echo なし) 出力=$out"; fi
ok=1; export ok; run proc FAIL; unset ok # 環境に ok=1 があっても、作れなければ走らない
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "環境に ok=1 があっても、作れなければ検査を走らせず失敗する"; else ng "環境に ok=1 がある: rc=$rc 出力=$out"; fi
nl="$T/a$(printf '\nb')"; mkdir "$nl"; run proc "$nl" # 改行を含む一時ディレクトリ名（grep -F -e は改行でパターンを分けるので、別のプロセスに当たる）
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "名前に改行があっても、検査を走らせず失敗する"; else ng "改行を含む名前: rc=$rc 出力=$out"; fi
printf 'x' > "$T/notdir"; run proc "$T/notdir" # ディレクトリでない
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "ディレクトリでなくても、検査を走らせず失敗する"; else ng "ディレクトリでない: rc=$rc 出力=$out"; fi
run proc rel # 絶対パスでない
if [ "$rc" = 1 ] && [ ! -e "$MARK" ]; then ok "絶対パスでなくても、検査を走らせず失敗する"; else ng "相対パス: rc=$rc 出力=$out"; fi

run none
if [ "$rc" = 0 ] && [ -z "$out" ] && [ "$(wc -l < "$MARK" | tr -d ' ')" = 3 ]; then ok "何も残さなければ、3 本とも走って出力なしで通る"; else ng "何も残さない: rc=$rc 印=$(cat "$MARK" 2>/dev/null | wc -l) 出力=$out"; fi

run file
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL 検査が普通に終わった後に残っている' && printf '%s\n' "$out" | grep -q '/left$'; then
  ok "ファイルが残れば、失敗して残ったものを出す"; else ng "ファイルを残す: rc=$rc 出力=$out"; fi

if [ -d /proc/self ]; then
  run proc; p="$(cat "$PF" 2>/dev/null)"
  if [ "$rc" = 1 ] && [ -n "$p" ] && printf '%s\n' "$out" | grep -q "^ *$p sleep 599.7" && gone "$p"; then
    ok "環境に一時ディレクトリを持つプロセスが残れば、失敗してそのプロセスを出し、止める"; else ng "プロセスを残す: rc=$rc pid=$p 生きている=$(alive "${p:-0}" && echo はい || echo いいえ) 出力=$out"; fi
  run tmuxonly; p="$(cat "$PF" 2>/dev/null)" # 環境が TMUX_TMPDIR=<一時ディレクトリ> だけのプロセス
  if [ "$rc" = 1 ] && [ -n "$p" ] && printf '%s\n' "$out" | grep -q "^ *$p sleep 599.9" && gone "$p"; then
    ok "環境が TMUX_TMPDIR だけのプロセスが残っても、失敗してそのプロセスを出し、止める"; else ng "TMUX_TMPDIR だけのプロセス: rc=$rc pid=$p 出力=$out"; fi
  run sub; p="$(cat "$PF" 2>/dev/null)"
  if [ "$rc" = 0 ] && [ -z "$out" ] && [ -n "$p" ] && alive "$p"; then
    ok "環境が TMPDIR=<一時ディレクトリ>/sub のプロセスは、止めない（部分一致で当てない）"; else ng "別のプロセス: rc=$rc pid=$p 生きている=$(alive "${p:-0}" && echo はい || echo いいえ) 出力=$out"; fi
  [ -z "$p" ] || kill "$p" 2>/dev/null
  # 子が検査の出力（パイプ）をつないだまま残っても、検査は戻って、残った子を出して止める（上限 30 秒）
  n=$((n + 1)); PF="$T/pid.pipe.$n"; rm -f "$MARK" "$T/rc.pipe"
  ( MODE=pipe MARK="$MARK" PIDF="$PF" sh "$R/scripts/check" > "$T/out.pipe" 2>&1; echo $? > "$T/rc.pipe" ) &
  pw=$!; i=0; while [ ! -e "$T/rc.pipe" ] && [ "$i" -lt 300 ]; do i=$((i + 1)); sleep 0.1; done
  p="$(cat "$PF" 2>/dev/null)"
  if [ "$(cat "$T/rc.pipe" 2>/dev/null)" = 1 ] && [ -n "$p" ] && grep -q "^ *$p sleep 599.6" "$T/out.pipe" && gone "$p"; then
    ok "子が出力をつないだまま残っても、検査は戻って失敗し、その子を出して止める"; else ng "出力をつないだ子: rc=$(cat "$T/rc.pipe" 2>/dev/null) pid=$p 出力=$(cat "$T/out.pipe")"; fi
  case "$(ps -o args= -p "${p:-0}" 2>/dev/null)" in *"sleep 599."*) kill "$p" 2>/dev/null ;; esac # 戻らなかったときは、子を止めて検査を終わらせる
  wait "$pw"
  # 長い TMPDIR（100 バイト程度）でも stop-cleanup.sh は ok になる（一時ディレクトリを TMPDIR の下に重ねると、ソケットのパスが長すぎて tmux が失敗する）
  L="$T"; while [ "${#L}" -lt 100 ]; do L="$L/long-directory-name"; done; mkdir -p "$L"
  out="$(TMPDIR="$L" sh "$ROOT/tests/acceptance/stop-cleanup.sh" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then ok "TMPDIR が ${#L} バイトでも stop-cleanup.sh は通る"; else ng "長い TMPDIR（${#L} バイト）で stop-cleanup.sh が失敗する: $out"; fi
  # static.sh（tmux.conf の節）と agent-status.sh も、単独で長い TMPDIR で通り、/tmp に作る <名前>-<pid>.* を自分の trap で消す
  # （scripts/check の確かめは /tmp の下を見ない。pid で絞るので、同時に走るほかの実行に影響されない）
  for t in static:tests/static.sh agent:tests/acceptance/agent-status.sh; do
    nm="${t%%:*}"; f="${t#*:}"
    out="$(TMPDIR="$L" sh -c 'echo $$ > "$1"; exec sh "$2"' _ "$T/lp.$nm" "$ROOT/$f" 2>&1)"; rc=$?
    q="$(cat "$T/lp.$nm" 2>/dev/null)"; rest=""; case "$q" in ''|*[!0-9]*) ;; *) rest="$(ls -d /tmp/"$nm"-"$q".* 2>/dev/null)" ;; esac
    if [ "$rc" = 0 ] && [ -z "$rest" ]; then ok "TMPDIR が ${#L} バイトでも $f は通り、/tmp の一時ディレクトリを残さない"
    else ng "長い TMPDIR（${#L} バイト）で $f: rc=$rc 残り=[$rest] 出力=$(printf '%s\n' "$out" | grep -v '^ok ' | head -3)"; [ -z "$rest" ] || rm -rf $rest; fi
  done
fi

# 検査が一時ディレクトリを読めなくしても（find が失敗する）、成功にしない。root は権限で止まらないので省く
if [ "$(id -u)" != 0 ]; then
  run locked; d="$(cat "$PF.dir" 2>/dev/null)"; chmod -R u+rwx "$d" 2>/dev/null; rm -rf "$d"
  if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^FAIL 一時ディレクトリを調べられない'; then ok "一時ディレクトリを読めなくされたら、調べられないので失敗する"; else ng "読めない一時ディレクトリ: rc=$rc 出力=$out"; fi
fi

[ "$fail" = 0 ] && echo "acceptance check-leftovers: ok"
[ "$fail" = 0 ]
