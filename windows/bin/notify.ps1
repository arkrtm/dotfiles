#Requires -Version 7.4
# pwsh から bin/notify を動かす（同じ場所の notify.cmd より先に選ばれる。cmd.exe を通さないので " ^ & | % を含む引数もそのまま渡る）。Git Bash は git.exe の場所から探す
$PSNativeCommandArgumentPassing = 'Standard'
. (Join-Path $PSScriptRoot '..\gitbash-lib.ps1')
$run = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\posix\run')) -replace '\\', '/'
& (Get-GitBash -Required) $run notify @args
exit $LASTEXITCODE
