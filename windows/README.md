# windows

ネイティブの Windows（WSL ではない）で mac / linux と同じ環境を作る。設定は共通のファイルへのシンボリックリンクなので、開発者モードが要る。シェルは PowerShell 7.4 以上、端末は Windows Terminal、Claude Code（CLI）は herdr の中で動かす。`install.ps1` は管理者が要らない（変えるのはユーザーの領域と HKCU だけ）。前提の開発者モードと、winget でマシン全体に入れるものは管理者の承認（UAC）が要る。

## 新しい PC での導入

上から順に行う。エージェント（Claude Code・Codex など）が読んで進められるように、各手順に担い手と、そのまま実行するコマンドと、確かめるコマンドを書く。「エージェントが実行」の手順はエージェントが実行し、「人がやる」の手順はエージェントが理由と操作を伝えて人に頼む。確かめるコマンドが期待どおりなら次へ進む。コマンドは PowerShell（手順 4 までは Windows PowerShell 5.1 でよい）。

エージェントはターミナルを開き直す代わりに、PATH を使うコマンドの前でこれを実行する（winget などが書いた PATH は新しいプロセスから効く。同じプロセスの中だけ効く）:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
```

1. 開発者モードをオンにする — 人がやる（理由: 設定画面。管理者の承認が要る）。設定 → システム → 開発者向け → 開発者モード。エージェントは `Start-Process ms-settings:developers` で画面を開ける
   - 確かめる: `Get-ItemPropertyValue HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock AllowDevelopmentWithoutDevLicense` が `1`
2. Git・PowerShell 7・VC++ ランタイム — 人がやる（理由: 初回は winget の規約への同意を聞かれる。UAC の承認も要る）。エージェントは下のコマンドを人に渡し、人がターミナルで実行して、規約に同意し UAC を承認する（この手順は人がそばにいる）
   ```powershell
   winget install -e --id Git.Git --source winget
   winget install -e --id Microsoft.PowerShell --source winget --installer-type wix
   winget install -e --id Microsoft.VCRedist.2015+.x64 --source winget
   ```
   - PowerShell 7 は MSI 版（`--installer-type wix`）。MSIX 版（Microsoft Store 版。winget が既定で選ぶことがある）は Codex のサンドボックスから動かせない。VC++ ランタイムが無いと mise・nvim・bat・yazi が起動しない。ARM64 の PC は `Microsoft.VCRedist.2015+.arm64`
   - 入っていれば winget は「既に入っている」と出して 0 以外で終わる。成否は確かめるコマンドで見る
   - `winget` が無ければ Microsoft Store の「アプリ インストーラー」を入れる（人がやる）。Windows Terminal が無ければ `winget install -e --id Microsoft.WindowsTerminal --source winget`。ssh（OpenSSH のクライアント。Windows 11 は普通入っている）が無ければ、管理者の PowerShell で `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`（Windows Update に届かず 0x80072ee6 などで失敗したら `winget install -e --id Microsoft.OpenSSH.Preview --source winget`）
   - 確かめる（エージェントが実行。PATH を読み直してから）: `git --version`、`pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'` が 7.4 以上、`Test-Path $env:WINDIR\System32\vcruntime140.dll` が `True`、`ssh -V` が動く
3. Hack Nerd Font（Nerd Fonts 3.5.0 以上。Windows Terminal のフォントと、starship・statusline のアイコン）— エージェントが実行（自分用に入れるので管理者は要らない）
   ```powershell
   $ProgressPreference = 'SilentlyContinue'
   $zip = Join-Path $env:TEMP 'HackNerdFont.zip'
   $src = Join-Path $env:TEMP 'HackNerdFont'
   Invoke-WebRequest -UseBasicParsing -Uri https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip -OutFile $zip
   Expand-Archive -LiteralPath $zip -DestinationPath $src -Force
   $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
   $reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
   if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
   if (-not (Test-Path $reg)) { New-Item -Path $reg | Out-Null }
   Get-ChildItem -LiteralPath $src -Recurse -Filter 'HackNerdFont*.ttf' | ForEach-Object {
     $dst = Join-Path $dir $_.Name
     if (-not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $_.FullName -Destination $dst }
     $name = ($_.BaseName -replace '-', ' ' -creplace '(?<=[a-z])(?=[A-Z])', ' ') + ' (TrueType)'
     New-ItemProperty -Path $reg -Name $name -Value $dst -PropertyType String -Force | Out-Null
   }
   ```
   - 確かめる: `Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\HackNerdFontMono-Regular.ttf"` が `True`
4. ターミナルを開き直す — 人がやる（理由: エージェントは自分が動いているターミナルを開き直せない）。Windows Terminal のウィンドウをすべて閉じて、開き直す（初めてなら一度起動する）。PATH・フォントと、Windows Terminal の PowerShell 7 のプロファイル（起動のときに作られる）が新しくなる。エージェントが Windows Terminal の中で動いていたなら、開き直した後にエージェントを起動し直して手順 5 から続ける
   - 確かめる: 新しいタブで `git --version` と `pwsh -v` が動く
5. clone — エージェントが実行。場所は `$HOME\dotfiles` に固定（Claude Code のフック・ステータスライン・`CLAUDE.md` がこの場所を指す）
   ```powershell
   git clone https://github.com/arkrtm/dotfiles.git $HOME\dotfiles
   ```
   - 確かめる: `git -C $HOME\dotfiles log -1 --oneline`
6. install.ps1 — エージェントが実行
   ```powershell
   pwsh -File $HOME\dotfiles\windows\install.ps1   # 何度実行しても安全。既存ファイルは *.bak.<日時> に退避
   ```
   - 全部成功すると最後に `done.` を出して終了コード 0。失敗した手順があっても残りは続け、最後に失敗した手順の名前と理由の一覧を出して終了コード 1 で終わる（`done.` は出さない）。理由を直して、もう一度実行する:
     - `Windows Terminal`（PowerShell 7 のプロファイルが無い・settings.json が無い）: 人が Windows Terminal を開き直して（初めてなら一度起動して）から再実行
     - `mise install`（GitHub の API の 403）: 手順 7 の後に再実行。gh は mise install が入れるので、`gh --version` が動かなければ、先に人が `winget install -e --id GitHub.cli --source winget` で単独で入れる（理由: UAC の承認。規約への同意を聞かれたら人が同意する）。`nvim`・`geoview` は mise install の失敗に続いて失敗する
     - `mise install`（lock に無い道具・checksum が違う配布物）: lock を作り直す（ルートの README の「版の固定と更新」）
     - `git の改行`: `~/dotfiles` の作業ツリーの変更を片づけてから再実行
   - 確かめる: `$LASTEXITCODE` が `0`
7. GitHub のログイン — 人がやる（理由: ログイン）。新しいターミナルで `gh auth login`
   - 確かめる: `gh auth status`
8. herdr と Claude Code の CLI — エージェントが実行（winget の規約には手順 2 で同意済み。もし同意を聞かれたら、そのコマンドは人に渡して人が同意する）
   ```powershell
   winget install -e --id Herdr.Herdr --source winget
   irm https://claude.ai/install.ps1 | iex   # ~/.local/bin/claude.exe
   ```
   - 確かめる（PATH を読み直してから）: `herdr --version`、`claude --version`
9. Codex のログイン — 人がやる（理由: ログイン）。`codex login`。Codex の初回に Windows のサンドボックスを選ぶ（`~/.codex/config.toml` の `[windows]` に保存され、install.ps1 が引き継ぐ）
   - 確かめる: `codex login status`
10. Claude Code のプラグイン（`config/claude/README.md`）— エージェントが実行
    ```powershell
    claude plugin marketplace add anthropics/claude-plugins-official
    claude plugin install superpowers@claude-plugins-official
    claude plugin marketplace add arkrtm/tinymemory
    claude plugin install tinymemory@tinymemory
    claude plugin marketplace add DietrichGebert/ponytail
    claude plugin install ponytail@ponytail
    ```
    - 確かめる: `claude plugin list` に superpowers・tinymemory・ponytail がある
11. Claude Code の最初の起動 — 人がやる（理由: ログインとフックの承認）。新しいタブで `herdr` を開き、その中で `claude` を起動してログインし、フックを承認する。Claude desktop を使っているなら再起動する（ユーザー環境変数は新しいプロセスから効く）
12. 確かめる — 人がやる（理由: 新しいタブを開いて見る）。Windows Terminal で新しいタブを開く（PowerShell 7 で開き、フォントが無いという警告が出ない）。そのタブで:
    ```powershell
    $PSVersionTable.PSVersion                                        # 7.4 以上
    $env:STARSHIP_SHELL                                              # pwsh（プロファイルの starship が効いている）
    Get-Command nvim, gh, rg, fzf, uv | Format-Table Name, Source    # どれも見つかる
    ```

任意: Docker Desktop（lazydocker を使うなら）`winget install -e --id Docker.DockerDesktop --source winget`

## ファイル

- `windows/install.ps1`: 入口（下の「install.ps1 がやること」）。`-LinksOnly` はリンクと ponytail の band だけ、`-HomeDir <path>` は配置先のホーム（本物のホームと違うときは `-LinksOnly` と一緒にだけ使え、AppData・Documents もその下にする。テスト用）。worktree（`.git` がファイル）からは `DOTFILES_ALLOW_WORKTREE` が無ければ実行しない
- `windows/gitbash-lib.ps1`・`windows/gitbash-lib.cmd`: Git for Windows の場所を探す（`Get-GitRoot`・`Get-GitBash`、cmd 版は `GITBASH` に入れる）。Git は Program Files とは限らない（ユーザー単位の `%LOCALAPPDATA%\Programs\Git` など）ので、PATH の `git.exe` の 1 つ上と 2 つ上（`cmd\git.exe`・`bin\git.exe`・`mingw64\bin\git.exe`・`ucrt64\bin\git.exe`）の `bin\bash.exe` を先に、無ければ Program Files・Program Files (x86)・`%LOCALAPPDATA%\Programs` の `Git` の順に探す。`windows/bin` のラッパーと install.ps1 が使う。見つからなければ「bash.exe が見つからない」で終了コード 1
- `windows/install-lib.ps1`: install.ps1 とテストが dot-source する関数（リンク、ユーザー環境変数と Path、ssh の権限、改行の検査と書き直し、Codex の config.toml の生成、Windows Terminal の settings.json の更新）
- `windows/.gitattributes`: `windows/` は LF で取り出す（Git Bash で動かすため）。`.cmd` だけ CRLF
- `windows/powershell/profile.ps1`: pwsh のプロファイル（CurrentUserAllHosts。`shell/zshenv`・`zprofile`・`zshrc` の移植）。前半は毎回読む環境（EDITOR・VISUAL、PATH の先頭に `~/.local/bin`・mise の shims・あれば `~/.cargo/bin`。重複を畳む）でプロセスを起動しない。PSReadLine が無い（非対話）ならそこで終わる。後半は UTF-8、vi モード（モードでカーソルの形を変える）、履歴（50000 行、重複なし、空白で始まる行は残さない）、履歴からの候補、Tab で一覧、starship → mise activate（続けて、cd と prompt の hook を包んで PATH から mise の Node の install のディレクトリを外す）→ PSFzf（Ctrl+t・Ctrl+r・Alt+c）、`ll`・`la`・`lt`・`lg`・`lzd`・`cw`。`ls`・`cat` は置き換えない
- `windows/claude/settings.json`: Claude Code の設定（`config/claude/settings.json` の Windows 版）。違いは、PowerShell ツール用の allow・deny（Bash の規則は PowerShell ツールに効かない）、`env` の `CLAUDE_CODE_USE_POWERSHELL_TOOL`（Git Bash の場所は書かない。Claude Code が PATH の git から見つける。Git が標準の場所に無く見つからないときは、ユーザー環境変数に `CLAUDE_CODE_GIT_BASH_PATH`（`bash.exe` のパス）を設定する）、`agent-status`・`claude-env` のフックが無い（`hook env` が mise の shims も置く）、bin のフックは `windows/posix/hook` 経由（ホームに空白があっても分かれないよう、`"$HOME/dotfiles/windows/posix/hook"` のように実行ファイルのパスを引用符で囲む。ステータスラインのパスも同じ）、SessionStart の先頭に `hook env`、ステータスラインは `statusline.ps1`、通知は端末のベル（`preferredNotifChannel`）。ほかは共通の設定と同じ
- `windows/claude/statusline.ps1`: `config/claude/statusline.sh` の PowerShell 版（出力・アイコン・メーター・コンテキストのキャッシュ・Codex の上限・herdr の pane の名前は同じ。jq・awk を使わない）
- `windows/claude/CLAUDE.md`: `config/agents/AGENTS.md` を読み込み、Windows の違いを足す（スクリーンショットは `~/Pictures/Screenshots`、dotfiles のコマンドは Bash ツールで）
- `windows/posix/run`: Git Bash で `bin/<名前>` を動かす。PATH の先頭に jq の shim と dotfiles の `bin` を置き、`/clear` を Windows のパスに直させない（`MSYS2_ARG_CONV_EXCL`。handoff が herdr に送る）
- `windows/posix/hook`: Claude Code のフック（Git Bash で動く）。`hook env` は `CLAUDE_ENV_FILE` に PATH（dotfiles の shims・bin と mise の shims。mise の shims は後ろ）と `/clear` の除外の行を足す（Bash ツール用）。`hook integrate-hook` は入力の `cwd`・`file_path`・`notebook_path` を `cygpath -u` で `/c/...` にしてから渡す。ほかは `bin/<名前>` をそのまま
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

- `config/codex/config.toml.tmpl`: `~/.codex/config.toml` を生成する（下の「install.ps1 がやること」の 9）
- `bin/` のコマンドとフック: `windows/posix/run`・`hook` が Git Bash で動かす
- `config/git/hooks-nosign/commit-msg`: `windows/git/hooks-nosign/commit-msg` が呼ぶ
- `bin/geoview`: `windows/geoview` の `geoview.exe` が動かす

## install.ps1 がやること（順に）

1. シンボリックリンクを作れるか試す（作れなければ開発者モードを案内して終了コード 1。その場で止まるのはこれだけ）
2. 上のリンクを作る（同じ先を指すリンクなら何もしない。ほかに何かあれば `*.bak.<日時>` に退避）。`~/.claude/.ponytail-band` が無ければ `off` を書く。`-LinksOnly` はここで終わる（失敗があれば 3 と同じく一覧と終了コード 1）
3. 2 からは失敗しても `warning:` を出して続け、最後に失敗した手順の名前と理由の一覧を出して終了コード 1 で終わる（`done.` は出さない）
4. git: このクローンの `core.autocrlf=input`。CRLF で取り出された LF のファイル（`.cmd` は除く）があり、作業ツリーに変更が無ければ LF で取り出し直す
5. `~/.gitconfig` が無ければ空で作る（`git config --global` の書き込み先。中身は消さない）
6. ssh: `ssh/config` に自分・SYSTEM・Administrators 以外が書き込めれば icacls で絞る。`ssh -G` を確かめる
7. ユーザー環境変数（HKCU\Environment）: `EDITOR`・`VISUAL`=nvim、`YAZI_FILE_ONE`（Git の `usr\bin\file.exe`。Git の場所は gitbash-lib で探す）。Path の先頭に `~/.local/bin`・mise の shims・`windows/bin`（`%USERPROFILE%`・`%LOCALAPPDATA%` のままの REG_EXPAND_SZ）。`HOME`・`XDG_CONFIG_HOME` は入れない
8. mise（`~/.local/bin/mise.exe`、install.sh と同じ版。違う版が入っていれば `mise self-update` でその版にする）と、`config/mise/mise.lock` を `~/.config/mise/mise.lock` に写して `mise install --locked`（lock の版だけを入れ、配布物を lock の checksum で確かめる。Node の LTS を含む。ホームで。`gh auth token` をこのプロセスだけの `GITHUB_TOKEN` にする）
9. Codex: テンプレートから `~/.codex/config.toml` を作る（`@HOME@` は `/` 区切りのホーム。既存の設定のうち、テンプレートにあるキーはテンプレートの値にし、ほかのトップレベルのキーと表（Codex デスクトップが書く `notify`・`[desktop]`・プラグインなど）は値ごと引き継ぐ。キーと表の名前は引用符やドットの前後の空白を除いて比べ、それでも同じキーが 2 回になるなら書かずに失敗する。値の外のコメントと空行は引き継がない。違うときだけ退避して書く）。codex が無ければ公式のインストーラーで入れ、ユーザーの Path を手順 7 の形に戻す。ponytail の marketplace と plugin を入れる。tinymemory があれば `tinymemory init codex`
10. Neovim のプラグインを `lazy-lock.json` に揃える（`Lazy! restore`。mise の nvim が無ければ失敗）
11. PSFzf（PSGallery）
12. geoview（`uv tool install`。uv が無ければ失敗）
13. Windows Terminal の settings.json: profiles.defaults に配色・Hack Nerd Font Mono 12・余白・履歴 50000、PowerShell 7 のプロファイルを既定にする（変わるときだけ退避して書く。ほかのキーとプロファイルはそのまま）。settings.json が無い、または PowerShell 7 のプロファイルが無ければ失敗（ほかは書く。Windows Terminal を開き直してから再実行）
14. 全部成功なら `done.` と README の残りの手順の案内を出して終了コード 0

## 制限

- tmux は無い（Windows 版が無い）。herdr を使う。`agent-status`（tmux の状態表示）は tmux だけなので使わない
- Windows Terminal は OSC 777 のデスクトップ通知を出さない。Claude Code の通知は端末のベル
- herdr の中の yazi は画像を表示しない（kitty の画像を切っている）
- Windows で入れない道具は `config/mise/config.toml` の `os` で決める（tmux）。前の install.ps1 が入れたユーザー環境変数 `MISE_DISABLE_TOOLS` は要らない（残っても害は無い。消すなら `[Environment]::SetEnvironmentVariable('MISE_DISABLE_TOOLS', $null, 'User')`）
- Codex のサンドボックスは MSIX 版（Microsoft Store 版）の pwsh を動かせず、サンドボックスの中のコマンドは Windows PowerShell 5.1 になる（手順 2 は MSI 版を入れる）
- nvim-treesitter は `cc` という名前の実行ファイルが PATH に無いと読み込まない。Windows には無い（Build Tools のコンパイラは `cl.exe`）ので使わない
- `windows/bin/*.cmd` を cmd.exe から呼ぶと `"`・`^`・`&`・`|` を含む引数が壊れる（pwsh からは `.ps1` が選ばれるので壊れない）
- Claude Code の PowerShell ツールはプロファイルを読まず、claude を起動した pwsh の PATH を受け継ぐ。mise activate は node などの install のディレクトリを shims より前に置くので、そのままだと node が起動した場所の版に固定される。プロファイルは cd と prompt のたびに PATH から mise の Node の install のディレクトリだけを外すので、node・npm・npx・corepack は PATH の shims が呼ばれた場所の版で動く（ほかの道具は install のディレクトリから直接起動するので、`mise.toml` が壊れた場所でも動く。`mise.toml` の `[env]` は mise activate が設定する）。Bash ツールは `hook env` が同じことをする。引き換えに、対話の pwsh とそこから起動したもので node・npm・npx・corepack だけが shims を通り、1 回あたり約 70 ms 遅くなる（この PC の計測）。呼ばれた場所の版（`.node-version` など）を使うため。`npm i -g` で入れた CLI は Node の install のディレクトリに入り PATH から外れるので、`mise reshim` で shims に入れる
- 上の処理が外すのは `$env:LOCALAPPDATA\mise\installs\node\` の下だけ。`mise.toml` の `node = { path = '…' }` のように install の外を指す Node は外さないので、そこから起動した子（PowerShell ツールなど）は起動した場所の版のまま（この処理の前と同じ）。`mise exec` が受け継がせた install の Node は外れ、手で PATH に足した Node のディレクトリは残る

## 検査

```powershell
pwsh -NoProfile -File windows/tests/run.ps1
```

Pester 5 が要る（無ければ `Install-PSResource Pester -Scope CurrentUser`）。ネットワークを使わず、本物のホームとレジストリに触らない（install.ps1 は一時ホームに `-LinksOnly`）。Git Bash が無ければ Git Bash の検査を、jq.exe が無ければ jq の検査を飛ばす。

- `syntax.Tests.ps1`: .ps1 の構文・BOM・`#Requires -Version 7.4`（`Select-Object -CaseInsensitive` が 7.4 から）、JSON、文字コードと改行、シェルスクリプトの構文
- `policy.Tests.ps1`: リポジトリの禁止の文字列・ファイル名、既存の追跡しているファイルを変えていない
- `install.Tests.ps1`: リンク・退避・2 回目は何もしない・worktree の拒否・band、install-lib.ps1 の関数（手順の失敗の一覧と終了コードを含む）、install.ps1 の手順の書き方（構文木）
- `claude.Tests.ps1`: settings.json と共通の設定の違い、statusline.ps1 の出力とキャッシュ
- `profile.Tests.ps1`: profile.ps1 が mise activate の後に包む cd・prompt の hook（偽の mise の hook が Node と ripgrep の install を PATH の先頭に置き、プロファイルの関数を読ませる）。mise の hook が先に走り、その後に Node の install だけが PATH から消え、ripgrep の install・shims・ほかの順と prompt の戻り値・`$?` が保たれる。mise があるときだけ、activate の後に呼ぶ（構文木）
- `posix.Tests.ps1`: `hook env`、jq の shim、commit-msg、integrate-hook、`/clear`、`windows/bin` の shim
- `gitbash.Tests.ps1`: gitbash-lib.ps1（偽の Git のルートを PATH に置いて、`git.exe` の 4 つの置き場所と標準の場所の順を確かめる）、`windows/bin` のラッパー（偽の `bash.exe` を PATH の `git.exe` の隣に置く。空白を含むパスの dotfiles と、Program Files の外の Git への junction）、settings.json のフックとステータスラインを HOME に空白を含めて `bash -c` で動かす
- `herdr.Tests.ps1`: herdr の設定と共通のファイルの違い

## fnm から移る（前に入れた PC で一度）

Node は mise に移した（mac / linux と同じ。決め方は `config/mise/README.md`）。前に install.ps1 を実行した PC で:

```powershell
pwsh -File $HOME\dotfiles\windows\install.ps1       # mise install が Node を入れる
[Environment]::SetEnvironmentVariable('FNM_DIR', $null, 'User')
mise uninstall --all aqua:Schniz/fnm
Remove-Item -Recurse -Force $HOME\.local\share\fnm
```

- ユーザーの Path に残る fnm の項目は mise の shims より後ろになるので害は無い（消すならシステムの環境変数の画面で）。ターミナルと Claude Code は開き直す
- fnm の Node に `npm i -g` で入れたものは入れ直す。Windows では mise が shims を作り直さないので、入れた後に `mise reshim`
