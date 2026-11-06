#Requires -Version 7
# pwsh から bin/codex-review を動かす（同じ場所の codex-review.cmd より先に選ばれる。cmd.exe を通さないので " ^ & | % を含む引数もそのまま渡る）
$PSNativeCommandArgumentPassing = 'Standard'
$run = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\posix\run')) -replace '\\', '/'
& (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') $run codex-review @args
exit $LASTEXITCODE
