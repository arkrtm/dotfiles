#Requires -Version 7.4
# Git for Windows の場所を探す関数（windows/bin/*.ps1・install.ps1・テストが dot-source する。読み込むだけでは何も変えない）。
# Git は Program Files に入るとは限らない（ユーザー単位の %LOCALAPPDATA%\Programs\Git など）ので、PATH の git.exe の場所から辿る。
# windows/bin/*.cmd 用の同じ探し方は gitbash-lib.cmd

# Git のルート（bin\bash.exe がある所）。無ければ $null。
# git.exe は <ルート>\cmd・<ルート>\bin・<ルート>\mingw64\bin・<ルート>\ucrt64\bin にいるので、その 1 つ上と 2 つ上を試す。見つからなければ標準の場所
function Get-GitRoot {
  $candidates = [Collections.Generic.List[string]]::new()
  $git = Get-Command git.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1
  if ($git) {
    $dir = Split-Path -Parent $git.Source
    foreach ($up in 1, 2) {
      $dir = if ($dir) { Split-Path -Parent $dir }
      if ($dir) { $candidates.Add($dir) }
    }
  }
  foreach ($base in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
    if ($base) { $candidates.Add((Join-Path $base 'Git')) }
  }
  if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git')) }
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath (Join-Path $c 'bin\bash.exe') -PathType Leaf) { return $c }
  }
}

# Git Bash の bash.exe のパス。無ければ $null（-Required なら例外）
function Get-GitBash {
  param([switch]$Required)
  $root = Get-GitRoot
  if ($root) { return Join-Path $root 'bin\bash.exe' }
  if ($Required) { throw 'Git for Windows の bash.exe が見つからない（git.exe を PATH に入れるか、Git for Windows を入れる）' }
}
