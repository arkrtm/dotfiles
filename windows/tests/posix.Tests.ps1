#Requires -Version 7.4
# Git Bash で動くもの（Git Bash が無ければ飛ばす）: posix/hook env が CLAUDE_ENV_FILE に PATH の行（mise の shims も）を足す、jq の shim は CR を出さない（jq.exe が無ければ飛ばす）、
# git/hooks-nosign/commit-msg はリンク経由の core.hooksPath で AI 由来の行を消す、posix/hook integrate-hook pre-edit は git の外の Windows のパスで 0、
# 編集するファイルのリポジトリで判定する（jq.exe が要る）、posix/run・hook と env の行は /clear を Windows のパスに直させない、
# posix/run と windows/bin/*.cmd・*.ps1 は終了コードを返し、*.ps1 は引数をそのまま渡す

BeforeDiscovery {
  . (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'windows\gitbash-lib.ps1')
  $NoBash = -not (Get-GitBash)
  $NoJq = -not (Get-Command jq.exe -CommandType Application -ErrorAction Ignore)
}

Describe 'Git Bash で動くもの' -Skip:$NoBash {
  BeforeAll {
    $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    # Claude Code と同じく / 区切りのパスで呼ぶ
    $RootFwd = $Root -replace '\\', '/'
    . (Join-Path $Root 'windows\gitbash-lib.ps1')
    $Bash = Get-GitBash
    $Git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    $Pwsh = (Get-Command pwsh -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
    if (-not $Pwsh) { $Pwsh = [Environment]::ProcessPath }
    $Utf8 = [Text.UTF8Encoding]::new($false)
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
    # TestDrive は Pester が Remove-Item -Recurse で消すので、リンクを置く一時ディレクトリは自分で作って自分で消す
    $Tmp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-posix-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $Tmp
    $RootPosix = (Invoke-Proc $Bash @('-c', 'cygpath -u "$1"', '_', $Root)).Out.TrimEnd("`n")
  }
  AfterAll {
    if ($Tmp) { Remove-TreeSafe $Tmp }
  }

  Context 'posix/hook env' {
    BeforeAll {
      $EnvFile = Join-Path $Tmp 'claude-env'
      $EnvLines = ('export PATH="' + "$RootPosix/windows/posix/shims:$RootPosix/bin:/c/lad/mise/shims:" + '$PATH"') + "`n" +
        'export MSYS2_ARG_CONV_EXCL="/clear${MSYS2_ARG_CONV_EXCL:+;$MSYS2_ARG_CONV_EXCL}"' + "`n"
    }
    It 'CLAUDE_ENV_FILE に dotfiles の shims と bin と mise の shims を PATH の先頭に置く行と /clear の除外を足す（$ はそのまま、CR なし）' {
      [IO.File]::WriteAllText($EnvFile, "export FOO=1`n", $Utf8)
      $r = Invoke-Proc $Bash @("$RootFwd/windows/posix/hook", 'env') -InputText '{"session_id":"x"}' -Environment @{ CLAUDE_ENV_FILE = $EnvFile; LOCALAPPDATA = 'C:\lad' } -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
      [IO.File]::ReadAllText($EnvFile, $Utf8) | Should -BeExactly "export FOO=1`n$EnvLines"
    }
    It '2 回目は同じ行を重ねない' {
      $r = Invoke-Proc $Bash @("$RootFwd/windows/posix/hook", 'env') -InputText '{}' -Environment @{ CLAUDE_ENV_FILE = $EnvFile; LOCALAPPDATA = 'C:\lad' } -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
      [IO.File]::ReadAllText($EnvFile, $Utf8) | Should -BeExactly "export FOO=1`n$EnvLines"
    }
    It '書いた行を読んだ Bash ツールでは、Windows の exe（git）に /clear がそのまま渡り、ほかの /c/... は直される' {
      $r = Invoke-Proc $Bash @('-c', '. "$1" && git rev-parse --sq-quote /clear /c/x', '_', ($EnvFile -replace '\\', '/')) -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
      $r.Out.Trim() | Should -BeExactly "'/clear' 'C:/x'"
    }
    It 'CLAUDE_ENV_FILE が無くても 0' {
      $r = Invoke-Proc $Bash @("$RootFwd/windows/posix/hook", 'env') -InputText '{}' -Environment @{ CLAUDE_ENV_FILE = $null; LOCALAPPDATA = 'C:\lad' } -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
    }
  }

  Context 'posix/shims/jq' -Skip:$NoJq {
    It 'jq.exe の出力に CR が無い' {
      $r = Invoke-Proc $Bash @('-c', 'printf ''{"a":[1,2]}'' | "$1" ".a[]"', '_', "$RootFwd/windows/posix/shims/jq") -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
      $r.Out | Should -BeExactly "1`n2`n"
    }
  }

  Context 'git/hooks-nosign/commit-msg' {
    BeforeAll {
      # tests/acceptance/git-nosign.sh と同じメッセージ（人の共同作者・本文の言及は残し、AI 由来の行は消す）
      $Msg = @(
        'fix token check'
        ''
        'Keeps the expiry check testable.'
        'Fixtures generated with Claude Code are checked by hand.'
        'See https://claude.ai/code/session_0123abc for the failing run.'
        ''
        'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
        'Co-authored-by: Codex <noreply@openai.com>'
        'Co-Authored-By: Taro <taro@example.com>'
        'Co-Authored-By: Claude Martin <claude.martin@example.com>'
        'Claude-Session: https://claude.ai/code/session_0123abc'
        ''
        "$([char]::ConvertFromUtf32(0x1F916)) Generated with [Claude Code](https://claude.com/claude-code)"
        'Generated with Claude Code'
        'Generated with [Codex](https://openai.com/codex/).'
        'Generated with Codex.'
        ''
        'https://claude.ai/code/session_0123abc'
      ) -join "`n"
      $Want = @(
        'fix token check'
        ''
        'Keeps the expiry check testable.'
        'Fixtures generated with Claude Code are checked by hand.'
        'See https://claude.ai/code/session_0123abc for the failing run.'
        ''
        'Co-Authored-By: Taro <taro@example.com>'
        'Co-Authored-By: Claude Martin <claude.martin@example.com>'
      ) -join "`n"
      # 端末の ~/.gitconfig・システムの設定に左右されないよう、空の設定で動かす
      $EmptyConfig = Join-Path $Tmp 'empty-gitconfig'
      [IO.File]::WriteAllText($EmptyConfig, '')
      $GitEnv = @{
        GIT_CONFIG_GLOBAL = $EmptyConfig; GIT_CONFIG_NOSYSTEM = '1'
        GIT_AUTHOR_NAME = 't'; GIT_AUTHOR_EMAIL = 't@example.com'; GIT_COMMITTER_NAME = 't'; GIT_COMMITTER_EMAIL = 't@example.com'
        # Git for Windows の grep が絵文字に一致しないロケール（ラッパーが C にする）
        LC_ALL = 'C.UTF-8'
      }
      # ~/.config/git/hooks-nosign と同じく、windows/git/hooks-nosign へのディレクトリのリンクを hooksPath にする
      $Hooks = Join-Path $Tmp 'hooks-nosign'
      $null = [IO.Directory]::CreateSymbolicLink($Hooks, (Join-Path $Root 'windows\git\hooks-nosign'))
      $MsgFile = Join-Path $Tmp 'msg'
      [IO.File]::WriteAllText($MsgFile, "$Msg`n", $Utf8)
      function New-Repo([string]$Path, [string]$HooksPath) {
        (Invoke-Proc $Git @('init', '-q', '-b', 'main', $Path) -Environment $GitEnv).ExitCode | Should -Be 0
        if ($HooksPath) { (Invoke-Proc $Git @('-C', $Path, 'config', 'core.hooksPath', $HooksPath) -Environment $GitEnv).ExitCode | Should -Be 0 }
        $c = Invoke-Proc $Git @('-C', $Path, 'commit', '-q', '--allow-empty', '-F', $MsgFile) -Environment $GitEnv
        $c.ExitCode | Should -Be 0 -Because $c.Err
        (Invoke-Proc $Git @('-C', $Path, 'log', '-1', '--format=%B') -Environment $GitEnv).Out
      }
    }
    It 'リンク経由の hooksPath（<Style> 区切り）で、件名・本文・人の共同作者だけが残る' -ForEach @(@{ Style = '\' }, @{ Style = '/' }) {
      $hp = if ($Style -eq '/') { $Hooks -replace '\\', '/' } else { $Hooks }
      $got = New-Repo (Join-Path $Tmp "work$([guid]::NewGuid().ToString('N'))") $hp
      $got | Should -BeExactly "$Want`n`n"
      $got | Should -Not -Match 'Generated with \[Claude Code\]'
      $got | Should -Not -Match 'Co-Authored-By: Claude Opus'
    }
    It 'hooksPath が無ければ変わらない（比べる前提）' {
      $got = New-Repo (Join-Path $Tmp 'private') ''
      $got | Should -BeExactly "$Msg`n`n"
    }
  }

  Context 'posix/hook integrate-hook' {
    It 'pre-edit は git の外の Windows のパス（C:\...）で 0' {
      $d = Join-Path $Tmp 'outside'
      $null = New-Item -ItemType Directory -Path $d -Force
      $in = [ordered]@{
        session_id = 'x'; cwd = $d; hook_event_name = 'PreToolUse'; tool_name = 'Write'
        tool_input = [ordered]@{ file_path = (Join-Path $d 'sub\new.txt'); content = 'x' }
      } | ConvertTo-Json -Compress
      $r = Invoke-Proc $Bash @("$RootFwd/windows/posix/hook", 'integrate-hook', 'pre-edit') -InputText $in -WorkingDirectory $d
      $r.ExitCode | Should -Be 0 -Because $r.Err
    }
    Context 'cwd と編集するファイルのリポジトリが違う（jq.exe が要る）' -Skip:$NoJq {
      BeforeAll {
        # origin があって integrate setup の設定が無いリポジトリと、git の外のディレクトリ。設定の置き場所（~/.config/integrate）は空のホームにする
        $EmptyConfig2 = Join-Path $Tmp 'empty-gitconfig2'
        [IO.File]::WriteAllText($EmptyConfig2, '')
        $HookEnv = @{ GIT_CONFIG_GLOBAL = $EmptyConfig2; GIT_CONFIG_NOSYSTEM = '1'; HOME = ((Join-Path $Tmp 'ihome') -replace '\\', '/') }
        $null = New-Item -ItemType Directory -Path (Join-Path $Tmp 'ihome') -Force
        $Repo = Join-Path $Tmp 'unconfigured repo'
        (Invoke-Proc $Git @('init', '-q', $Repo) -Environment $HookEnv).ExitCode | Should -Be 0
        (Invoke-Proc $Git @('-C', $Repo, 'remote', 'add', 'origin', 'https://example.invalid/x.git') -Environment $HookEnv).ExitCode | Should -Be 0
        $Outside = Join-Path $Tmp 'outside2'
        $null = New-Item -ItemType Directory -Path $Outside -Force
        function Invoke-PreEdit([string]$Cwd, [string]$File) {
          $in = [ordered]@{
            session_id = 'x'; cwd = $Cwd; hook_event_name = 'PreToolUse'; tool_name = 'Write'
            tool_input = [ordered]@{ file_path = $File; content = 'x' }
          } | ConvertTo-Json -Compress
          Invoke-Proc $Bash @("$RootFwd/windows/posix/hook", 'integrate-hook', 'pre-edit') -InputText $in -Environment $HookEnv -WorkingDirectory $Cwd
        }
      }
      It 'git の外の cwd から、設定の無いリポジトリのファイル（C:\...）の編集は止める（2）' {
        $r = Invoke-PreEdit $Outside (Join-Path $Repo 'sub\a.txt')
        $r.ExitCode | Should -Be 2 -Because $r.Err
        $r.Err | Should -Match 'integrate setup'
      }
      It '設定の無いリポジトリの cwd から、git の外のファイルの編集は止めない（0）' {
        $r = Invoke-PreEdit $Repo (Join-Path $Outside 'b.txt')
        $r.ExitCode | Should -Be 0 -Because $r.Err
      }
    }
  }

  Context 'posix/run と posix/hook は handoff が herdr に送る /clear を Windows のパスに直させない' {
    BeforeAll {
      # run・hook は自分の場所からリポジトリを決めるので、偽のリポジトリに写して、引数を git（Windows の exe）に渡すだけの bin/argv を置く
      $Fake = Join-Path $Tmp 'fake'
      $null = New-Item -ItemType Directory -Path (Join-Path $Fake 'windows\posix'), (Join-Path $Fake 'bin') -Force
      Copy-Item -LiteralPath (Join-Path $Root 'windows\posix\run'), (Join-Path $Root 'windows\posix\hook') -Destination (Join-Path $Fake 'windows\posix')
      [IO.File]::WriteAllText((Join-Path $Fake 'bin\argv'), "#!/bin/sh`nexec git rev-parse --sq-quote `"`$@`"`n", $Utf8)
      $FakeFwd = $Fake -replace '\\', '/'
    }
    It '<Script> argv /clear /c/x は ''/clear'' ''C:/x'' を渡す' -ForEach @(@{ Script = 'run' }, @{ Script = 'hook' }) {
      $r = Invoke-Proc $Bash @("$FakeFwd/windows/posix/$Script", 'argv', '/clear', '/c/x') -Environment @{ MSYS2_ARG_CONV_EXCL = $null } -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
      $r.Out.Trim() | Should -BeExactly "'/clear' 'C:/x'"
    }
  }

  Context 'posix/run と windows/bin/*.cmd' {
    It 'run は名前が <Name> なら終了コード 2' -ForEach @(@{ Name = '（なし）'; A = @() }, @{ Name = 'Bad_Name'; A = @('Bad_Name') }, @{ Name = 'no-such-command'; A = @('no-such-command') }) {
      $r = Invoke-Proc $Bash (@("$RootFwd/windows/posix/run") + $A) -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 2
    }
    It 'codex-review.cmd は引数なしで bin/codex-review の usage と終了コード 2 を返す' {
      $r = Invoke-Proc (Join-Path $env:SystemRoot 'System32\cmd.exe') @('/d', '/c', (Join-Path $Root 'windows\bin\codex-review.cmd')) -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 2
      $r.Err | Should -Match 'usage: codex-review'
    }
    It '<Name>.cmd には pwsh 用の <Name>.ps1 が並んでいる' -ForEach @(Get-ChildItem -LiteralPath (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'windows\bin') -Filter *.cmd | ForEach-Object { @{ Name = $_.BaseName } }) {
      Test-Path -LiteralPath (Join-Path $Root "windows\bin\$Name.ps1") -PathType Leaf | Should -BeTrue
    }
    It 'codex-review.ps1 は引数なしで bin/codex-review の usage と終了コード 2 を返す' {
      $r = Invoke-Proc $Pwsh @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Root 'windows\bin\codex-review.ps1')) -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 2
      $r.Err | Should -Match 'usage: codex-review'
    }
    It 'notify.ps1 は " & | ^ % 空白・日本語を含む引数をそのまま渡す' {
      $state = Join-Path $Tmp 'state'
      $a = @('say "hi" there', 'a&b', 'x|y', 'p^q', '50%', '日本語 です')
      $r = Invoke-Proc $Pwsh (@('-NoProfile', '-NonInteractive', '-File', (Join-Path $Root 'windows\bin\notify.ps1')) + $a) -Environment @{ XDG_STATE_HOME = $state } -WorkingDirectory $Tmp
      $r.ExitCode | Should -Be 0 -Because $r.Err
      $log = [IO.File]::ReadAllText((Join-Path $state 'agent-notify.log'), $Utf8)
      $log | Should -Match ('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d ' + [regex]::Escape($a -join ' ') + "`n$")
    }
  }
}
