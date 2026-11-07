#Requires -Version 7.4
# dotfiles セットアップ（ネイティブ Windows。管理者は不要、シンボリックリンクに開発者モードが要る。何度実行しても安全）
#   pwsh -File windows/install.ps1 [-LinksOnly] [-HomeDir <path>]
# -LinksOnly: リンクと ponytail の band だけ作って終わる（windows/tests が一時ホームで使う）
# -HomeDir:   配置先のホーム（既定は %USERPROFILE%）。違うホームを渡すと AppData・Documents もその下にする
[CmdletBinding()]
param(
  [switch]$LinksOnly,
  [string]$HomeDir = $env:USERPROFILE
)
$ErrorActionPreference = 'Stop'
# コードページ 932 の端末でも日本語と UTF-8 の出力が化けないように
try { [Console]::InputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
$OutputEncoding = [Text.UTF8Encoding]::new($false)

# mise 本体の版（install.sh の MISE_VERSION と一緒に上げる）
$MiseVersion = 'v2026.10.1'
# Windows で mise に入れない道具: tmux は Windows 版が無い。tinymemory は Windows 版のリリースが出るまで
$MiseDisable = 'aqua:tmux/tmux-builds,github:arkrtm/tinymemory'

$DOTFILES = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
. (Join-Path $PSScriptRoot 'install-lib.ps1')
. (Join-Path $PSScriptRoot 'gitbash-lib.ps1')

# worktree（.git がファイル）から実行すると、リンクが worktree を指し、worktree を消すと設定が読めなくなる
if ((Test-Path -LiteralPath (Join-Path $DOTFILES '.git') -PathType Leaf) -and -not $env:DOTFILES_ALLOW_WORKTREE) {
  [Console]::Error.WriteLine('install.ps1: worktree からは実行しない（元のチェックアウトで実行する）')
  exit 1
}

$HomeDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HomeDir).TrimEnd('\')
$testHome = $HomeDir -ine [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
if ($testHome) {
  # 一時ホームでの検査用。レジストリ（ユーザー環境変数）や道具の導入は本物のホームに効くので、リンクだけに限る
  if (-not $LinksOnly) {
    [Console]::Error.WriteLine('install.ps1: -HomeDir に別のホームを渡すときは -LinksOnly と一緒に使う')
    exit 1
  }
  $LocalAppData = Join-Path $HomeDir 'AppData\Local'
  $AppData = Join-Path $HomeDir 'AppData\Roaming'
  $Documents = Join-Path $HomeDir 'Documents'
} else {
  $LocalAppData = $env:LOCALAPPDATA
  $AppData = $env:APPDATA
  $Documents = [Environment]::GetFolderPath('MyDocuments')
}

if (-not (Test-SymlinkSupport)) {
  [Console]::Error.WriteLine('install.ps1: シンボリックリンクを作れない。開発者モードをオンにする（設定 → システム → 開発者向け）')
  exit 1
}

# リンクから先は失敗しても続け、最後に失敗した手順の一覧を出して終了コード 1 にする（その場で止まるのは前提の検査だけ）
$StepLog = [Collections.Generic.List[object]]::new()

# リンク定義: リポジトリ内パス → 配置先。Dir はリンク元がまだ無くてもディレクトリのリンクにする印
$H = $HomeDir
$Links = @(
  @{ Src = 'config/git/config'; Dst = "$H\.config\git\config" }
  @{ Src = 'config/git/ignore'; Dst = "$H\.config\git\ignore" }
  @{ Src = 'windows/git/hooks-nosign'; Dst = "$H\.config\git\hooks-nosign"; Dir = $true }
  @{ Src = 'config/mise/config.toml'; Dst = "$H\.config\mise\config.toml" }
  @{ Src = 'config/starship.toml'; Dst = "$H\.config\starship.toml" }
  @{ Src = 'config/bat/config'; Dst = "$AppData\bat\config" }
  @{ Src = 'config/nvim'; Dst = "$LocalAppData\nvim"; Dir = $true }
  @{ Src = 'config/yazi'; Dst = "$AppData\yazi\config"; Dir = $true }
  @{ Src = 'windows/herdr/config.toml'; Dst = "$AppData\herdr\config.toml" }
  @{ Src = 'windows/claude/settings.json'; Dst = "$H\.claude\settings.json" }
  @{ Src = 'windows/claude/CLAUDE.md'; Dst = "$H\.claude\CLAUDE.md" }
  @{ Src = 'config/agents/AGENTS.md'; Dst = "$H\.codex\AGENTS.md" }
  @{ Src = 'config/agents/skills/issue'; Dst = "$H\.claude\skills\issue"; Dir = $true }
  @{ Src = 'config/agents/skills/wrap-up'; Dst = "$H\.claude\skills\wrap-up"; Dir = $true }
  @{ Src = 'config/agents/skills/handoff'; Dst = "$H\.claude\skills\handoff"; Dir = $true }
  @{ Src = 'config/agents/skills/issue'; Dst = "$H\.agents\skills\issue"; Dir = $true }
  @{ Src = 'config/agents/skills/wrap-up'; Dst = "$H\.agents\skills\wrap-up"; Dir = $true }
  @{ Src = 'ssh/config'; Dst = "$H\.ssh\config" }
  # CurrentUserAllHosts（pwsh のどのホストでも読む）
  @{ Src = 'windows/powershell/profile.ps1'; Dst = "$Documents\PowerShell\profile.ps1" }
  @{ Src = 'windows/terminal/dotfiles.json'; Dst = "$LocalAppData\Microsoft\Windows Terminal\Fragments\dotfiles\dotfiles.json" }
)
foreach ($l in $Links) {
  $src = Join-Path $DOTFILES ($l.Src -replace '/', '\')
  Invoke-Step $StepLog "リンク $($l.Dst)" { Link-Item -Source $src -Destination $l.Dst -Directory:([bool]$l.Dir) }
}

# ponytail の band（プロンプトの上の行）を既定で隠す（install.sh と同じ）。ファイルがあれば触らない
Invoke-Step $StepLog 'ponytail の band' {
  $band = Join-Path $H '.claude\.ponytail-band'
  if (-not (Get-PathEntry $band)) { [IO.File]::WriteAllText($band, "off`n", [Text.UTF8Encoding]::new($false)) }
}

# リンク配置だけを検査したい時（windows/tests）はここで終わる（失敗があれば一覧と終了コード 1）
if ($LinksOnly) { exit (Complete-Install $StepLog) }

# 取得してから実行する（パイプで渡さない。取得に失敗したら実行しない）
function Get-RemoteScript {
  param([Parameter(Mandatory)][string]$Uri)
  $s = Invoke-RestMethod -Uri $Uri
  if ($s -is [byte[]]) { $s = [Text.Encoding]::UTF8.GetString($s) }
  [string]$s
}
function Test-Command { param([string]$Name) [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue) }

Update-ProcessPath

# 1. 改行: このクローンは LF で取り出す（シェルスクリプトを Git Bash で動かすため）。CRLF で取り出し済みなら、変更が無いときだけ取り出し直す
Invoke-Step $StepLog 'git の改行' {
  git -C $DOTFILES config --local core.autocrlf input
  if ($LASTEXITCODE) { throw 'git config に失敗' }
  $crlf = Get-CrlfCheckout $DOTFILES
  if ($crlf.Count -eq 0) { return }
  if (git -C $DOTFILES status --porcelain --untracked-files=all) {
    throw 'CRLF で取り出されたファイルがあるが、作業ツリーに変更があるので取り出し直さない（片づけてから再実行する）'
  }
  foreach ($f in $crlf) { Remove-Item -LiteralPath (Join-Path $DOTFILES $f) -Force }
  git -C $DOTFILES checkout -- .
  if ($LASTEXITCODE) { throw 'git checkout に失敗' }
  Write-Host "LF で取り出し直した: $($crlf.Count) 個"
}

# 2. git config --global の書き込み先を端末ローカルの ~/.gitconfig にする（無いと ~/.config/git/config = リポジトリ側が書き換わる）。中身は消さない
Invoke-Step $StepLog '~/.gitconfig' {
  $gc = Join-Path $H '.gitconfig'
  if (-not (Get-PathEntry $gc)) { [IO.File]::WriteAllBytes($gc, [byte[]]@()) }
}

# 3. ssh は設定ファイルが他人に書き込めると拒否するので、リンク先の実ファイルの権限を自分・SYSTEM・Administrators に絞る
Invoke-Step $StepLog 'ssh' {
  $sshDir = Join-Path $H '.ssh'
  if (-not (Test-Path -LiteralPath $sshDir)) { $null = New-Item -ItemType Directory -Path $sshDir }
  $conf = Join-Path $DOTFILES 'ssh\config'
  if (Get-UnsafeWriter $conf) {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    icacls $conf /inheritance:r /grant:r "*${me}:(F)" '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
    foreach ($sid in Get-UnsafeWriter $conf) { icacls $conf /remove:g "*$sid" | Out-Null }
    if (Get-UnsafeWriter $conf) { throw "$conf の権限を絞れなかった" }
    Write-Host "ssh/config の権限を絞った"
  }
  $ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
  if (-not (Test-Path -LiteralPath $ssh)) { $ssh = 'ssh' }
  & $ssh -G example.invalid *> $null
  if ($LASTEXITCODE) { throw 'ssh -G が失敗する（~/.ssh/config を確かめる）' }
}

# 4. ユーザー環境変数（HKCU\Environment）。HOME と XDG_CONFIG_HOME は入れない（Windows の道具が既定の場所を外れるため）
# ユーザーの Path の先頭に置くもの（この順）
$UserPathDirs = @('%USERPROFILE%\.local\share\fnm\aliases\default', '%USERPROFILE%\.local\bin', '%LOCALAPPDATA%\mise\shims', (ConvertTo-EnvRelativePath (Join-Path $DOTFILES 'windows\bin')))
Invoke-Step $StepLog 'ユーザー環境変数' {
  $null = Set-UserEnv EDITOR nvim
  $null = Set-UserEnv VISUAL nvim
  $null = Set-UserEnv FNM_DIR '%USERPROFILE%\.local\share\fnm'
  $null = Set-UserEnv MISE_DISABLE_TOOLS $MiseDisable
  # yazi のファイル種別の判定に Git の file.exe を使う（Git の場所は git.exe から探す。Program Files とは限らない）
  $gitRoot = Get-GitRoot
  $file = if ($gitRoot) { Join-Path $gitRoot 'usr\bin\file.exe' }
  if ($file -and (Test-Path -LiteralPath $file)) { $null = Set-UserEnv YAZI_FILE_ONE $file }
  $null = Add-UserPath @UserPathDirs
}

# ここから先の mise・fnm・uv は、呼んだ場所の設定（mise.toml、.python-version など）に左右されないようホームで実行する
$mise = Join-Path $H '.local\bin\mise.exe'

# 5. mise 本体（~/.local/bin/mise.exe）と道具。インストーラは版を固定すると配布物をその release の SHASUMS256.txt で検証する
Invoke-Step $StepLog 'mise' {
  if (-not (Test-Path -LiteralPath $mise)) {
    $s = Get-RemoteScript 'https://mise.run/powershell'
    $env:MISE_VERSION = $MiseVersion
    # Path は上の Add-UserPath で入れてある
    $env:MISE_INSTALL_MODIFY_PATH = '0'
    try { & ([scriptblock]::Create($s)) } finally { Remove-Item env:MISE_VERSION, env:MISE_INSTALL_MODIFY_PATH -ErrorAction SilentlyContinue }
    if (-not (Test-Path -LiteralPath $mise)) { throw "$mise が入らなかった" }
  }
}
if (Test-Path -LiteralPath $mise) {
  # GitHub API の回数制限を避ける（gh の token は資格情報ストアにあり、mise は読めない）。このプロセスだけに入れ、保存しない
  if (-not $env:GITHUB_TOKEN -and (Test-Command gh)) {
    $tok = gh auth token 2>$null
    if (-not $LASTEXITCODE -and $tok) { $env:GITHUB_TOKEN = "$tok".Trim() }
  }
  Invoke-Step $StepLog 'mise install' {
    Push-Location $H
    try {
      & $mise install --yes
      if ($LASTEXITCODE) { throw "mise install が失敗した（Windows 版の無い道具は MISE_DISABLE_TOOLS に足す）" }
    } finally { Pop-Location }
  }

  # 6. Node は fnm で最新の LTS を入れて既定にする（再実行のたびに最新の LTS に追随する）
  Invoke-Step $StepLog 'fnm' {
    Push-Location $H
    try {
      & $mise exec -- fnm install --lts
      if ($LASTEXITCODE) { throw 'fnm install --lts が失敗した' }
      & $mise exec -- fnm default lts-latest
      if ($LASTEXITCODE) { throw 'fnm default が失敗した' }
    } finally { Pop-Location }
  }
}

# 7. Codex: config.toml はリンクせずテンプレートから生成する（writable_roots にホームの絶対パスが要るため）
Invoke-Step $StepLog 'Codex の設定' {
  $null = New-CodexConfig -Template (Join-Path $DOTFILES 'config\codex\config.toml.tmpl') -ConfigPath (Join-Path $H '.codex\config.toml') -HomeDir $H
}
Invoke-Step $StepLog 'Codex' {
  # 公式のインストーラー。入っていれば何もしない。失敗しても止めず、Codex の後続だけ飛ばす
  if (-not (Test-Command codex)) {
    try {
      $s = Get-RemoteScript 'https://chatgpt.com/codex/install.ps1'
      $env:CODEX_NON_INTERACTIVE = '1'
      try { & ([scriptblock]::Create($s)) } finally { Remove-Item env:CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue }
    } catch {
      Add-StepFailure $StepLog 'Codex' "入れられなかった（install.ps1 の再実行で入れ直す）: $($_.Exception.Message)"
    }
    # Codex のインストーラーはユーザーの Path を展開した形の REG_SZ で書き戻すので、手順 4 の項目を %...% の形と REG_EXPAND_SZ に戻す
    try { $null = Add-UserPath @UserPathDirs } catch { Add-StepFailure $StepLog 'Codex' "ユーザーの Path を戻せなかった: $($_.Exception.Message)" }
    Update-ProcessPath
  }
  if (Test-Command codex) {
    # ponytail は宣言だけでは入らない（ログインは要らない）
    codex plugin marketplace add DietrichGebert/ponytail *> $null
    if (-not $LASTEXITCODE) { codex plugin add ponytail@ponytail *> $null }
    if ($LASTEXITCODE) { Add-StepFailure $StepLog 'Codex' 'ponytail を入れられなかった' }
  } else {
    Add-StepFailure $StepLog 'Codex' 'codex が見つからない（install.ps1 の再実行で入れ直す）'
  }
  # tinymemory の Codex の hook と skill（Windows 版が出るまでは入っていないので飛ばす）。tinymemory は HOME を見る
  if (Test-Command tinymemory) {
    $oldHome = $env:HOME
    $env:HOME = $H
    try {
      tinymemory init codex *> $null
      if ($LASTEXITCODE) { Add-StepFailure $StepLog 'Codex' 'tinymemory init codex が失敗した' }
    } finally { $env:HOME = $oldHome }
  }
}

# 8. Neovim プラグインを lazy-lock.json の版に揃える（mise exec で tree-sitter も PATH に載せる）
Invoke-Step $StepLog 'nvim' {
  if (-not (Test-Path -LiteralPath $mise)) { throw 'mise が無い（mise の手順を直して再実行する）' }
  & $mise which nvim *> $null
  if ($LASTEXITCODE) { throw 'mise の nvim が無い（mise install を直して再実行する）' }
  & $mise exec -- nvim --headless '+Lazy! restore' +qa *> $null
  if ($LASTEXITCODE) { throw 'プラグインの restore に失敗した' }
}

# 9. PSFzf（fzf の Ctrl+t・Ctrl+r・Alt+c を PSReadLine に付ける）
Invoke-Step $StepLog 'PSFzf' {
  if (Get-Module -ListAvailable PSFzf) { return }
  try { Install-PSResource -Name PSFzf -Scope CurrentUser -TrustRepository -ErrorAction Stop }
  catch { Install-Module PSFzf -Scope CurrentUser -Force -ErrorAction Stop }
}

# 10. geoview（bin/geoview を Windows で動かす uv の tool。~/.local/bin/geoview.exe）
Invoke-Step $StepLog 'geoview' {
  if (-not (Test-Command uv)) { throw 'uv が無い（mise install を直して再実行する）' }
  Push-Location $H
  try {
    uv tool install --force (Join-Path $DOTFILES 'windows\geoview')
    if ($LASTEXITCODE) { throw 'uv tool install が失敗した' }
  } finally { Pop-Location }
}

# 11. Windows Terminal: 配色・フォント・余白・履歴を profiles.defaults に、既定のプロファイルを PowerShell 7 にする
Invoke-Step $StepLog 'Windows Terminal' {
  $wt = Join-Path $LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
  if (-not (Test-Path -LiteralPath $wt)) { throw "settings.json が無い（Windows Terminal を一度起動してから再実行する）: $wt" }
  $null = Update-TerminalSettings $wt
}

exit (Complete-Install $StepLog)
