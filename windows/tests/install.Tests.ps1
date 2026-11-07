#Requires -Version 7.4
# windows/install.ps1 を一時ホームに -LinksOnly で実行する（本物のホーム・レジストリには触らない）: リンク表のどの行もリポジトリのファイルへのシンボリックリンクになる、
# 前からあるものは *.bak.（14 桁の時刻） に退避する、2 回目は何も出さない、worktree からは DOTFILES_ALLOW_WORKTREE なしでは拒む、ponytail の band を書く。
# リンクを置けないときは失敗を一覧にして終了コード 1 にする。install-lib.ps1 の Invoke-Step・Add-StepFailure・Complete-Install・New-CodexConfig（テンプレートに無い設定の引き継ぎ・キーの正規化と重複の検査を含む）・Get-CrlfCheckout・Update-TerminalSettings を一時ファイルで、
# Add-UserPath をレジストリの代わりのもので確かめる。install.ps1 の手順の書き方は構文木で見る

BeforeDiscovery {
  # リンク表（spec の表。-HomeDir が本物のホームと違うとき AppData・Documents はホームの下）
  $Rows = @(
    @{ Src = 'config/git/config'; Dst = '.config/git/config' }
    @{ Src = 'config/git/ignore'; Dst = '.config/git/ignore' }
    @{ Src = 'windows/git/hooks-nosign'; Dst = '.config/git/hooks-nosign' }
    @{ Src = 'config/mise/config.toml'; Dst = '.config/mise/config.toml' }
    @{ Src = 'config/starship.toml'; Dst = '.config/starship.toml' }
    @{ Src = 'config/bat/config'; Dst = 'AppData/Roaming/bat/config' }
    @{ Src = 'config/nvim'; Dst = 'AppData/Local/nvim' }
    @{ Src = 'config/yazi'; Dst = 'AppData/Roaming/yazi/config' }
    @{ Src = 'windows/herdr/config.toml'; Dst = 'AppData/Roaming/herdr/config.toml' }
    @{ Src = 'windows/claude/settings.json'; Dst = '.claude/settings.json' }
    @{ Src = 'windows/claude/CLAUDE.md'; Dst = '.claude/CLAUDE.md' }
    @{ Src = 'config/agents/AGENTS.md'; Dst = '.codex/AGENTS.md' }
    @{ Src = 'config/agents/skills/issue'; Dst = '.claude/skills/issue' }
    @{ Src = 'config/agents/skills/wrap-up'; Dst = '.claude/skills/wrap-up' }
    @{ Src = 'config/agents/skills/handoff'; Dst = '.claude/skills/handoff' }
    @{ Src = 'config/agents/skills/issue'; Dst = '.agents/skills/issue' }
    @{ Src = 'config/agents/skills/wrap-up'; Dst = '.agents/skills/wrap-up' }
    @{ Src = 'ssh/config'; Dst = '.ssh/config' }
    @{ Src = 'windows/powershell/profile.ps1'; Dst = 'Documents/PowerShell/profile.ps1' }
    @{ Src = 'windows/terminal/dotfiles.json'; Dst = 'AppData/Local/Microsoft/Windows Terminal/Fragments/dotfiles/dotfiles.json' }
  )
}

BeforeAll {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $Install = Join-Path $Root 'windows\install.ps1'
  $Pwsh = (Get-Command pwsh -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
  if (-not $Pwsh) { $Pwsh = [Environment]::ProcessPath }

  # 子プロセスを UTF-8 で動かし、終了コード・標準出力・標準エラーを返す。$null の環境変数は消す
  function Invoke-Proc {
    param([string]$FilePath, [string[]]$Arguments = @(), [string]$InputText = '', [hashtable]$Environment = @{}, [string]$WorkingDirectory)
    $utf8 = [Text.UTF8Encoding]::new($false)
    $psi = [Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $psi.RedirectStandardOutput = $psi.RedirectStandardError = $true
    $psi.StandardInputEncoding = $psi.StandardOutputEncoding = $psi.StandardErrorEncoding = $utf8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($k in $Environment.Keys) {
      if ($null -eq $Environment[$k]) { [void]$psi.Environment.Remove($k) } else { $psi.Environment[$k] = [string]$Environment[$k] }
    }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $p.StandardInput.Write($InputText); $p.StandardInput.Close()
    if (-not $p.WaitForExit(180000)) { $p.Kill($true); throw "時間切れ: $FilePath $Arguments" }
    $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $o.Result; Err = $e.Result }
  }
  function Invoke-Install {
    param([string]$Script = $Install, [string]$HomeDir, [hashtable]$Environment = @{ DOTFILES_ALLOW_WORKTREE = '1' })
    Invoke-Proc $Pwsh @('-NoProfile', '-NonInteractive', '-File', $Script, '-LinksOnly', '-HomeDir', $HomeDir) -Environment $Environment
  }
  # シンボリックリンクを辿らずに消す（リンク先のリポジトリを消さないよう、リンクはリンクだけ消してから木を消す）
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
  function Get-Norm([string]$p) { [IO.Path]::GetFullPath(($p -replace '/', '\')).TrimEnd('\') }

  # TestDrive は Pester が Remove-Item -Recurse で消すので、リンクを置く一時ホームは自分で作って自分で消す
  $Tmp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-install-test-' + [guid]::NewGuid().ToString('N'))
  $null = New-Item -ItemType Directory -Path $Tmp
  $H = Join-Path $Tmp 'home'

  # 前からあるファイル（退避される）と、別の場所を指すリンク（退避される）
  $null = New-Item -ItemType Directory -Path (Join-Path $H '.config\git') -Force
  [IO.File]::WriteAllText((Join-Path $H '.config\git\config'), "old`n")
  $other = Join-Path $Tmp 'other-ignore'
  [IO.File]::WriteAllText($other, "other`n")
  $null = [IO.File]::CreateSymbolicLink((Join-Path $H '.config\git\ignore'), $other)

  $First = Invoke-Install -HomeDir $H
}

AfterAll {
  if ($Tmp) { Remove-TreeSafe $Tmp }
}

Describe 'install.ps1 -LinksOnly（1 回目）' {
  It '終了コード 0 で、標準エラーに何も出さない' {
    $First.ExitCode | Should -Be 0 -Because $First.Err
    $First.Err | Should -BeNullOrEmpty
  }
  It '<Dst> は <Src> へのシンボリックリンク' -ForEach $Rows {
    $dst = Join-Path $H ($Dst -replace '/', '\')
    $src = Join-Path $Root ($Src -replace '/', '\')
    $item = Get-Item -LiteralPath $dst -Force
    $item.LinkType | Should -Be 'SymbolicLink'
    $t = $item.Target
    if (-not [IO.Path]::IsPathRooted($t)) { $t = Join-Path (Split-Path -Parent $dst) $t }
    Get-Norm $t | Should -Be (Get-Norm $src)
    $item.PSIsContainer | Should -Be (Test-Path -LiteralPath $src -PathType Container)
    Test-Path -LiteralPath $dst | Should -BeTrue -Because 'リンク先が読める'
  }
  It 'リンクごとに link: の行を出す（<N> 行）' -ForEach @(@{ N = $Rows.Count }) {
    $links = @($First.Out -split "`r?`n" | Where-Object { $_ -like 'link:*' })
    $links.Count | Should -Be $N
  }
  It '前からあったファイルを config.bak.（14 桁の時刻） に退避して backup: を出す' {
    $baks = @(Get-ChildItem -LiteralPath (Join-Path $H '.config\git') -Force | Where-Object { $_.Name -like 'config.bak.*' })
    $baks.Count | Should -Be 1
    $baks[0].Name | Should -Match '^config\.bak\.\d{14}$'
    [IO.File]::ReadAllText($baks[0].FullName) | Should -BeExactly "old`n"
    $First.Out | Should -Match ([regex]::Escape("backup: $(Join-Path $H '.config\git\config') -> $($baks[0].FullName)"))
  }
  It '別の場所を指すリンクを ignore.bak.（14 桁の時刻） に退避する' {
    $baks = @(Get-ChildItem -LiteralPath (Join-Path $H '.config\git') -Force | Where-Object { $_.Name -like 'ignore.bak.*' })
    $baks.Count | Should -Be 1
    $baks[0].Name | Should -Match '^ignore\.bak\.\d{14}$'
    $baks[0].LinkType | Should -Be 'SymbolicLink'
    Get-Norm $baks[0].Target | Should -Be (Get-Norm $other)
  }
  It 'ponytail の band（~/.claude/.ponytail-band）に off を書く' {
    [IO.File]::ReadAllBytes((Join-Path $H '.claude\.ponytail-band')) | Should -Be ([byte[]][char[]]"off`n")
  }
  It '-LinksOnly ではリンクの後で終わる（~/.gitconfig や Codex の設定を作らない）' {
    Test-Path -LiteralPath (Join-Path $H '.gitconfig') | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $H '.codex\config.toml') | Should -BeFalse
  }
}

Describe 'install.ps1 -LinksOnly（2 回目）' {
  BeforeAll {
    # 既にある band は書き換えない
    [IO.File]::WriteAllText((Join-Path $H '.claude\.ponytail-band'), "on`n")
    $Second = Invoke-Install -HomeDir $H
  }
  It '終了コード 0 で、link: も backup: も出さない' {
    $Second.ExitCode | Should -Be 0 -Because $Second.Err
    @($Second.Out -split "`r?`n" | Where-Object { $_ -match '^(link|backup):' }) | Should -BeNullOrEmpty
  }
  It '退避は増えない' {
    @(Get-ChildItem -LiteralPath (Join-Path $H '.config\git') -Force | Where-Object { $_.Name -like '*.bak.*' }).Count | Should -Be 2
  }
  It '既にある band はそのまま' {
    [IO.File]::ReadAllText((Join-Path $H '.claude\.ponytail-band')) | Should -BeExactly "on`n"
  }
}

Describe 'install.ps1 -LinksOnly（リンクを置けないとき）' {
  BeforeAll {
    $Bad = Join-Path $Tmp 'badhome'
    $null = New-Item -ItemType Directory -Path (Join-Path $Bad '.config') -Force
    [IO.File]::WriteAllText((Join-Path $Bad '.config\git'), "not a directory`n")
    $R = Invoke-Install -HomeDir $Bad
  }
  It '失敗したリンクを名前と理由の一覧に出し、done. を出さず終了コード 1' {
    $R.ExitCode | Should -Be 1
    $lines = @($R.Out -split "`r?`n")
    $lines | Should -Contain '失敗した手順（理由を直して install.ps1 を再実行する）:'
    foreach ($d in 'config', 'ignore', 'hooks-nosign') {
      @($lines | Where-Object { $_.StartsWith("- リンク $(Join-Path $Bad ".config\git\$d"): ") }).Count | Should -Be 1
    }
    $lines | Should -Not -Contain 'done.'
  }
  It '失敗の後も続け、ほかのリンクと band を作る' {
    (Get-Item -LiteralPath (Join-Path $Bad '.config\starship.toml') -Force).LinkType | Should -Be 'SymbolicLink'
    (Get-Item -LiteralPath (Join-Path $Bad 'Documents\PowerShell\profile.ps1') -Force).LinkType | Should -Be 'SymbolicLink'
    Test-Path -LiteralPath (Join-Path $Bad '.claude\.ponytail-band') | Should -BeTrue
  }
}

Describe 'worktree からの実行' {
  BeforeAll {
    # .git がファイルの偽のチェックアウトに install.ps1 と、それが読み込む install-lib.ps1・gitbash-lib.ps1 だけを写す
    $Wt = Join-Path $Tmp 'wt'
    $null = New-Item -ItemType Directory -Path (Join-Path $Wt 'windows') -Force
    Copy-Item -LiteralPath $Install, (Join-Path $Root 'windows\install-lib.ps1'), (Join-Path $Root 'windows\gitbash-lib.ps1') -Destination (Join-Path $Wt 'windows')
    [IO.File]::WriteAllText((Join-Path $Wt '.git'), "gitdir: $Tmp\main\.git\worktrees\wt`n")
    $WtScript = Join-Path $Wt 'windows\install.ps1'
  }
  It 'DOTFILES_ALLOW_WORKTREE が無ければ終了コード 1 で拒み、何も作らない' {
    $wh = Join-Path $Tmp 'wthome1'
    $r = Invoke-Install -Script $WtScript -HomeDir $wh -Environment @{ DOTFILES_ALLOW_WORKTREE = $null }
    $r.ExitCode | Should -Be 1
    $r.Err | Should -Match 'worktree'
    Test-Path -LiteralPath $wh | Should -BeFalse
  }
  It 'ヘルパーは既定で DOTFILES_ALLOW_WORKTREE を渡す（worktree の中で検査しても通る）' {
    $wh = Join-Path $Tmp 'wthome3'
    $r = Invoke-Install -Script $WtScript -HomeDir $wh
    $r.ExitCode | Should -Be 0 -Because $r.Err
  }
  It '呼び出し側の DOTFILES_ALLOW_WORKTREE は（ヘルパーが消さずに）子プロセスに引き継がれる' {
    $wh = Join-Path $Tmp 'wthome4'
    $old = $env:DOTFILES_ALLOW_WORKTREE
    try {
      $env:DOTFILES_ALLOW_WORKTREE = '1'
      $r = Invoke-Install -Script $WtScript -HomeDir $wh -Environment @{}
    } finally { $env:DOTFILES_ALLOW_WORKTREE = $old }
    $r.ExitCode | Should -Be 0 -Because $r.Err
  }
  It 'DOTFILES_ALLOW_WORKTREE=1 なら続ける' {
    $wh = Join-Path $Tmp 'wthome2'
    $r = Invoke-Install -Script $WtScript -HomeDir $wh -Environment @{ DOTFILES_ALLOW_WORKTREE = '1' }
    $r.ExitCode | Should -Be 0 -Because $r.Err
    (Get-Item -LiteralPath (Join-Path $wh '.config\git\config') -Force).LinkType | Should -Be 'SymbolicLink'
  }
}

Describe 'Invoke-Step・Add-StepFailure・Complete-Install' {
  BeforeAll { . (Join-Path $Root 'windows\install-lib.ps1') }
  BeforeEach {
    $log = [Collections.Generic.List[object]]::new()
    $ran = [Collections.Generic.List[string]]::new()
  }
  It '失敗した手順を名前と理由で記録し、warning: を出し、次の手順へ進む' {
    $out = @(Invoke-Step $log 'a' { throw 'x' } 6>&1)
    Invoke-Step $log 'b' { $ran.Add('b') }
    "$out" | Should -BeExactly 'warning: a: x（続行）'
    $log.Count | Should -Be 1
    $log[0].Name | Should -BeExactly 'a'
    $log[0].Reason | Should -BeExactly 'x'
    $ran | Should -Be @('b')
  }
  It '手順の中の Add-StepFailure は記録して、その手順を続ける' {
    Invoke-Step $log 'c' { Add-StepFailure $log 'c' 'y'; $ran.Add('c の続き') } 6>$null
    $log.Count | Should -Be 1
    $log[0].Reason | Should -BeExactly 'y'
    $ran | Should -Be @('c の続き')
  }
  It '本体の出力はそのまま流す' {
    Invoke-Step $log 'd' { 'z' } | Should -BeExactly 'z'
    $log.Count | Should -Be 0
  }
  It '失敗があれば一覧を出し、done. を出さず 1 を返す' {
    Add-StepFailure $log 'a' 'x' 6>$null
    Add-StepFailure $log 'c' 'y' 6>$null
    Complete-Install $log 6>$null | Should -Be 1
    $text = @(Complete-Install $log 6>&1 | Where-Object { $_ -is [Management.Automation.InformationRecord] }) -join "`n"
    $text | Should -BeExactly "失敗した手順（理由を直して install.ps1 を再実行する）:`n- a: x`n- c: y"
  }
  It '失敗が無ければ done. と残りの手順の案内を出して 0 を返す' {
    Complete-Install $log 6>$null | Should -Be 0
    $text = @(Complete-Install $log 6>&1 | Where-Object { $_ -is [Management.Automation.InformationRecord] }) -join "`n"
    $text | Should -BeExactly "done.`n残りの手順: windows/README.md の「新しい PC での導入」の install.ps1 より後"
  }
}

Describe 'install.ps1 の手順の書き方（構文木）' {
  BeforeAll {
    $Ast = [Management.Automation.Language.Parser]::ParseFile($Install, [ref]$null, [ref]$null)
    $Steps = @($Ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-Step' }, $true))
  }
  It 'どの Invoke-Step も $StepLog に記録する' {
    $Steps | Should -Not -BeNullOrEmpty
    @($Steps | ForEach-Object { $_.CommandElements[1].Extent.Text }) | Should -Be (@('$StepLog') * $Steps.Count)
  }
  It 'warning: を直接 Write-Host しない（Add-StepFailure か throw にする。一覧に出すため）' {
    @($Ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Write-Host' -and $n.CommandElements.Count -gt 1 -and $n.CommandElements[1].Extent.Text -match '^[''"]warning:' }, $true)) | Should -BeNullOrEmpty
  }
  It '<_> の手順は前提が無いとき黙って return しない' -ForEach @('nvim', 'geoview') {
    $name = $_
    $step = @($Steps | Where-Object { $_.CommandElements[2].Extent.Text -eq "'$name'" })
    $step.Count | Should -Be 1
    @($step[0].CommandElements[3].FindAll({ param($n) $n -is [Management.Automation.Language.ReturnStatementAst] }, $true)) | Should -BeNullOrEmpty
  }
  It '最後は Complete-Install の終了コードで終わる' {
    $Ast.EndBlock.Statements[-1].Extent.Text | Should -BeExactly 'exit (Complete-Install $StepLog)'
  }
}

Describe 'New-CodexConfig' {
  BeforeAll {
    . (Join-Path $Root 'windows\install-lib.ps1')
    $Tmpl = Join-Path $Root 'config\codex\config.toml.tmpl'
    $Utf8 = [Text.UTF8Encoding]::new($false)
    $Base = [IO.File]::ReadAllText($Tmpl, $Utf8).Replace('@HOME@', 'C:/Users/test')
    $Effort = "model_reasoning_effort = `"xhigh`"`n"
    $Url = "url = `"https://mcp.linear.app/mcp`"`n"
    # この PC の ~/.codex/config.toml と同じ表とキーの形（値は架空）。Codex デスクトップは notify を最初の表の直前に空行なしで、表をテンプレートの表の間に書く
    $Notify = 'notify = ["C:\\Users\\test\\AppData\\Local\\OpenAI\\Codex\\bin\\codex-computer-use.exe", "turn-ended"]'
    $Desktop = @'
# Codex の設定（古いテンプレートのコメント）
model = "gpt-old"
model_reasoning_effort = "high"

notify = ["C:\\Users\\test\\AppData\\Local\\OpenAI\\Codex\\bin\\codex-computer-use.exe", "turn-ended"]
[plugins."ponytail@ponytail"]
enabled = true

[plugins."codex-app-tools@openai-bundled"]
enabled = true

[plugins."browser@openai-bundled"]
enabled = true

[plugins."documents@openai-primary-runtime"]
enabled = true

[marketplaces.ponytail]
source_type = "git"
source = "https://example.invalid/old-ponytail.git"

[marketplaces.openai-bundled]
source_type = "local"
source = 'C:\Users\test\.codex\.tmp\bundled-marketplaces\openai-bundled'

[marketplaces.openai-primary-runtime]
source_type = "local"
source = 'C:\Users\test\.cache\codex-runtimes\plugins\openai-primary-runtime'

# tinymemory が承認なしで記憶を保存できるように
[sandbox_workspace_write]
writable_roots = ["C:/Users/test/.tinymemory"]

[mcp_servers.linear]
url = "https://mcp.linear.app/mcp"

[mcp_servers.node_repl]
args = []
command = 'C:\Users\test\AppData\Local\OpenAI\Codex\node_repl.exe'
env_vars = ["A", "B", "C", "D"]
startup_timeout_sec = 120

[mcp_servers.node_repl.env]
NODE_REPL_NODE_PATH = 'C:\Users\test\node.exe'
CODEX_HOME = 'C:\Users\test\.codex'
BROWSER_USE_TINYSKY_ENABLED = "1"

[tui]
screen_reader_detection_done = true

[hooks.state]

[hooks.state."ponytail@ponytail:hooks/claude-codex-hooks.json:session_start:0:0"]
trusted_hash = "sha256:0000"
trusted_content_hash = "sha256:1111"

[windows]
sandbox = "elevated"

[desktop]
conversationDetailMode = "steps"
ambient-suggestions-enabled = true
'@
    # テンプレートの後ろに元の順で残る表（テンプレートのコメントと空行は落ちる）
    $DesktopKept = @'
[plugins."codex-app-tools@openai-bundled"]
enabled = true

[plugins."browser@openai-bundled"]
enabled = true

[plugins."documents@openai-primary-runtime"]
enabled = true

[marketplaces.openai-bundled]
source_type = "local"
source = 'C:\Users\test\.codex\.tmp\bundled-marketplaces\openai-bundled'

[marketplaces.openai-primary-runtime]
source_type = "local"
source = 'C:\Users\test\.cache\codex-runtimes\plugins\openai-primary-runtime'

[mcp_servers.node_repl]
args = []
command = 'C:\Users\test\AppData\Local\OpenAI\Codex\node_repl.exe'
env_vars = ["A", "B", "C", "D"]
startup_timeout_sec = 120

[mcp_servers.node_repl.env]
NODE_REPL_NODE_PATH = 'C:\Users\test\node.exe'
CODEX_HOME = 'C:\Users\test\.codex'
BROWSER_USE_TINYSKY_ENABLED = "1"

[tui]
screen_reader_detection_done = true

[hooks.state]

[hooks.state."ponytail@ponytail:hooks/claude-codex-hooks.json:session_start:0:0"]
trusted_hash = "sha256:0000"
trusted_content_hash = "sha256:1111"

[windows]
sandbox = "elevated"

[desktop]
conversationDetailMode = "steps"
ambient-suggestions-enabled = true
'@
    # 複数行の値（中の行は見出し・テンプレートのキー・コメント・空行に見える）
    $MultiRoot = @'
matrix = [
[1, 2],
  # 配列の中のコメント

]
desc = """
[not.a.table]
model = "not a key"
# not a comment

"""
lit = '''
[also.not.a.table]
'''
'@
    $Old = @(
      'model = "old-model"'
      'approval_policy = "never"'
      ''
      "[projects.'C:\x']"
      'trust_level = "trusted"'
      ''
      '[mcp_servers.linear]'
      'url = "https://old.example/mcp"'
      ''
      '[hooks.state."abc"]'
      ''
      'enabled = true'
      '[windows]'
      'sandbox = "elevated"'
      '[other]'
      'x = 1'
      '[tui]'
      'notifications = true'
      # awk と同じく大文字小文字を区別するので落ちる
      '[TUI]'
      'foo = 1'
      '[Windows]'
      'w = 2'
      '[[a]]'
      'n = 1'
      '[[a]]'
      'n = 2'
    ) -join "`n"
    # テンプレートに無いトップレベルのキーはテンプレートのトップレベルの後ろ、テンプレートに無い表はテンプレートの後ろに元の順で。見出しの前に空行を 1 つ、値の外の空行は落とす
    $ExpectedOld = $Base.Replace($Effort, $Effort + "approval_policy = `"never`"`n") +
      "`n[projects.'C:\x']`ntrust_level = `"trusted`"`n" +
      "`n[hooks.state.`"abc`"]`nenabled = true`n" +
      "`n[windows]`nsandbox = `"elevated`"`n" +
      "`n[other]`nx = 1`n" +
      "`n[tui]`nnotifications = true`n" +
      "`n[TUI]`nfoo = 1`n" +
      "`n[Windows]`nw = 2`n" +
      "`n[[a]]`nn = 1`n" +
      "`n[[a]]`nn = 2`n"
    function Get-Baks([string]$Conf) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Conf) -Force | Where-Object { $_.Name -like "$(Split-Path -Leaf $Conf).bak.*" }) }
  }
  It '無ければ親のディレクトリごと作り、@HOME@ を / 区切りのホームにする' {
    $conf = Join-Path $TestDrive 'new\.codex\config.toml'
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    $text = [IO.File]::ReadAllText($conf, $Utf8)
    $text | Should -BeExactly $Base
    $text | Should -Not -Match '@HOME@'
    $text | Should -Match ([regex]::Escape('writable_roots = ["C:/Users/test/.tinymemory"]'))
    @(Get-Baks $conf).Count | Should -Be 0
  }
  It '既存の設定のテンプレートにあるキーはテンプレートの値にし、ほかのキーと表（配列の表、大文字小文字だけ違う表を含む）を残し、退避する' {
    $conf = Join-Path $TestDrive 'old\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Old + "`n", $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    $b = [IO.File]::ReadAllBytes($conf)
    $Utf8.GetString($b) | Should -BeExactly $ExpectedOld
    ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) | Should -BeFalse -Because 'BOM を付けない'
    [Array]::IndexOf($b, [byte]13) | Should -Be -1 -Because 'LF だけ'
    $baks = Get-Baks $conf
    $baks.Count | Should -Be 1
    $baks[0].Name | Should -Match '^config\.toml\.bak\.\d{14}$'
    [IO.File]::ReadAllText($baks[0].FullName, $Utf8) | Should -BeExactly ($Old + "`n")
  }
  It '同じ内容になる再実行では書かず、退避もしない' {
    $conf = Join-Path $TestDrive 'old\config.toml'
    $before = [IO.File]::ReadAllBytes($conf)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
    [IO.File]::ReadAllBytes($conf) | Should -Be $before
    (Get-Baks $conf).Count | Should -Be 1
  }
  It 'CRLF と BOM の既存の設定からも LF・BOM なしで同じものを作る' {
    $conf = Join-Path $TestDrive 'crlf\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, ($Old -replace "`n", "`r`n") + "`r`n", [Text.UTF8Encoding]::new($true))
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test\' 6>$null | Should -BeTrue
    [IO.File]::ReadAllBytes($conf) | Should -Be ($Utf8.GetBytes($ExpectedOld))
  }
  It 'Codex デスクトップが書いた設定（この PC と同じ形）を値ごと残し、テンプレートにある設定はテンプレートの値にする' {
    $conf = Join-Path $TestDrive 'desktop\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Desktop + "`n", $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base.Replace($Effort, $Effort + $Notify + "`n") + "`n" + $DesktopKept + "`n")
  }
  It 'Codex デスクトップの設定があっても 2 回目は書き換えず、退避もしない' {
    $conf = Join-Path $TestDrive 'desktop\config.toml'
    $before = [IO.File]::ReadAllBytes($conf)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
    [IO.File]::ReadAllBytes($conf) | Should -Be $before
    (Get-Baks $conf).Count | Should -Be 1
  }
  It 'テンプレートの表に足されたキーをその表に、テンプレートの表の子の表をテンプレートの後ろに残す' {
    $conf = Join-Path $TestDrive 'extra\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $old = "[mcp_servers.linear]`nurl = `"https://old.example/mcp`"`nstartup_timeout_sec = 30`n`n[mcp_servers.linear.env]`nLINEAR_ENV = `"x`"`n`n[plugins.`"ponytail@ponytail`"]`nenabled = false`n"
    [IO.File]::WriteAllText($conf, $old, $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base.Replace($Url, $Url + "startup_timeout_sec = 30`n") + "`n[mcp_servers.linear.env]`nLINEAR_ENV = `"x`"`n")
  }
  It '複数行の値は、中に見出し・キー・コメント・空行に見える行があっても 1 つの値として行ごと残し、2 回目は書き換えない' {
    $conf = Join-Path $TestDrive 'multi\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, "model = `"old`"`n" + $MultiRoot + "`n[tui]`nx = 1`n", $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base.Replace($Effort, $Effort + $MultiRoot + "`n") + "`n[tui]`nx = 1`n")
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
  }
  It 'キーと表の名前は、書き方（引用符・ドットの前後の空白）が違っても同じものとして扱う' {
    $conf = Join-Path $TestDrive 'quoted\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $old = "`"model`" = `"old`"`n[ plugins . `"ponytail@ponytail`" ]`n'enabled' = false`nx = 1`n[mcp_servers.'linear']`nurl = `"https://old.example/mcp`"`n"
    [IO.File]::WriteAllText($conf, $old, $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    $p = "[plugins.`"ponytail@ponytail`"]`nenabled = true`n"
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base.Replace($p, $p + "x = 1`n"))
  }
  It '書く前に、正規化したキーの重複（<Case>）を見つけたら、書かず退避もせず失敗する' -ForEach @(
    @{ Case = 'トップレベルのドット付きのキーとテンプレートの表のキー'; Old = "mcp_servers.linear.url = `"https://x.example/mcp`"`n"; Key = 'mcp_servers.linear.url' }
    @{ Case = '残す表の中の、書き方だけ違う同じキー'; Old = "[desktop]`na = 1`n`"a`" = 2`n"; Key = 'desktop.a' }
  ) {
    $conf = Join-Path $TestDrive ('dup\' + [guid]::NewGuid().ToString('N') + '\config.toml')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Old, $Utf8)
    { New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null } | Should -Throw "*同じキーが 2 回ある*$Key*"
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $Old
    (Get-Baks $conf).Count | Should -Be 0
  }
  It '値（<Case>）で定義した名前の下や同じ名前に表を作ることになるなら、書かず退避もせず失敗する' -ForEach @(
    @{ Case = 'インライン表のトップレベルのキーとテンプレートの子の表'; Old = "mcp_servers = { other = { command = `"my-mcp`" } }`n"; Key = 'mcp_servers' }
    @{ Case = '残す表の中のキーと、その下の子の表'; Old = "[desktop]`nx = { y = 1 }`n`n[desktop.x.z]`nw = 1`n"; Key = 'desktop.x' }
    @{ Case = '残す表の中のキーとテンプレートの表の見出し'; Old = "[plugins]`n`"ponytail@ponytail`" = { enabled = false }`n"; Key = 'plugins.ponytail@ponytail' }
  ) {
    $conf = Join-Path $TestDrive ('parent\' + [guid]::NewGuid().ToString('N') + '\config.toml')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Old, $Utf8)
    { New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null } | Should -Throw "*config.toml*$Key*"
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $Old
    (Get-Baks $conf).Count | Should -Be 0
  }
  It 'ドット付きのキー（<Case>）が表の名前の途中までと同じなら、同じ表を 2 回定義することになるので、書かず退避もせず失敗する' -ForEach @(
    @{ Case = 'トップレベルのキーとテンプレートの表'; Old = "mcp_servers.linear.command = `"x`"`n"; Key = 'mcp_servers.linear' }
    @{ Case = '残す表の中のキーとテンプレートの表'; Old = "[mcp_servers]`nlinear.command = `"x`"`n"; Key = 'mcp_servers.linear' }
    @{ Case = '残す表の中のキーと、その途中の名前の子の表'; Old = "[desktop]`na.b.c = 1`n`n[desktop.a.b]`nd = 1`n"; Key = 'desktop.a.b' }
  ) {
    $conf = Join-Path $TestDrive ('dotted\' + [guid]::NewGuid().ToString('N') + '\config.toml')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Old, $Utf8)
    { New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null } | Should -Throw "*config.toml*$Key*"
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $Old
    (Get-Baks $conf).Count | Should -Be 0
  }
  It 'ドット付きのキーで作った表に、さらに深い名前の子の表を足すのは正しい TOML なので受け入れ、2 回目は書き換えない' {
    $conf = Join-Path $TestDrive 'subtable\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $keep = "`n[desktop]`napple.color = `"red`"`n`n[desktop.apple.texture]`nsmooth = true`n"
    [IO.File]::WriteAllText($conf, $keep.TrimStart("`n"), $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base + $keep)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
  }
  It 'Unicode エスケープ（\uXXXX・\UXXXXXXXX）を含む正しい表の名前もそのまま残し、2 回目は書き換えない' {
    $conf = Join-Path $TestDrive 'unicode\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $keep = "`n[projects.`"C:/work/\U0001F680`"]`ntrust_level = `"trusted`"`n`n[projects.`"C:/work/\u00e9`"]`ntrust_level = `"trusted`"`n"
    [IO.File]::WriteAllText($conf, $keep.TrimStart("`n"), $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base + $keep)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
  }
  It 'エスケープで書いた名前は、実際の文字で書いたテンプレートの表と同じ名前として扱う' {
    $conf = Join-Path $TestDrive 'unicode-merge\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, "[mcp_servers.`"\u006c\U00000069near`"]`nurl = `"https://old.example/mcp`"`n", $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $Base
  }
  It 'エスケープの書き方だけ違う同じキー（<Case>）は重複として、書かず退避もせず失敗する' -ForEach @(
    @{ Case = '\u'; Old = "[desktop]`n`"\u00e9`" = 1`n`"$([char]0x00e9)`" = 2`n" }
    @{ Case = '\U'; Old = "[desktop]`n`"\U0001F680`" = 1`n`"$([char]::ConvertFromUtf32(0x1F680))`" = 2`n" }
    @{ Case = '\t と \"'; Old = "[desktop]`n`"a\tb\`"`" = 1`n'a`tb`"' = 2`n" }
  ) {
    $conf = Join-Path $TestDrive ('esc\' + [guid]::NewGuid().ToString('N') + '\config.toml')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Old, $Utf8)
    { New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null } | Should -Throw '*同じキーが 2 回ある*desktop*'
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $Old
    (Get-Baks $conf).Count | Should -Be 0
  }
  It 'TOML に無いエスケープを名前に含む設定は、書かず退避もせず失敗する' {
    $conf = Join-Path $TestDrive 'badesc\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $old = "[desktop]`n`"a\xb`" = 1`n"
    [IO.File]::WriteAllText($conf, $old, $Utf8)
    { New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null } | Should -Throw '*エスケープ*'
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $old
    (Get-Baks $conf).Count | Should -Be 0
  }
  It '配列の表の要素ごとに子の表を持つ設定（<Case>）は正しい TOML なので受け入れ、2 回目は書き換えない' -ForEach @(
    @{ Case = '同じ名前の子の表'; Old = "[[a]]`n[a.options]`nx = 1`n[[a]]`n[a.options]`nx = 2`n"; Kept = "`n[[a]]`n`n[a.options]`nx = 1`n`n[[a]]`n`n[a.options]`nx = 2`n" }
    @{ Case = '片方の要素の値の下に、もう片方の要素の子の表'; Old = "[[a]]`n[a.o]`nx = { y = 1 }`n[[a]]`n[a.o.x]`nz = 1`n"; Kept = "`n[[a]]`n`n[a.o]`nx = { y = 1 }`n`n[[a]]`n`n[a.o.x]`nz = 1`n" }
  ) {
    $conf = Join-Path $TestDrive ('elem\' + [guid]::NewGuid().ToString('N') + '\config.toml')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    [IO.File]::WriteAllText($conf, $Old, $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base + $Kept)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
  }
  It '同じ配列の表の要素の中で子の表が重複したら、書かず退避もせず失敗する' {
    $conf = Join-Path $TestDrive 'elemdup\config.toml'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $old = "[[a]]`n[a.options]`nx = 1`n[[a]]`n[a.options]`nx = 2`n[a.options]`ny = 3`n"
    [IO.File]::WriteAllText($conf, $old, $Utf8)
    { New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null } | Should -Throw '*同じキーが 2 回ある*a.options*'
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly $old
    (Get-Baks $conf).Count | Should -Be 0
  }
  It '複数行の文字列が <Delim> を 4 個・5 個並べて閉じても 1 つの値として残し、後ろの表を別の表として扱い、2 回目は書き換えない' -ForEach @(
    @{ Delim = '"""'; Notify = 'notify = ["pwsh", "-Command", """Write-Host "done""""]' }
    @{ Delim = '"""'; Notify = 'notify = ["pwsh", "-Command", """Write-Host ""done"""""]' }
    @{ Delim = "'''"; Notify = "notify = [`"pwsh`", `"-Command`", '''Write-Host 'done'''']" }
    @{ Delim = "'''"; Notify = "notify = [`"pwsh`", `"-Command`", '''Write-Host ''done''''']" }
  ) {
    $conf = Join-Path $TestDrive ('quotes\' + [guid]::NewGuid().ToString('N') + '\config.toml')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $conf) -Force
    $old = "model = `"old`"`n$Notify`n[plugins.`"ponytail@ponytail`"]`nenabled = false`n`n[desktop]`nx = 1`n"
    [IO.File]::WriteAllText($conf, $old, $Utf8)
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeTrue
    [IO.File]::ReadAllText($conf, $Utf8) | Should -BeExactly ($Base.Replace($Effort, $Effort + $Notify + "`n") + "`n[desktop]`nx = 1`n")
    New-CodexConfig -Template $Tmpl -ConfigPath $conf -HomeDir 'C:\Users\test' 6>$null | Should -BeFalse
  }
}

Describe 'Get-CrlfCheckout' {
  BeforeAll {
    . (Join-Path $Root 'windows\install-lib.ps1')
    $Git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    $EmptyConfig = Join-Path $TestDrive 'empty-gitconfig'
    [IO.File]::WriteAllText($EmptyConfig, '')
    $GitEnv = @{ GIT_CONFIG_GLOBAL = $EmptyConfig; GIT_CONFIG_NOSYSTEM = '1'; GIT_AUTHOR_NAME = 't'; GIT_AUTHOR_EMAIL = 't@example.com'; GIT_COMMITTER_NAME = 't'; GIT_COMMITTER_EMAIL = 't@example.com' }
    function Invoke-Git { $r = Invoke-Proc $Git ([string[]]$args) -Environment $GitEnv; $r.ExitCode | Should -Be 0 -Because $r.Err }
    $SavedGitEnv = @{ GIT_CONFIG_GLOBAL = $env:GIT_CONFIG_GLOBAL; GIT_CONFIG_NOSYSTEM = $env:GIT_CONFIG_NOSYSTEM }
    # windows/.gitattributes と同じ属性で、LF で入れたファイルを CRLF で取り出し直す
    $Repo = Join-Path $TestDrive 'eol'
    Invoke-Git init -q $Repo
    Invoke-Git -C $Repo config core.autocrlf input
    $null = New-Item -ItemType Directory -Path (Join-Path $Repo 'windows\bin') -Force
    Copy-Item -LiteralPath (Join-Path $Root 'windows\.gitattributes') -Destination (Join-Path $Repo 'windows')
    Copy-Item -LiteralPath (Join-Path $Root 'windows\bin\notify.cmd') -Destination (Join-Path $Repo 'windows\bin')
    [IO.File]::WriteAllText((Join-Path $Repo 'a.txt'), "x`r`ny`r`n")
    [IO.File]::WriteAllText((Join-Path $Repo 'b.txt'), "x`n")
    Invoke-Git -C $Repo add -A
    Invoke-Git -C $Repo commit -q -m x
    Remove-Item -LiteralPath (Join-Path $Repo 'a.txt'), (Join-Path $Repo 'windows\bin\notify.cmd')
    Invoke-Git -C $Repo -c core.autocrlf=true checkout -- .
  }
  # Get-CrlfCheckout はこのプロセスの git を使うので、It の中だけ空の設定にする
  AfterEach { $env:GIT_CONFIG_GLOBAL = $SavedGitEnv.GIT_CONFIG_GLOBAL; $env:GIT_CONFIG_NOSYSTEM = $SavedGitEnv.GIT_CONFIG_NOSYSTEM }
  It 'CRLF で取り出された LF のファイルだけを返し、属性で CRLF を求める .cmd は返さない' {
    $env:GIT_CONFIG_GLOBAL = $EmptyConfig; $env:GIT_CONFIG_NOSYSTEM = '1'
    $got = @(Get-CrlfCheckout $Repo)
    $got | Should -Be @('a.txt')
    [IO.File]::ReadAllText((Join-Path $Repo 'windows\bin\notify.cmd')) | Should -Match "`r`n" -Because '比べる前提: .cmd は CRLF で取り出されている'
  }
  It '取り出し直したあとは空（install.ps1 の手順 1 は 2 回目に何もしない）' {
    $env:GIT_CONFIG_GLOBAL = $EmptyConfig; $env:GIT_CONFIG_NOSYSTEM = '1'
    Remove-Item -LiteralPath (Join-Path $Repo 'a.txt')
    Invoke-Git -C $Repo checkout -- .
    @(Get-CrlfCheckout $Repo).Count | Should -Be 0
  }
}

Describe 'Add-UserPath' {
  BeforeAll {
    . (Join-Path $Root 'windows\install-lib.ps1')
    # レジストリの代わり（HKCU\Environment の Path の値と種類だけを持つ）
    $Fake = [pscustomobject]@{ Value = $null; Kind = $null }
    $Fake | Add-Member ScriptMethod GetValue { param($Name, $Default, $Options) if ($Name -eq 'Path') { $this.Value } else { $Default } }
    $Fake | Add-Member ScriptMethod GetValueKind { param($Name) $this.Kind }
    $Fake | Add-Member ScriptMethod SetValue { param($Name, $Value, $Kind) $this.Value = $Value; $this.Kind = $Kind }
    $Fake | Add-Member ScriptMethod Dispose { }
    Mock Open-UserEnvironmentKey { $Fake }
    Mock Send-EnvironmentChange { }
    $Dirs = @('%USERPROFILE%\.local\bin', '%LOCALAPPDATA%\mise\shims')
  }
  BeforeEach { $SavedPath = $env:Path }
  AfterEach { $env:Path = $SavedPath }
  It '展開した形の REG_SZ に書き戻された Path（Codex のインストーラーの後）を、先頭の %...% の形と REG_EXPAND_SZ に戻す' {
    $Fake.Value = "C:\other;$env:USERPROFILE\.local\bin;$env:LOCALAPPDATA\mise\shims\"
    $Fake.Kind = [Microsoft.Win32.RegistryValueKind]::String
    Add-UserPath @Dirs | Should -BeTrue
    $Fake.Value | Should -BeExactly '%USERPROFILE%\.local\bin;%LOCALAPPDATA%\mise\shims;C:\other'
    $Fake.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    Should -Invoke Send-EnvironmentChange -Times 1 -Exactly
  }
  It '揃っていれば書かず $false' {
    Add-UserPath @Dirs | Should -BeFalse
    $Fake.Value | Should -BeExactly '%USERPROFILE%\.local\bin;%LOCALAPPDATA%\mise\shims;C:\other'
  }
  It '今のプロセスの Path の先頭に展開した形で入れる' {
    $null = Add-UserPath @Dirs
    ($env:Path -split ';')[0..1] | Should -Be @("$env:USERPROFILE\.local\bin", "$env:LOCALAPPDATA\mise\shims")
  }
}

Describe 'Update-TerminalSettings' {
  BeforeAll {
    . (Join-Path $Root 'windows\install-lib.ps1')
    $Utf8 = [Text.UTF8Encoding]::new($false)
    $Pwsh7 = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    # Windows Terminal が書く形（コメント付き、PowerShell 7 の guid は大文字）
    $Sample = @'
// This file was initially generated by Windows Terminal
{
    "$help": "https://aka.ms/terminal-documentation",
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "actions": [ { "command": { "action": "copy", "singleLine": false }, "id": "User.copy.644BA8F2" } ],
    "copyFormatting": "none",
    "copyOnSelect": false,
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "newTabMenu": [ { "type": "remainingProfiles" } ],
    "profiles": {
        "defaults": { "font": { "weight": "normal" }, "opacity": 90 },
        "list": [
            { "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "hidden": false, "name": "Windows PowerShell" },
            { "guid": "{574E775E-4F2A-5B96-AC1E-A2962A402336}", "hidden": false, "name": "PowerShell", "source": "Windows.Terminal.PowershellCore" }
        ]
    },
    "schemes": [],
    "themes": []
}
'@
    function Get-Baks([string]$Path) { @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -Force | Where-Object { $_.Name -like 'settings.json.bak.*' }) }
    function New-Settings([string]$Name, [string]$Text) {
      $dir = Join-Path $TestDrive $Name
      $null = New-Item -ItemType Directory -Path $dir -Force
      $p = Join-Path $dir 'settings.json'
      [IO.File]::WriteAllText($p, $Text, $Utf8)
      $p
    }
    $S = New-Settings 'wt' $Sample
    $FirstResult = Update-TerminalSettings $S 6>$null
    $J = [IO.File]::ReadAllText($S, $Utf8) | ConvertFrom-Json -Depth 50
  }
  It '変えたときは $true を返し、元のファイルを settings.json.bak.（14 桁の時刻） に写す' {
    $FirstResult | Should -BeTrue
    $baks = Get-Baks $S
    $baks.Count | Should -Be 1
    $baks[0].Name | Should -Match '^settings\.json\.bak\.\d{14}$'
    [IO.File]::ReadAllText($baks[0].FullName, $Utf8) | Should -BeExactly $Sample
  }
  It 'profiles.defaults に配色・フォント・余白・履歴を入れる' {
    $d = $J.profiles.defaults
    $d.colorScheme | Should -BeExactly 'Atom One Dark'
    $d.font.face | Should -BeExactly 'Hack Nerd Font Mono'
    $d.font.size | Should -Be 12
    $d.padding | Should -BeExactly '6, 4'
    $d.historySize | Should -Be 50000
  }
  It 'PowerShell 7 のプロファイルがあれば既定にする（guid の大文字小文字は問わない）' {
    $J.defaultProfile | Should -Be $Pwsh7
  }
  It 'ほかのキーとプロファイルはそのまま' {
    $J.profiles.defaults.font.weight | Should -BeExactly 'normal'
    $J.profiles.defaults.opacity | Should -Be 90
    $J.'$schema' | Should -BeExactly 'https://aka.ms/terminal-profiles-schema'
    $J.actions[0].id | Should -BeExactly 'User.copy.644BA8F2'
    $J.actions[0].command.action | Should -BeExactly 'copy'
    $J.copyFormatting | Should -BeExactly 'none'
    $J.copyOnSelect | Should -BeFalse
    $J.newTabMenu[0].type | Should -BeExactly 'remainingProfiles'
    @($J.profiles.list).Count | Should -Be 2
    $J.profiles.list[0].commandline | Should -BeExactly '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
    $J.profiles.list[1].source | Should -BeExactly 'Windows.Terminal.PowershellCore'
    $J.PSObject.Properties.Name | Should -Contain 'schemes'
    @($J.schemes).Count | Should -Be 0
  }
  It 'BOM を付けない' {
    $b = [IO.File]::ReadAllBytes($S)
    $b[0] | Should -Not -Be 0xEF
  }
  It '再実行では $false を返し、書かず、退避もしない' {
    $before = [IO.File]::ReadAllBytes($S)
    Update-TerminalSettings $S 6>$null | Should -BeFalse
    [IO.File]::ReadAllBytes($S) | Should -Be $before
    (Get-Baks $S).Count | Should -Be 1
  }
  It 'PowerShell 7 のプロファイルが無ければ、ほかの設定を書いてから失敗する（defaultProfile は変えない）' {
    $p = New-Settings 'nopwsh' ($Sample -replace '\{574E775E-4F2A-5B96-AC1E-A2962A402336\}', '{00000000-0000-0000-0000-000000000001}')
    { Update-TerminalSettings $p 6>$null } | Should -Throw '*PowerShell 7 のプロファイルが Windows Terminal に無い*'
    $j = [IO.File]::ReadAllText($p, $Utf8) | ConvertFrom-Json
    $j.profiles.defaults.colorScheme | Should -BeExactly 'Atom One Dark'
    $j.defaultProfile | Should -BeExactly '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    (Get-Baks $p).Count | Should -Be 1
    $before = [IO.File]::ReadAllBytes($p)
    { Update-TerminalSettings $p 6>$null } | Should -Throw
    [IO.File]::ReadAllBytes($p) | Should -Be $before -Because '2 回目は書かない'
    (Get-Baks $p).Count | Should -Be 1
  }
  It 'Windows Terminal を開き直してプロファイルができた後の再実行では、既定にして失敗しない' {
    $p = Join-Path $TestDrive 'nopwsh\settings.json'
    $j = [IO.File]::ReadAllText($p, $Utf8) | ConvertFrom-Json -Depth 50
    $j.profiles.list += [pscustomobject]@{ guid = $Pwsh7; name = 'PowerShell'; source = 'Windows.Terminal.PowershellCore' }
    [IO.File]::WriteAllText($p, (ConvertTo-Json $j -Depth 50), $Utf8)
    Update-TerminalSettings $p 6>$null | Should -BeTrue
    ([IO.File]::ReadAllText($p, $Utf8) | ConvertFrom-Json).defaultProfile | Should -Be $Pwsh7
  }
  It '既に揃っている設定（コメント付き）は 1 バイトも変えず、退避もしない' {
    $done = @'
// 手で書いた設定
{
    "defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
    "profiles": {
        "defaults": { "colorScheme": "Atom One Dark", "font": { "face": "Hack Nerd Font Mono", "size": 12 }, "padding": "6, 4", "historySize": 50000 },
        "list": [ { "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}", "name": "PowerShell" } ]
    }
}
'@
    $p = New-Settings 'done' $done
    Update-TerminalSettings $p 6>$null | Should -BeFalse
    [IO.File]::ReadAllText($p, $Utf8) | Should -BeExactly $done
    (Get-Baks $p).Count | Should -Be 0
  }
}
