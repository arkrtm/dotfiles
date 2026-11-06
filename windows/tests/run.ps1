#Requires -Version 7.4
# windows/ の検査（Pester 5 以上）。ネットワークを使わず、本物のホームに触らない（一時ホームと TestDrive だけ）
#   pwsh -NoProfile -File windows/tests/run.ps1
$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
$OutputEncoding = [Text.UTF8Encoding]::new($false)

try { Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop }
catch {
  [Console]::Error.WriteLine('run.ps1: Pester 5 以上が無い。入れる: Install-PSResource Pester -Scope CurrentUser')
  exit 1
}

# 古いプロセスから起動されると Path に git が無いことがあるので、レジストリの Machine と User の Path から足りない分を後ろに足す
$reg = foreach ($scope in 'Machine', 'User') { [Environment]::GetEnvironmentVariable('Path', $scope) -split ';' }
$env:Path = (@($env:Path -split ';') + @($reg) | Where-Object { $_ } | Select-Object -Unique -CaseInsensitive) -join ';'

# 結果のファイル（testResults.xml）は書かない（リポジトリに残るため）
$c = New-PesterConfiguration
$c.Run.Path = $PSScriptRoot
$c.Run.PassThru = $true
$c.Output.Verbosity = 'Detailed'
$c.TestResult.Enabled = $false
$c.CodeCoverage.Enabled = $false
$r = Invoke-Pester -Configuration $c
if ($r.Result -ne 'Passed' -or $r.FailedCount -gt 0) { exit 1 }
exit 0
