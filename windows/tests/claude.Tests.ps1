#Requires -Version 7.4
# windows/claude/settings.json が config/claude/settings.json から決めた所だけ違うこと（フックは agent-status を落として windows/posix/hook 経由にする）と、
# windows/claude/statusline.ps1 の出力（2 行、モデル・ブランチ・使用率・Codex のモデルと使用量）とコンテキストの使用率のキャッシュ

BeforeAll {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $Utf8 = [Text.UTF8Encoding]::new($false)
  function Read-Json([string]$Path) { [IO.File]::ReadAllText($Path, $Utf8) | ConvertFrom-Json -Depth 50 }
  function J($o) { ConvertTo-Json -InputObject $o -Depth 50 -Compress }
  $Shared = Read-Json (Join-Path $Root 'config\claude\settings.json')
  $Win = Read-Json (Join-Path $Root 'windows\claude\settings.json')
  $WinCommands = @($Win.hooks.PSObject.Properties.Value | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
  $SharedCommands = @($Shared.hooks.PSObject.Properties.Value | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
}

Describe 'windows/claude/settings.json' {
  It '<Key> は共通の設定と同じ' -ForEach @(
    'enabledPlugins', 'extraKnownMarketplaces', 'model', 'modelSettings', 'theme', 'remoteControlAtStartup', 'skipWorkflowUsageWarning', 'cleanupPeriodDays'
  ).ForEach({ @{ Key = $_ } }) {
    $Win.PSObject.Properties.Name | Should -Contain $Key
    J $Win.$Key | Should -BeExactly (J $Shared.$Key)
  }
  It '共通の設定に無いキーは env と preferredNotifChannel だけで、共通のキーはどれもある' {
    $extra = @($Win.PSObject.Properties.Name | Where-Object { $_ -notin $Shared.PSObject.Properties.Name })
    $extra | Sort-Object | Should -Be @('env', 'preferredNotifChannel')
    @($Shared.PSObject.Properties.Name | Where-Object { $_ -notin $Win.PSObject.Properties.Name }) | Should -BeNullOrEmpty
  }
  It '共通の allow・deny をすべて含み、足すのは PowerShell ツールの同じ規則だけ' {
    foreach ($k in 'allow', 'deny') {
      foreach ($r in $Shared.permissions.$k) { $Win.permissions.$k | Should -Contain $r }
    }
    @($Win.permissions.allow | Where-Object { $_ -notin $Shared.permissions.allow }) |
      Should -Be @('PowerShell(tinymemory *)', 'PowerShell(git diff *)', 'PowerShell(codex-review *)')
    @($Win.permissions.deny | Where-Object { $_ -notin $Shared.permissions.deny }) |
      Should -Be @('PowerShell(git push *)', 'PowerShell(gh pr merge *)', 'PowerShell(integrate --human-approved *)', 'PowerShell(integrate setup --force *)')
    @($Win.permissions.PSObject.Properties.Name) | Should -Be @('allow', 'deny')
  }
  It 'env は PowerShell ツールだけ（Git Bash の場所は書かず、PATH の git から Claude Code に見つけさせる）' {
    J $Win.env | Should -BeExactly (J ([ordered]@{ CLAUDE_CODE_USE_POWERSHELL_TOOL = '1' }))
  }
  It 'statusLine は pwsh で statusline.ps1（パスは引用符で囲む）、通知は端末のベル' {
    J $Win.statusLine | Should -BeExactly (J ([ordered]@{ type = 'command'; command = 'pwsh -NoProfile -NonInteractive -File "$HOME/dotfiles/windows/claude/statusline.ps1"' }))
    $Win.preferredNotifChannel | Should -BeExactly 'terminal_bell'
  }
  It 'agent-status のフックが無い' {
    $WinCommands | Should -Not -BeNullOrEmpty
    @($WinCommands | Where-Object { $_ -match 'agent-status' }) | Should -BeNullOrEmpty
    @($WinCommands | Where-Object { $_ -match '\.local/bin/' -and $_ -notmatch '^sh -c ' }) | Should -BeNullOrEmpty
  }
  It 'tinymemory のコマンドは共通の設定と 1 文字も違わない' {
    $s = @($SharedCommands | Where-Object { $_ -match 'tinymemory' })
    $w = @($WinCommands | Where-Object { $_ -match 'tinymemory' })
    $s.Count | Should -Be 1
    $w.Count | Should -Be 1
    $w[0] | Should -BeExactly $s[0]
  }
  It 'dotfiles のパスは引用符で囲む（ホームに空白があっても分割されない）' {
    $cmds = @($WinCommands | Where-Object { $_ -match 'dotfiles/' }) + @($Win.statusLine.command)
    $cmds.Count | Should -BeGreaterThan 1
    foreach ($c in $cmds) { $c | Should -Match '"\$HOME/dotfiles/[^"\s]+"' -Because $c }
    @($cmds | Where-Object { $_ -match '(?<!")(?:\$HOME|~)/dotfiles' }) | Should -BeNullOrEmpty
  }
  It '$HOME/dotfiles/ が指すファイルはリポジトリにあり、hook の名前は bin/ にある' {
    $refs = @($WinCommands + @($Win.statusLine.command)) | ForEach-Object {
      foreach ($m in [regex]::Matches($_, '\$HOME/dotfiles/([^"\s]+)"?(?:\s+(\S+))?')) { $m }
    }
    @($refs).Count | Should -BeGreaterThan 0
    foreach ($m in $refs) {
      $rel = $m.Groups[1].Value
      Test-Path -LiteralPath (Join-Path $Root $rel) -PathType Leaf | Should -BeTrue -Because $rel
      if ($rel -eq 'windows/posix/hook' -and $m.Groups[2].Value -ne 'env') {
        Test-Path -LiteralPath (Join-Path $Root "bin\$($m.Groups[2].Value)") -PathType Leaf | Should -BeTrue -Because $m.Value
      }
    }
  }
  It 'フックは共通の設定から agent-status を落とし、$HOME/.local/bin/X を "$HOME/dotfiles/windows/posix/hook" X にし、SessionStart の先頭に hook env を足したもの（タイムアウトも同じ）' {
    $exp = [ordered]@{}
    foreach ($ev in $Shared.hooks.PSObject.Properties) {
      $groups = @(foreach ($g in $ev.Value) {
          $hs = @($g.hooks | Where-Object { $_.command -notmatch 'agent-status' } | ForEach-Object {
              $h = $_ | ConvertTo-Json -Depth 10 | ConvertFrom-Json
              $h.command = $h.command -replace '^\$HOME/\.local/bin/', '"$$HOME/dotfiles/windows/posix/hook" '
              $h
            })
          if ($hs.Count) {
            $c = $g | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $c.hooks = $hs
            $c
          }
        })
      if ($groups.Count) { $exp[$ev.Name] = $groups }
    }
    $envHook = [ordered]@{ matcher = 'startup|resume|clear|compact|fork'; hooks = @([ordered]@{ type = 'command'; command = '"$HOME/dotfiles/windows/posix/hook" env'; timeout = 5 }) }
    $exp['SessionStart'] = @($envHook) + @($exp['SessionStart'])
    J $Win.hooks | Should -BeExactly (J $exp)
  }
}

Describe 'windows/claude/statusline.ps1' {
  BeforeAll {
    $Script = Join-Path $Root 'windows\claude\statusline.ps1'
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
    $State = Join-Path $TestDrive 'state'
    $CodexHome = Join-Path $TestDrive 'codex'
    $ChildEnv = @{ XDG_STATE_HOME = $State; CODEX_HOME = $CodexHome; HERDR_ENV = $null; HERDR_PANE_ID = $null }
    function Invoke-StatusLine([string]$InputText) {
      $r = Invoke-Proc $Pwsh @('-NoProfile', '-NonInteractive', '-File', $Script) -InputText $InputText -Environment $ChildEnv -WorkingDirectory $TestDrive
      # 末尾の LF を 1 つ外して行に分ける（2 行目が空でも 2 行と数える）
      $lines = if ($r.Out.EndsWith("`n")) { $r.Out.Substring(0, $r.Out.Length - 1) -split "`n" } else { @($r.Out -split "`n") }
      $r | Add-Member -NotePropertyName Lines -NotePropertyValue @($lines) -PassThru
    }

    # Codex の設定（先頭の model と effort だけを読む。[tui] の model は見ない）と、今日のディレクトリのセッションの記録
    $null = New-Item -ItemType Directory -Path $CodexHome -Force
    [IO.File]::WriteAllText((Join-Path $CodexHome 'config.toml'), "model = `"gpt-test-model`"`nmodel_reasoning_effort = `"medium`"`n`n[tui]`nmodel = `"not-this`"`n", $Utf8)
    $day = Join-Path $CodexHome ('sessions\' + (Get-Date -Format 'yyyy\\MM\\dd'))
    $null = New-Item -ItemType Directory -Path $day -Force
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $rl = '{"timestamp":"2026-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","limit_name":null,' +
      '"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":' + ($now + 3600) + '},' +
      '"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_at":' + ($now + 86400) + '},"plan_type":"prolite"}}}'
    [IO.File]::WriteAllText((Join-Path $day 'x.jsonl'), "{`"type`":`"session_meta`",`"payload`":{}}`n$rl`n", $Utf8)

    # ブランチを決めておくため、git の作業ディレクトリは一時リポジトリにする
    $Repo = Join-Path $TestDrive 'repo'
    git init -q -b statusline-test $Repo
    $Sample = [ordered]@{
      session_id = 'sess-123'
      model = [ordered]@{ id = 'claude-opus-5-5[1m]'; display_name = 'Opus 5.5' }
      effort = [ordered]@{ level = 'high' }
      workspace = [ordered]@{ current_dir = $Repo }
      context_window = [ordered]@{ used_percentage = 42.7 }
      rate_limits = [ordered]@{
        five_hour = [ordered]@{ used_percentage = 81; resets_at = $now + 7200 }
        seven_day = [ordered]@{ used_percentage = 3.2 }
      }
    } | ConvertTo-Json -Depth 10 -Compress
    $R = Invoke-StatusLine $Sample
    $IClaude = [string][char]0xEC82
    $IOpenAI = [string][char]0xEC81
  }
  It '終了コード 0 で 2 行を出す（CR を出さない）' {
    $R.ExitCode | Should -Be 0 -Because $R.Err
    $R.Lines.Count | Should -Be 2
    $R.Out | Should -Not -Match "`r"
  }
  It '1 行目は Claude のモデルと effort、Codex のモデルと effort、ブランチ' {
    $l1 = $R.Lines[0]
    $l1 | Should -Match ([regex]::Escape("$IClaude$([char]27)[0m Opus 5.5"))
    $l1 | Should -Match 'high'
    $l1 | Should -Match ([regex]::Escape("$IOpenAI$([char]27)[0m gpt-test-model"))
    $l1 | Should -Match 'medium'
    $l1 | Should -Not -Match 'not-this'
    $l1 | Should -Match ([regex]::Escape("$([char]0xE0A0) statusline-test"))
  }
  It '2 行目はコンテキスト 42%・5 時間 81%・週 3% と、Codex のアイコンの後に 12%・55%' {
    $l2 = $R.Lines[1]
    $l2 | Should -Match ([regex]::Escape("$([char]0xF1C0) "))
    $l2 | Should -Match ' 42%'
    $l2 | Should -Match ' 81%'
    $l2 | Should -Match '  3%'
    $i = $l2.IndexOf($IOpenAI)
    $i | Should -BeGreaterThan 0
    $cx = $l2.Substring($i)
    $cx | Should -Match ' 12%'
    $cx | Should -Match ' 55%'
  }
  It 'コンテキストの使用率のキャッシュは切り捨てた値と LF だけ（42\n）' {
    [IO.File]::ReadAllBytes((Join-Path $State 'claude-context\sess-123')) | Should -Be ([byte[]](0x34, 0x32, 0x0A))
  }
  It 'session_id が <Sid> ならキャッシュを書かない' -ForEach @(@{ Sid = '..' }, @{ Sid = '.' }, @{ Sid = 'a/b' }, @{ Sid = 'a\b' }) {
    $st = Join-Path $TestDrive "state-$([guid]::NewGuid().ToString('N'))"
    $old = $ChildEnv.XDG_STATE_HOME
    $ChildEnv.XDG_STATE_HOME = $st
    try {
      $r = Invoke-StatusLine (@{ session_id = $Sid; context_window = @{ used_percentage = 10 } } | ConvertTo-Json -Compress)
    } finally { $ChildEnv.XDG_STATE_HOME = $old }
    $r.ExitCode | Should -Be 0
    @(Get-ChildItem -LiteralPath $st -Recurse -File -Force -ErrorAction Ignore) | Should -BeNullOrEmpty
  }
  It '入力が <Name> でも終了コード 0 で 2 行' -ForEach @(@{ Name = '{}'; Text = '{}' }, @{ Name = '空'; Text = '' }) {
    $r = Invoke-StatusLine $Text
    $r.ExitCode | Should -Be 0 -Because $r.Err
    $r.Lines.Count | Should -Be 2
  }
}
