#!/bin/sh
# bare の pre-receive の受け入れ検査（ARK-89）: config/git/hooks/pre-receive をリンクした一時的な bare に push し、
# main への push は受け取ったコミットで scripts/check が通るときだけ受け付けること（git のリポジトリとして検査し、
# export-ignore のファイルも欠けない）、main 以外は検査しないこと、一時ディレクトリを残さないこと
#   sh tests/acceptance/pre-receive.sh      失敗した項目と要約だけ
#   V=1 sh tests/acceptance/pre-receive.sh  通った項目も
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { [ -n "${V:-}" ] && echo "ok   $1"; return 0; }
ng() { echo "FAIL $1"; fail=1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# 業務サーバーのように、グローバルの core.hooksPath が別の場所を指していても効く入れ方（README の手順）で入れる
mkdir -p "$T/hooks-nosign"; printf '[core]\n\thooksPath = %s\n' "$T/hooks-nosign" > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
# フックが作る一時ディレクトリをここで数える（ローカルの push ではフックが環境変数を引き継ぐ）
mkdir -p "$T/tmp"; export TMPDIR="$T/tmp"

git init -q --bare -b main "$T/r.git"
ln -s "$ROOT/config/git/hooks/pre-receive" "$T/r.git/hooks/pre-receive"
git -C "$T/r.git" config core.hooksPath hooks
git clone -q "$T/r.git" "$T/w" 2>/dev/null
cd "$T/w"
main() { git -C "$T/r.git" rev-parse -q --verify main; }
push() { git push -q origin "$1" 2>"$T/err"; }

# git のリポジトリを前提にし、export-ignore のファイルも要る検査
mkdir scripts
printf '#!/bin/sh\ngit ls-files | grep -qx scripts/check && [ -f ignored.sh ]\n' > scripts/check; chmod +x scripts/check
echo x > ignored.sh; echo 'ignored.sh export-ignore' > .gitattributes
git add -A && git commit -qm good
push HEAD:main && [ "$(main)" = "$(git rev-parse HEAD)" ] \
  && ok "検査が通るコミットは main へ push できる" || ng "検査が通るコミットが拒否された: $(cat "$T/err")"

printf '#!/bin/sh\necho check-failed-here\nexit 1\n' > scripts/check; git commit -qam fail
m0="$(main)"
if push HEAD:main; then ng "検査が通らないコミットが main に入った"
else [ "$(main)" = "$m0" ] && grep -q check-failed-here "$T/err" && ok "検査が通らないコミットは拒否し、検査の出力を返す" || ng "拒否の後: $(cat "$T/err")"; fi
push HEAD:feature/y && ok "main 以外のブランチは検査しない" || ng "main 以外への push が拒否された: $(cat "$T/err")"

git reset -q --hard HEAD~1; git rm -q scripts/check; git commit -qm rm
if push HEAD:main; then ng "scripts/check が無いコミットが main に入った"
else [ "$(main)" = "$m0" ] && grep -q scripts/check "$T/err" && ok "scripts/check が無いコミットは拒否する" || ng "拒否の後: $(cat "$T/err")"; fi

[ -z "$(ls -A "$T/tmp")" ] && ok "一時ディレクトリを残さない" || ng "一時ディレクトリが残った: $(ls -A "$T/tmp")"

[ "$fail" = 0 ] && echo "acceptance pre-receive: ok"
[ "$fail" = 0 ]
