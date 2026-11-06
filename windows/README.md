# windows

ネイティブの Windows（WSL ではない）で mac / linux と同じ環境を作る。管理者は不要。設定は共通のファイルへのシンボリックリンクなので、開発者モード（設定 → システム → 開発者向け）が要る。シェルは PowerShell 7.4 以上、端末は Windows Terminal、Claude Code（CLI）は herdr の中で動かす。

```powershell
git clone https://github.com/arkrtm/dotfiles.git $HOME\dotfiles
pwsh -File $HOME\dotfiles\windows\install.ps1   # 何度実行しても安全。既存ファイルは *.bak.<日時> に退避
```

## ファイル

- `windows/install.ps1`: 入口（下の「install.ps1 がやること」）。`-LinksOnly` はリンクと ponytail の band だけ、`-HomeDir <path>` は配置先のホーム（本物のホームと違うときは `-LinksOnly` と一緒にだけ使え、AppData・Documents もその下にする。テスト用）。worktree（`.git` がファイル）からは `DOTFILES_ALLOW_WORKTREE` が無ければ実行しない
- `windows/gitbash-lib.ps1`・`windows/gitbash-lib.cmd`: Git for Windows の場所を探す（`Get-GitRoot`・`Get-GitBash`、cmd 版は `GITBASH` に入れる）。Git は Program Files とは限らない（ユーザー単位の `%LOCALAPPDATA%\Programs\Git` など）ので、PATH の `git.exe` の 1 つ上と 2 つ上（`cmd\git.exe`・`bin\git.exe`・`mingw64\bin\git.exe`・`ucrt64\bin\git.exe`）の `bin\bash.exe` を先に、無ければ Program Files・Program Files (x86)・`%LOCALAPPDATA%\Programs` の `Git` の順に探す。`windows/bin` のラッパーと install.ps1 が使う。見つからなければ「bash.exe が見つからない」で終了コード 1
- `windows/install-lib.ps1`: install.ps1 とテストが dot-source する関数（リンク、ユーザー環境変数と Path、ssh の権限、改行の検査、Codex の config.toml の生成、Windows Terminal の settings.json の更新）
- `windows/.gitattributes`: `windows/` は LF で取り出す（Git Bash で動かすため）。`.cmd` だけ CRLF
- `windows/powershell/profile.ps1`: pwsh のプロファイル（CurrentUserAllHosts。`shell/zshenv`・`zprofile`・`zshrc` の移植）。前半は毎回読む環境（EDITOR・VISUAL・FNM_DIR、PATH の先頭に fnm の既定・`~/.local/bin`・mise の shims・あれば `~/.cargo/bin`。重複を畳む）でプロセスを起動しない。PSReadLine が無い（非対話）ならそこで終わる。後半は UTF-8、vi モード（モードでカーソルの形を変える）、履歴（50000 行、重複なし、空白で始まる行は残さない）、履歴からの候補、Tab で一覧、starship → fnm → mise activate → PSFzf（Ctrl+t・Ctrl+r・Alt+c）、`ll`・`la`・`lt`・`lg`・`lzd`・`cw`。`ls`・`cat` は置き換えない
- `windows/claude/settings.json`: Claude Code の設定（`config/claude/settings.json` の Windows 版）。違いは、PowerShell ツール用の allow・deny（Bash の規則は PowerShell ツールに効かない）、`env` の `CLAUDE_CODE_USE_POWERSHELL_TOOL`（Git Bash の場所は書かない。Claude Code が PATH の git から見つける。Git が標準の場所に無く見つからないときは、ユーザー環境変数に `CLAUDE_CODE_GIT_BASH_PATH`（`bash.exe` のパス）を設定する）、`agent-status` のフックが無い、bin のフックは `windows/posix/hook` 経由（ホームに空白があっても分かれないよう、`"$HOME/dotfiles/windows/posix/hook"` のように実行ファイルのパスを引用符で囲む。ステータスラインのパスも同じ）、SessionStart の先頭に `hook env`、ステータスラインは `statusline.ps1`、通知は端末のベル（`preferredNotifChannel`）。ほかは共通の設定と同じ
- `windows/claude/statusline.ps1`: `config/claude/statusline.sh` の PowerShell 版（出力・アイコン・メーター・コンテキストのキャッシュ・Codex の上限・herdr の pane の名前は同じ。jq・awk を使わない）
- `windows/claude/CLAUDE.md`: `config/agents/AGENTS.md` を読み込み、Windows の違いを足す（スクリーンショットは `~/Pictures/Screenshots`、dotfiles のコマンドは Bash ツールで）
- `windows/posix/run`: Git Bash で `bin/<名前>` を動かす。PATH の先頭に jq の shim と dotfiles の `bin` を置き、`/clear` を Windows のパスに直させない（`MSYS2_ARG_CONV_EXCL`。handoff が herdr に送る）
- `windows/posix/hook`: Claude Code のフック（Git Bash で動く）。`hook env` は `CLAUDE_ENV_FILE` に PATH と `/clear` の除外の行を足す（Bash ツール用）。`hook integrate-hook` は入力の `cwd`・`file_path`・`notebook_path` を `cygpath -u` で `/c/...` にしてから渡す。ほかは `bin/<名前>` をそのまま
- `windows/posix/shims/jq`: `jq.exe -b`（Windows の jq は `-b` が無いと CRLF で出す）。run・hook と Bash ツールの PATH にだけ置き、Windows の Path には入れない
- `windows/bin/*.cmd`・`windows/bin/*.ps1`: `integrate`・`codex-review`・`notify`・`handoff`・`agent-pane` を pwsh・cmd から呼ぶ（`posix/run` 経由。Git Bash は上の gitbash-lib で探すので、Git が Program Files に無くても動く）。ユーザーの Path に入る。pwsh は同じ場所の `.ps1` を先に選び、引数をそのまま渡す。`.cmd` は cmd.exe を通るので `"`・`^`・`&`・`|` を含む引数は壊れる
- `windows/git/hooks-nosign/commit-msg`: `config/git/hooks-nosign/commit-msg` を `LC_ALL=C` で動かす（Git for Windows の grep は既定の C.UTF-8 で絵文字に一致しない）。リンクを解決してからリポジトリを辿る
- `windows/herdr/config.toml`: `config/herdr/config.toml` と同じで、最後の kitty の画像だけ `[terminal]` `kitty_graphics = false`（Windows Terminal は kitty 方式の画像を表示できない）
- `windows/terminal/dotfiles.json`: Windows Terminal の fragment（配色 Atom One Dark）。フォント・サイズ・余白・履歴は fragment では profiles.defaults に勝てないので install.ps1 が settings.json に書く
- `windows/geoview/`: `bin/geoview` を動かす uv の tool（`geoview.exe`。依存は bin/geoview の PEP 723 と同じ、Python 3.12 以上）。dotfiles の場所は `DOTFILES`、無ければ `~/dotfiles`
- `windows/tests/`: Pester 5 の検査（下の「検査」）
- `.github/workflows/windows.yml`: windows-latest で `windows/tests/run.ps1`（PR と main への push）

## Windows でも使う共通のファイル

リンク（`install.ps1` が作る。`~` は `%USERPROFILE%`）:

- `config/git/config`・`config/git/ignore` → `~/.config/git/`（`hooks-nosign` は `windows/git/hooks-nosign` へ）
- `config/mise/config.toml` → `~/.config/mise/config.toml`
- `config/starship.toml` → `~/.config/starship.toml`
- `config/bat/config` → `%APPDATA%\bat\config`
- `config/nvim` → `%LOCALAPPDATA%\nvim`
- `config/yazi` → `%APPDATA%\yazi\config`
- `config/agents/AGENTS.md` → `~/.codex/AGENTS.md`（Claude Code は `windows/claude/CLAUDE.md` から読み込む）
- `config/agents/skills/issue`・`wrap-up`・`handoff` → `~/.claude/skills/`、`issue`・`wrap-up` → `~/.agents/skills/`
- `ssh/config` → `~/.ssh/config`
- Windows 版へのリンク: `windows/claude/settings.json`・`CLAUDE.md` → `~/.claude/`、`windows/herdr/config.toml` → `%APPDATA%\herdr\config.toml`、`windows/powershell/profile.ps1` → `Documents\PowerShell\profile.ps1`、`windows/terminal/dotfiles.json` → `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\dotfiles\dotfiles.json`

リンクしないもの:

- `config/codex/config.toml.tmpl`: `~/.codex/config.toml` を生成する（下の手順 10）
- `bin/` のコマンドとフック: `windows/posix/run`・`hook` が Git Bash で動かす
- `config/git/hooks-nosign/commit-msg`: `windows/git/hooks-nosign/commit-msg` が呼ぶ
- `bin/geoview`: `windows/geoview` の `geoview.exe` が動かす

## install.ps1 がやること（順に）

1. シンボリックリンクを作れるか試す（作れなければ開発者モードを案内して終了コード 1）
2. 上のリンクを作る（同じ先を指すリンクなら何もしない。ほかに何かあれば `*.bak.<日時>` に退避）。`~/.claude/.ponytail-band` が無ければ `off` を書く。`-LinksOnly` はここで終わる
3. 以降は失敗しても `warning:` を出して続ける
4. git: このクローンの `core.autocrlf=input`。CRLF で取り出された LF のファイル（`.cmd` は除く）があり、作業ツリーに変更が無ければ LF で取り出し直す
5. `~/.gitconfig` が無ければ空で作る（`git config --global` の書き込み先。中身は消さない）
6. ssh: `ssh/config` に自分・SYSTEM・Administrators 以外が書き込めれば icacls で絞る。`ssh -G` を確かめる
7. ユーザー環境変数（HKCU\Environment）: `EDITOR`・`VISUAL`=nvim、`FNM_DIR`、`MISE_DISABLE_TOOLS`、`YAZI_FILE_ONE`（Git の `usr\bin\file.exe`。Git の場所は gitbash-lib で探す）。Path の先頭に fnm の既定・`~/.local/bin`・mise の shims・`windows/bin`（`%USERPROFILE%`・`%LOCALAPPDATA%` のままの REG_EXPAND_SZ）。`HOME`・`XDG_CONFIG_HOME` は入れない
8. mise（`~/.local/bin/mise.exe`、install.sh と同じ版）と `mise install`（ホームで。`gh auth token` をこのプロセスだけの `GITHUB_TOKEN` にする）
9. fnm で最新の LTS の Node を入れて既定にする
10. Codex: テンプレートから `~/.codex/config.toml` を作る（`@HOME@` は `/` 区切りのホーム。既存の `[hooks.state…]`・`[projects.…]`・`[tui…]`・`[windows…]` を引き継ぐ。違うときだけ退避して書く）。codex が無ければ公式のインストーラーで入れ、ユーザーの Path を手順 7 の形に戻す。ponytail の marketplace と plugin を入れる。tinymemory があれば `tinymemory init codex`
11. Neovim のプラグインを `lazy-lock.json` に揃える（`Lazy! restore`）
12. PSFzf（PSGallery）
13. geoview（uv があれば `uv tool install`）
14. Windows Terminal の settings.json: profiles.defaults に配色・Hack Nerd Font Mono 12・余白・履歴 50000、PowerShell 7 のプロファイルがあれば既定にする（変わるときだけ退避して書く。ほかのキーとプロファイルはそのまま）
15. `done.` と残りの手順を出す

## 手で入れるもの

- herdr: `winget install Herdr.Herdr`
- Claude Code の CLI: `irm https://claude.ai/install.ps1 | iex`（`~/.local/bin/claude.exe`）
- win32yank（Neovim のクリップボード）: `winget install equalsraf.win32yank`
- C コンパイラ: `winget install Microsoft.VisualStudio.2022.BuildTools`（C++ のワークロード。管理者が要る）。nvim-treesitter は `cc` という名前の実行ファイルが PATH に無いと読み込まない（Build Tools のコンパイラは `cl.exe`）
- Docker Desktop（lazydocker を使うなら）: `winget install Docker.DockerDesktop`

## install の後に手でやること

- ターミナルを開き直し、Claude desktop を再起動する（ユーザー環境変数は新しいプロセスから効く）
- `codex login`。Codex の初回に Windows のサンドボックスを選ぶ（`~/.codex/config.toml` の `[windows]` に保存され、install.ps1 が引き継ぐ）
- Claude Code のプラグイン（`config/claude/README.md`）:
  `claude plugin marketplace add anthropics/claude-plugins-official` → `claude plugin install superpowers@claude-plugins-official` → `claude plugin marketplace add arkrtm/tinymemory` → `claude plugin install tinymemory@tinymemory` → `claude plugin marketplace add DietrichGebert/ponytail` → `claude plugin install ponytail@ponytail`
- Claude Code の最初の起動でフックを承認する

## 制限

- tmux は無い（Windows 版が無い）。herdr を使う。`agent-status`（tmux の状態表示）は tmux だけなので使わない
- Windows Terminal は OSC 777 のデスクトップ通知を出さない。Claude Code の通知は端末のベル
- herdr の中の yazi は画像を表示しない（kitty の画像を切っている）
- tinymemory は Windows 版のリリースが出るまで入れない（`MISE_DISABLE_TOOLS` で mise から外す。settings.json の tinymemory のフックは無ければ何もしない）
- `MISE_DISABLE_TOOLS` は `install.ps1` の `$MiseDisable`（tmux・tinymemory）。Windows 版の無い道具で `mise install` が失敗したらここに足す
- Codex のサンドボックスは Microsoft Store 版の pwsh を動かせず、サンドボックスの中のコマンドは Windows PowerShell 5.1 になる
- `windows/bin/*.cmd` を cmd.exe から呼ぶと `"`・`^`・`&`・`|` を含む引数が壊れる（pwsh からは `.ps1` が選ばれるので壊れない）

## 検査

```powershell
pwsh -NoProfile -File windows/tests/run.ps1
```

Pester 5 が要る（無ければ `Install-PSResource Pester -Scope CurrentUser`）。ネットワークを使わず、本物のホームとレジストリに触らない（install.ps1 は一時ホームに `-LinksOnly`）。Git Bash が無ければ Git Bash の検査を、jq.exe が無ければ jq の検査を飛ばす。

- `syntax.Tests.ps1`: .ps1 の構文・BOM・`#Requires -Version 7.4`（`Select-Object -CaseInsensitive` が 7.4 から）、JSON、文字コードと改行、シェルスクリプトの構文
- `policy.Tests.ps1`: リポジトリの禁止の文字列・ファイル名、既存の追跡しているファイルを変えていない
- `install.Tests.ps1`: リンク・退避・2 回目は何もしない・worktree の拒否・band、install-lib.ps1 の関数
- `claude.Tests.ps1`: settings.json と共通の設定の違い、statusline.ps1 の出力とキャッシュ
- `posix.Tests.ps1`: `hook env`、jq の shim、commit-msg、integrate-hook、`/clear`、`windows/bin` の shim
- `gitbash.Tests.ps1`: gitbash-lib.ps1（偽の Git のルートを PATH に置いて、`git.exe` の 4 つの置き場所と標準の場所の順を確かめる）、`windows/bin` のラッパー（偽の `bash.exe` を PATH の `git.exe` の隣に置く。空白を含むパスの dotfiles と、Program Files の外の Git への junction）、settings.json のフックとステータスラインを HOME に空白を含めて `bash -c` で動かす
- `herdr.Tests.ps1`: herdr の設定と共通のファイルの違い
