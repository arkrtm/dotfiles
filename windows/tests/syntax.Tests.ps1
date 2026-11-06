#Requires -Version 7.4
# windows/ のファイルの構文・文字コード・改行: .ps1 は構文エラーが無く BOM 付き UTF-8 で #Requires -Version 7.4 から始まる。.json は厳密な JSON。
# シェルスクリプトは Git Bash の sh -n（dash があれば dash -n）・bash -n を通る（Git Bash が無ければ飛ばす）。.cmd は CRLF、ほかは LF だけ

BeforeDiscovery {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $Win = Join-Path $Root 'windows'
  $all = @(Get-ChildItem -LiteralPath $Win -Recurse -File -Force | ForEach-Object {
      @{ Rel = [IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/'; Path = $_.FullName; Ext = $_.Extension.ToLowerInvariant() }
    })
  $Ps1 = @($all | Where-Object { $_.Ext -eq '.ps1' })
  $Json = @($all | Where-Object { $_.Ext -eq '.json' })
  $Cmd = @($all | Where-Object { $_.Ext -eq '.cmd' })
  $Other = @($all | Where-Object { $_.Ext -ne '.cmd' })
  # 先頭が #! のファイル（シェルスクリプト）と、windows/posix・windows/git の下のファイル（シェルスクリプトのはず）
  $Shell = @($all | Where-Object {
      $_.Rel -like 'windows/posix/*' -or $_.Rel -like 'windows/git/*' -or ([IO.File]::ReadAllText($_.Path).StartsWith('#!'))
    })
  . (Join-Path $Win 'gitbash-lib.ps1')
  $NoBash = -not (Get-GitBash)
}

BeforeAll {
  . (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'windows\gitbash-lib.ps1')
  $Bash = Get-GitBash
  $Utf8Strict = [Text.UTF8Encoding]::new($false, $true)
  function Get-Bytes([string]$Path) { [IO.File]::ReadAllBytes($Path) }
  function Test-Bom([byte[]]$b) { $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF }
}

Describe 'PowerShell のスクリプト' {
  It '<Rel> は構文エラーが無い' -ForEach $Ps1 {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    @($errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty
  }
  It '<Rel> は BOM 付き UTF-8 で #Requires -Version 7.4 から始まる' -ForEach $Ps1 {
    $b = Get-Bytes $Path
    Test-Bom $b | Should -BeTrue
    $text = $Utf8Strict.GetString($b, 3, $b.Length - 3)
    ($text -split "`n", 2)[0] | Should -BeExactly '#Requires -Version 7.4'
  }
}

Describe 'JSON' {
  It '<Rel> は厳密な JSON として読める（コメント・末尾のカンマが無い）' -ForEach $Json {
    $text = $Utf8Strict.GetString((Get-Bytes $Path))
    { $d = [Text.Json.JsonDocument]::Parse($text); $d.Dispose() } | Should -Not -Throw
  }
}

Describe '文字コードと改行' {
  It '<Rel> は UTF-8 として正しく、CR が無く、LF で終わる' -ForEach $Other {
    $b = Get-Bytes $Path
    { $Utf8Strict.GetString($b) } | Should -Not -Throw
    [Array]::IndexOf($b, [byte]13) | Should -Be -1
    $b[-1] | Should -Be 10
  }
  It '<Rel> は .ps1 でなければ BOM が無い' -ForEach $Other {
    if ($Ext -ne '.ps1') { Test-Bom (Get-Bytes $Path) | Should -BeFalse }
  }
  It '<Rel> は CRLF だけで BOM が無い' -ForEach $Cmd {
    $b = Get-Bytes $Path
    Test-Bom $b | Should -BeFalse
    $text = $Utf8Strict.GetString($b)
    $text | Should -Match "\r\n$"
    ($text -replace "`r`n", '') | Should -Not -Match '[\r\n]'
  }
  It '<Rel> は sh・bash のシバンで始まらない' -ForEach @($Ps1 + $Json + $Cmd + @($Other | Where-Object { $_.Ext -eq '.md' })) {
    $first = ($Utf8Strict.GetString((Get-Bytes $Path)).TrimStart([char]0xFEFF) -split "`n", 2)[0]
    $first | Should -Not -BeLike '#!/bin/sh*'
    $first | Should -Not -BeLike '#!/usr/bin/env bash*'
  }
}

Describe 'シェルスクリプト' -Skip:$NoBash {
  It '<Rel> は #!/bin/sh か #!/usr/bin/env bash で始まり、構文検査を通る' -ForEach $Shell {
    $first = ([IO.File]::ReadAllText($Path) -split "`n", 2)[0]
    $first | Should -BeIn @('#!/bin/sh', '#!/usr/bin/env bash')
    $p = $Path -replace '\\', '/'
    if ($first -eq '#!/bin/sh') {
      # ubuntu の CI は dash -n で見るので、Git Bash に dash があればそれで見る
      $out = & $Bash -c 'if command -v dash >/dev/null 2>&1; then dash -n "$1"; else sh -n "$1"; fi' _ $p 2>&1
    } else {
      $out = & $Bash -n $p 2>&1
    }
    $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
  }
}
