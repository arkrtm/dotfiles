#Requires -Version 7
# pwsh から bin/handoff を動かす（同じ場所の handoff.cmd より先に選ばれる。cmd.exe を通さないので " ^ & | % を含む引数もそのまま渡る）
$PSNativeCommandArgumentPassing = 'Standard'
$run = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\posix\run')) -replace '\\', '/'
& (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') $run handoff @args
exit $LASTEXITCODE
