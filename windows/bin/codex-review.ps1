#Requires -Version 7.4
# pwsh から bin/codex-review を動かす（同じ場所の codex-review.cmd より先に選ばれる。cmd.exe を通さないので " ^ & | % を含む引数もそのまま渡る）。Git Bash は git.exe の場所から探す
$PSNativeCommandArgumentPassing = 'Standard'
. (Join-Path $PSScriptRoot '..\gitbash-lib.ps1')
$run = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\posix\run')) -replace '\\', '/'
& (Get-GitBash -Required) $run codex-review @args
exit $LASTEXITCODE
