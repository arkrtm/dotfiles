#Requires -Version 7.4
# Git Bash の場所と、空白を含むホーム: gitbash-lib.ps1 は git.exe の場所（cmd\git.exe・bin\git.exe・mingw64\bin\git.exe・ucrt64\bin\git.exe）から Git のルートを見つけ、
# 無ければ標準の場所（Program Files・Program Files (x86)・%LOCALAPPDATA%\Programs）を探す。windows/bin の *.ps1・*.cmd は標準の場所に無い Git でも動き、
# settings.json のフックとステータスラインは空白を含むホームでも動く（Git Bash が無ければ後半を飛ばす）

BeforeDiscovery {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  . (Join-Path $Root 'windows\gitbash-lib.ps1')
  $NoBash = -not (Get-GitBash)
  $Csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  $NoCsc = -not (Test-Path -LiteralPath $Csc)
  # Program Files に Git があると、PATH に git.exe が無いときの標準の場所の検査はそちらが先に見つかる（ProgramFiles は子プロセスで書き換えられない）
  $StdGit = Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
  $WinSettings = [IO.File]::ReadAllText((Join-Path $Root 'windows\claude\settings.json'), [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json -Depth 50
  $Hooks = @($WinSettings.hooks.PSObject.Properties.Value | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command } |
      Where-Object { $_ -match 'dotfiles/' } | ForEach-Object { @{ Command = $_ } })
  $Layouts = @('cmd', 'bin', 'mingw64\bin', 'ucrt64\bin') | ForEach-Object { @{ Dir = $_ } }
  $Wrappers = @('agent-pane', 'codex-review', 'handoff', 'integrate', 'notify') | ForEach-Object { @{ Name = $_ } }
}

BeforeAll {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  . (Join-Path $Root 'windows\gitbash-lib.ps1')
  $Utf8 = [Text.UTF8Encoding]::new($false)
  $Pwsh = (Get-Command pwsh -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
  if (-not $Pwsh) { $Pwsh = [Environment]::ProcessPath }
  function Invoke-Proc {
    param([string]$FilePath, [string[]]$Arguments = @(), [string]$InputText = '', [hashtable]$Environment = @{}, [string]$WorkingDirectory)
    $psi = [Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $psi.RedirectStandardOutput = $psi.RedirectStandardError = $true
    $psi.StandardInputEncoding = $psi.StandardOutputEncoding = $psi.StandardErrorEncoding = $Utf8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($k in $Environment.Keys) {
      if ($null -eq $Environment[$k]) { [void]$psi.Environment.Remove($k) } else { $psi.Environment[$k] = [string]$Environment[$k] }
    }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $p.StandardInput.Write($InputText); $p.StandardInput.Close()
    if (-not $p.WaitForExit(120000)) { $p.Kill($true); throw "時間切れ: $FilePath $Arguments" }
    $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $o.Result; Err = $e.Result }
  }
  # シンボリックリンク・ジャンクションを辿らずに消す（リンク先の本物の Git を消さないよう、リンクはリンクだけ消してから木を消す）
  function Remove-TreeSafe([string]$Path) {
    if (-not [IO.Directory]::Exists($Path)) { return }
    foreach ($e in [IO.Directory]::GetFileSystemEntries($Path)) {
      $a = [IO.File]::GetAttributes($e)
      if ($a.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        if ($a.HasFlag([IO.FileAttributes]::Directory)) { [IO.Directory]::Delete($e, $false) } else { [IO.File]::Delete($e) }
      } elseif ($a.HasFlag([IO.FileAttributes]::Directory)) {
        Remove-TreeSafe $e
      } else {
        [IO.File]::SetAttributes($e, [IO.FileAttributes]::Normal); [IO.File]::Delete($e)
      }
    }
    [IO.Directory]::Delete($Path, $false)
  }
  # 環境変数を一時的に差し替えて $Body を動かす（$null は消す）
  function Use-Env([hashtable]$Vars, [scriptblock]$Body) {
    $saved = @{}
    foreach ($k in $Vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
    try { & $Body } finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
  }
  # 後ろの値で上書きして 2 つの環境を合わせる
  function Merge-Env([hashtable]$Base, [hashtable]$Over) { $m = $Base.Clone(); foreach ($k in $Over.Keys) { $m[$k] = $Over[$k] }; $m }
  function New-EmptyFile([string]$Path) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllBytes($Path, [byte[]]@())
  }
  $Tmp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-gitbash-test-' + [guid]::NewGuid().ToString('N'))
  $null = New-Item -ItemType Directory -Path $Tmp
  # 標準の場所が空の環境（Program Files などをここに向ける）
  $Empty = Join-Path $Tmp 'empty'
  $null = New-Item -ItemType Directory -Path $Empty
  $System32 = Join-Path $env:SystemRoot 'System32'
  $Isolated = @{ ProgramFiles = $Empty; 'ProgramFiles(x86)' = $Empty; LOCALAPPDATA = $Empty }
}

AfterAll {
  if ($Tmp) { Remove-TreeSafe $Tmp }
}

Describe 'gitbash-lib.cmd' {
  It 'git.exe が <Dir>\git.exe にある Git のルートの bin\bash.exe を GITBASH にする' -ForEach $Layouts {
    $gitRoot = Join-Path $Tmp ("cmdlib-$($Dir -replace '\\', '_')\Programs\Git")
    New-EmptyFile (Join-Path $gitRoot "$Dir\git.exe")
    New-EmptyFile (Join-Path $gitRoot 'bin\bash.exe')
    $probe = Join-Path $Tmp "probe-$($Dir -replace '\\', '_').cmd"
    [IO.File]::WriteAllText($probe, "@echo off`r`ncall `"$(Join-Path $Root 'windows\gitbash-lib.cmd')`"`r`necho GITBASH=%GITBASH%`r`nexit /b %ERRORLEVEL%`r`n")
    $r = Invoke-Proc (Join-Path $System32 'cmd.exe') @('/d', '/c', $probe) -Environment ($Isolated + @{ Path = "$(Join-Path $gitRoot $Dir);$System32" }) -WorkingDirectory $Tmp
    $r.ExitCode | Should -Be 0 -Because $r.Err
    $r.Out.Trim() | Should -Be "GITBASH=$(Join-Path $gitRoot 'bin\bash.exe')"
  }
}

Describe 'gitbash-lib.ps1' {
  It 'git.exe が <Dir>\git.exe にある Git のルートの bin\bash.exe を返す' -ForEach $Layouts {
    $gitRoot = Join-Path $Tmp ("peruser-$($Dir -replace '\\', '_')\Programs\Git")
    New-EmptyFile (Join-Path $gitRoot "$Dir\git.exe")
    New-EmptyFile (Join-Path $gitRoot 'bin\bash.exe')
    Use-Env ($Isolated + @{ Path = "$(Join-Path $gitRoot $Dir);$System32" }) {
      Get-GitRoot | Should -BeExactly $gitRoot
      Get-GitBash | Should -BeExactly (Join-Path $gitRoot 'bin\bash.exe')
    }
  }
  It 'PATH の git.exe を、標準の場所の Git より先に選ぶ' {
    $gitRoot = Join-Path $Tmp 'first\Git'
    $std = Join-Path $Tmp 'std'
    New-EmptyFile (Join-Path $gitRoot 'cmd\git.exe'); New-EmptyFile (Join-Path $gitRoot 'bin\bash.exe')
    New-EmptyFile (Join-Path $std 'Git\bin\bash.exe')
    Use-Env @{ ProgramFiles = $std; 'ProgramFiles(x86)' = $Empty; LOCALAPPDATA = $Empty; Path = "$(Join-Path $gitRoot 'cmd');$System32" } {
      Get-GitRoot | Should -BeExactly $gitRoot
    }
  }
  It 'PATH に git.exe が無ければ標準の場所（<Where>）を探す' -ForEach @(
    @{ Where = 'Program Files'; Var = 'ProgramFiles'; Sub = 'Git' }
    @{ Where = 'Program Files (x86)'; Var = 'ProgramFiles(x86)'; Sub = 'Git' }
    @{ Where = '%LOCALAPPDATA%\Programs'; Var = 'LOCALAPPDATA'; Sub = 'Programs\Git' }
  ) {
    $base = Join-Path $Tmp "std-$([guid]::NewGuid().ToString('N'))"
    New-EmptyFile (Join-Path $base "$Sub\bin\bash.exe")
    Use-Env (Merge-Env $Isolated @{ $Var = $base; Path = $System32 }) {
      Get-GitRoot | Should -BeExactly (Join-Path $base $Sub)
    }
  }
  It 'git.exe の Git に bin\bash.exe が無ければ標準の場所へ進む' {
    $other = Join-Path $Tmp 'nobash\Git'
    New-EmptyFile (Join-Path $other 'cmd\git.exe')
    $base = Join-Path $Tmp "std-$([guid]::NewGuid().ToString('N'))"
    New-EmptyFile (Join-Path $base 'Git\bin\bash.exe')
    Use-Env (Merge-Env $Isolated @{ ProgramFiles = $base; Path = "$(Join-Path $other 'cmd');$System32" }) {
      Get-GitRoot | Should -BeExactly (Join-Path $base 'Git')
    }
  }
  It 'どこにも無ければ Get-GitRoot・Get-GitBash は $null、-Required は例外' {
    Use-Env ($Isolated + @{ Path = $System32 }) {
      Get-GitRoot | Should -BeNullOrEmpty
      Get-GitBash | Should -BeNullOrEmpty
      { Get-GitBash -Required } | Should -Throw '*bash.exe*'
    }
  }
}

Describe 'windows/bin のラッパーと posix のフックは、標準の場所に無い Git と空白を含むホームで動く' -Skip:$NoBash {
  BeforeAll {
    $Csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $NoCsc = -not (Test-Path -LiteralPath $Csc)
    $RealRoot = Get-GitRoot
    $RealGit = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
    $GitDirRel = [IO.Path]::GetRelativePath($RealRoot, (Split-Path -Parent $RealGit))
    # 本物の Git へのジャンクション（Program Files の外の、空白を含むパス）
    $Link = Join-Path $Tmp 'Per User\Programs\Git'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Link) -Force
    $null = New-Item -ItemType Junction -Path $Link -Target $RealRoot
    $WithGit = @{ Path = "$(Join-Path $Link $GitDirRel);$System32" }
    # 偽の Git: git.exe（空）と、呼ばれた印と受け取った引数を出して終了コード 7 を返す bash.exe（.NET Framework の csc.exe で作る）
    $Fake = Join-Path $Tmp 'Fake Git'
    New-EmptyFile (Join-Path $Fake 'cmd\git.exe')
    $null = New-Item -ItemType Directory -Path (Join-Path $Fake 'bin') -Force
    if (-not $NoCsc) {
      $src = Join-Path $Tmp 'fake-bash.cs'
      [IO.File]::WriteAllText($src, 'class P { static int Main(string[] a) { System.Console.Out.WriteLine("FAKE-BASH " + string.Join("|", a)); return 7; } }')
      $null = & $Csc /nologo /target:exe "/out:$(Join-Path $Fake 'bin\bash.exe')" $src
    }
    $WithFake = @{ Path = "$(Join-Path $Fake 'cmd');$System32" }

    # 空白を含むホームの下の dotfiles（リポジトリの windows/ と bin/ の写し）
    $SpHome = Join-Path $Tmp 'Jane Doe'
    $Dot = Join-Path $SpHome 'dotfiles'
    $null = New-Item -ItemType Directory -Path $Dot -Force
    Copy-Item -LiteralPath (Join-Path $Root 'windows'), (Join-Path $Root 'bin') -Destination $Dot -Recurse
    $State = Join-Path $SpHome 'state'
    $Cmd = Join-Path $System32 'cmd.exe'
  }

  Context 'windows/bin のラッパー' {
    It '<Name>.ps1 は PATH の git.exe の場所の bash.exe に posix/run と名前と引数を渡す' -Skip:$NoCsc -ForEach $Wrappers {
      $r = Invoke-Proc $Pwsh @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Dot "windows\bin\$Name.ps1"), 'hello') -Environment $WithFake -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 7 -Because $r.Err
      $r.Out | Should -Match ('FAKE-BASH .*posix.run\|' + $Name + '\|hello')
    }
    It '<Name>.cmd は PATH の git.exe の場所の bash.exe に posix/run と名前と引数を渡す' -Skip:$NoCsc -ForEach $Wrappers {
      $r = Invoke-Proc $Cmd @('/d', '/c', (Join-Path $Dot "windows\bin\$Name.cmd"), 'hello') -Environment $WithFake -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 7 -Because $r.Err
      $r.Out | Should -Match ('FAKE-BASH .*posix.run\|' + $Name + '\|hello')
    }
    It 'codex-review.ps1 は Program Files の外の Git と空白を含むパスで動く（引数なしなら usage と終了コード 2）' {
      $r = Invoke-Proc $Pwsh @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Dot 'windows\bin\codex-review.ps1')) -Environment $WithGit -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 2 -Because $r.Err
      $r.Err | Should -Match 'usage: codex-review'
    }
    It 'codex-review.cmd は Program Files の外の Git と空白を含むパスで動く（引数なしなら usage と終了コード 2）' {
      $r = Invoke-Proc $Cmd @('/d', '/c', (Join-Path $Dot 'windows\bin\codex-review.cmd')) -Environment $WithGit -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 2 -Because $r.Err
      $r.Err | Should -Match 'usage: codex-review'
    }
    It '.cmd は Git が見つからなければ 0 でない終了コードと bash.exe の名前を出す（Program Files に Git が無いとき）' -Skip:$StdGit {
      $r = Invoke-Proc $Cmd @('/d', '/c', (Join-Path $Dot 'windows\bin\codex-review.cmd')) -Environment (Merge-Env $Isolated @{ Path = $System32 }) -WorkingDirectory $Tmp
      $r.ExitCode | Should -Not -Be 0
      $r.Err | Should -Match 'bash\.exe'
    }
    It '.cmd は PATH に git.exe が無ければ %LOCALAPPDATA%\Programs\Git を探す（Program Files に Git が無いとき）' -Skip:($StdGit -or $NoCsc) {
      $la = Join-Path $Tmp 'LocalAppData'
      $null = New-Item -ItemType Directory -Path (Join-Path $la 'Programs\Git\bin') -Force
      Copy-Item -LiteralPath (Join-Path $Fake 'bin\bash.exe') -Destination (Join-Path $la 'Programs\Git\bin\bash.exe')
      $r = Invoke-Proc $Cmd @('/d', '/c', (Join-Path $Dot 'windows\bin\notify.cmd'), 'hello') -Environment (Merge-Env $Isolated @{ Path = $System32; LOCALAPPDATA = $la }) -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 7 -Because $r.Err
      $r.Out | Should -Match 'FAKE-BASH .*posix.run\|notify\|hello'
    }
    It '<Name>.cmd・<Name>.ps1 は Program Files の Git の固定パスを持たず、Git Bash を探す共通の部品を使う' -ForEach $Wrappers {
      $ps1 = [IO.File]::ReadAllText((Join-Path $Root "windows\bin\$Name.ps1"))
      $cmd = [IO.File]::ReadAllText((Join-Path $Root "windows\bin\$Name.cmd"))
      $ps1 + $cmd | Should -Not -Match 'Program ?Files'
      $ps1 | Should -Match 'Get-GitBash -Required'
      $cmd | Should -Match 'gitbash-lib\.cmd'
    }
  }

  Context 'settings.json のフックとステータスライン（bash -c で、HOME に空白を含む）' {
    BeforeAll {
      $Bash = Get-GitBash
      $StatusLine = ([IO.File]::ReadAllText((Join-Path $Root 'windows\claude\settings.json'), $Utf8) | ConvertFrom-Json -Depth 50).statusLine.command
      $EnvFile = Join-Path $SpHome 'claude-env'
      $HookEnv = @{ HOME = $SpHome; CLAUDE_ENV_FILE = $EnvFile; XDG_STATE_HOME = $State; HERDR_ENV = $null; HERDR_PANE_ID = $null; CODEX_HOME = (Join-Path $SpHome 'codex') }
      function Invoke-InBash([string]$Command, [hashtable]$ExtraEnv = @{}, [string]$InputText = '{"session_id":"x","hook_event_name":"x"}') {
        Invoke-Proc $Bash @('-c', $Command) -InputText $InputText -Environment ($HookEnv + $ExtraEnv) -WorkingDirectory $Tmp
      }
    }
    It '<Command> は空白で分かれず、dotfiles の中のスクリプトが動く' -ForEach $Hooks {
      $r = Invoke-InBash $Command
      $r.ExitCode | Should -Not -BeIn @(126, 127) -Because $r.Err
      $r.Err | Should -Not -Match 'No such file or directory|command not found|not found|Is a directory'
    }
    It 'hook env は CLAUDE_ENV_FILE に空白を含む dotfiles の shims と bin を書く' {
      if (Test-Path -LiteralPath $EnvFile) { Remove-Item -LiteralPath $EnvFile }
      $r = Invoke-InBash '"$HOME/dotfiles/windows/posix/hook" env'
      $r.ExitCode | Should -Be 0 -Because $r.Err
      $text = [IO.File]::ReadAllText($EnvFile, $Utf8)
      $text | Should -Match 'Jane Doe/dotfiles/windows/posix/shims'
      $text | Should -Match 'Jane Doe/dotfiles/bin'
    }
    It 'ステータスラインのコマンドは空白を含むホームでも動き、出力する' {
      $StatusLine | Should -Match 'statusline\.ps1'
      $r = Invoke-InBash $StatusLine @{ Path = "$(Split-Path -Parent $Pwsh);$env:Path" } '{"model":{"display_name":"M"},"workspace":{"current_dir":"C:\\"}}'
      $r.ExitCode | Should -Be 0 -Because $r.Err
      $r.Out | Should -Not -BeNullOrEmpty -Because $r.Err
    }
  }
}
