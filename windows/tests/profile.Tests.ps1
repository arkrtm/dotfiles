#Requires -Version 7.4
# windows/powershell/profile.ps1 が mise activate の後に包む 2 つの hook（cd の LocationChangedAction と prompt）: mise の処理の後に、PATH から mise の Node の install の
# ディレクトリだけを外す（shims と、ripgrep などほかの道具の install は残り、順も保つ）。mise の hook の形をまねた偽の LocationChangedAction と prompt を用意して、プロファイルの関数を読ませて確かめる。本物の mise は動かさない

BeforeAll {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $Ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'windows\powershell\profile.ps1'), [ref]$null, [ref]$null)
  $Shims = "$env:LOCALAPPDATA\mise\shims"
  $Node = "$env:LOCALAPPDATA\mise\installs\node\22.1.0"
  $Rg = "$env:LOCALAPPDATA\mise\installs\ripgrep\14.1.0\ripgrep-14.1.0-x86_64-pc-windows-msvc"
  $Decoy = "$env:LOCALAPPDATA\mise\installs\nodex\1"
  $Dir = Join-Path $TestDrive 'dir'
  $null = New-Item -ItemType Directory -Path $Dir
  $Ci = $ExecutionContext.SessionState.InvokeCommand
  $Saved = @{ Path = $env:PATH; Loc = Get-Location; Chpwd = $Ci.LocationChangedAction; Prompt = $function:prompt }

  # 偽の mise activate: Node と ripgrep の install のディレクトリを（あれば畳んで）PATH の先頭に置く hook を、cd と prompt に付ける
  $Global:TestInstalls = @($Rg, $Node)
  $Global:TestCalls = [Collections.Generic.List[string]]::new()
  function Global:Set-TestInstallFirst { $env:PATH = ($Global:TestInstalls + @($env:PATH -split ';' | Where-Object { $_ -notin $Global:TestInstalls })) -join ';' }
  $Ci.LocationChangedAction = [EventHandler[Management.Automation.LocationChangedEventArgs]] { $Global:TestCalls.Add('chpwd'); Set-TestInstallFirst }
  function Global:prompt { $ok = $?; $Global:TestCalls.Add('prompt'); Set-TestInstallFirst; "P:$ok" }

  $fns = $Ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -match '^(Global:)?(Remove-DotfilesNodeInstall|Enable-DotfilesNodeShims)$' }, $true)
  $fns.Count | Should -Be 2
  . ([scriptblock]::Create(($fns.Extent.Text -join "`n")))
  Enable-DotfilesNodeShims
}

AfterAll {
  Set-Location -LiteralPath $Saved.Loc.Path
  $Ci.LocationChangedAction = $Saved.Chpwd
  Set-Item Function:\Global:prompt $Saved.Prompt
  Remove-Item Function:\Global:Set-TestInstallFirst, Function:\Global:Remove-DotfilesNodeInstall, Function:\Global:Enable-DotfilesNodeShims -ErrorAction Ignore
  Remove-Variable TestInstalls, TestCalls, DotfilesPrompt -Scope Global -ErrorAction Ignore
  $env:PATH = $Saved.Path
}

Describe 'PATH から mise の Node の install を外す hook（profile.ps1）' {
  BeforeEach {
    $Global:TestCalls.Clear()
    $env:PATH = "C:\a;$Shims;C:\b;$Decoy;C:\c"
  }
  It 'cd の後、mise の hook が先に走り、Node の install だけが消えて、ripgrep の install・shims・ほかの順は保たれる' {
    Set-Location -LiteralPath $Dir
    $Global:TestCalls | Should -Contain 'chpwd'
    $env:PATH | Should -BeExactly "$Rg;C:\a;$Shims;C:\b;$Decoy;C:\c"
  }
  It 'prompt の後、mise の prompt が先に走り、Node の install だけが消えて、戻り値がそのまま返る' {
    $r = prompt
    $Global:TestCalls | Should -Contain 'prompt'
    $r | Should -BeExactly 'P:True'
    $env:PATH | Should -BeExactly "$Rg;C:\a;$Shims;C:\b;$Decoy;C:\c"
  }
  It 'prompt は直前のコマンドの成否（$?）を mise の prompt に渡す' {
    Write-Error '' -ErrorAction Ignore
    $r = prompt
    $r | Should -BeExactly 'P:False'
  }
  It '何度呼んでも同じ（Node の install は無く、ほかは変わらない）' {
    $null = prompt
    $null = prompt
    Set-Location -LiteralPath $Dir
    $env:PATH | Should -BeExactly "$Rg;C:\a;$Shims;C:\b;$Decoy;C:\c"
  }
  It 'Node の install を外した後も、npm.cmd・npx.cmd・corepack.cmd は windows/bin のものが見つかる' {
    $saved = $env:LOCALAPPDATA
    $la = Join-Path $TestDrive 'la'
    $inst = Join-Path $la 'mise\installs\node\22'
    $null = New-Item -ItemType Directory -Path $inst
    foreach ($n in 'npm', 'npx', 'corepack') { $null = New-Item -ItemType File -Path (Join-Path $inst "$n.cmd") }
    $env:LOCALAPPDATA = $la
    try {
      $env:PATH = "$inst;$la\mise\shims;$(Join-Path $Root 'windows\bin');C:\x"
      foreach ($n in 'npm', 'npx', 'corepack') { (Get-Command "$n.cmd" -CommandType Application | Select-Object -First 1).Source | Should -BeExactly (Join-Path $inst "$n.cmd") }
      Remove-DotfilesNodeInstall
      foreach ($n in 'npm', 'npx', 'corepack') { (Get-Command "$n.cmd" -CommandType Application | Select-Object -First 1).Source | Should -BeExactly (Join-Path $Root "windows\bin\$n.cmd") }
    } finally { $env:LOCALAPPDATA = $saved }
  }
  It 'mise activate の行の中（mise があるときだけ）で、その後に呼ぶ' {
    $call = $Ast.Find({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Enable-DotfilesNodeShims' }, $true)
    $call | Should -Not -BeNullOrEmpty
    $if = $call.Parent
    while ($if -and $if -isnot [Management.Automation.Language.IfStatementAst]) { $if = $if.Parent }
    $if | Should -Not -BeNullOrEmpty
    $if.Clauses[0].Item1.Extent.Text | Should -Match 'Get-Command mise'
    $if.Extent.Text.IndexOf('mise activate pwsh') | Should -BeLessThan ($call.Extent.StartOffset - $if.Extent.StartOffset)
  }
}

Describe 'windows/bin の npm.cmd・npx.cmd・corepack.cmd（mise の shims の .exe へ渡す）' {
  BeforeAll {
    $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $Csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $Cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $Bin = Join-Path $Root 'windows\bin'
    $Utf8 = [Text.UTF8Encoding]::new($false)
    # 偽の shims: 受け取った引数を 1 つずつ出し、最初の引数が ok なら 0、ほかは 7 で終わる .exe（.NET Framework の csc.exe で作る）
    $La = Join-Path $TestDrive 'shim la'
    $ShimDir = Join-Path $La 'mise\shims'
    $null = New-Item -ItemType Directory -Path $ShimDir
    if (Test-Path -LiteralPath $Csc) {
      $src = Join-Path $TestDrive 'fake-shim.cs'
      [IO.File]::WriteAllText($src, 'class P { static int Main(string[] a) { foreach (var s in a) System.Console.Out.WriteLine("ARG=[" + s + "]"); return a.Length > 0 && a[0] == "ok" ? 0 : 7; } }')
      foreach ($n in 'npm', 'npx', 'corepack') { $null = & $Csc /nologo /target:exe "/out:$(Join-Path $ShimDir "$n.exe")" $src }
    }
    function Invoke-Shim([string]$Name, [string[]]$A, [string]$LocalAppData) {
      $psi = [Diagnostics.ProcessStartInfo]::new($Cmd)
      foreach ($x in @('/d', '/c', (Join-Path $Bin "$Name.cmd")) + $A) { $psi.ArgumentList.Add($x) }
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = $psi.StandardErrorEncoding = $Utf8
      $psi.Environment['LOCALAPPDATA'] = $LocalAppData
      $p = [Diagnostics.Process]::Start($psi)
      $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
      $p.WaitForExit()
      [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $o.Result; Err = $e.Result }
    }
  }
  It '<Name>.cmd は shims の <Name>.exe に引数（空白・引用符を含む）をそのまま渡す' -Skip:(-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'))) -ForEach @(@{ Name = 'npm' }, @{ Name = 'npx' }, @{ Name = 'corepack' }) {
    $r = Invoke-Shim $Name @('a b', "it's", '--flag=v w') $La
    $r.Out -split "`r?`n" | Where-Object { $_ } | Should -Be @('ARG=[a b]', "ARG=[it's]", 'ARG=[--flag=v w]')
  }
  It '<Name>.cmd は shims の <Name>.exe の終了コードを返す' -Skip:(-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'))) -ForEach @(@{ Name = 'npm' }, @{ Name = 'npx' }, @{ Name = 'corepack' }) {
    (Invoke-Shim $Name @('ok') $La).ExitCode | Should -Be 0
    (Invoke-Shim $Name @('x') $La).ExitCode | Should -Be 7
  }
  It '<Name>.cmd は shims の <Name>.exe が無ければ名前を出して 1 で終わる' -ForEach @(@{ Name = 'npm' }, @{ Name = 'npx' }, @{ Name = 'corepack' }) {
    $r = Invoke-Shim $Name @('x') (Join-Path $TestDrive 'no la')
    $r.ExitCode | Should -Be 1
    $r.Err | Should -Match "$Name\.exe was not found"
  }
}
