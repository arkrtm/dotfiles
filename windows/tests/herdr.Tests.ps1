#Requires -Version 7.4
# windows/herdr/config.toml は config/herdr/config.toml と最後のブロック（kitty の画像）より前が同じで、[terminal] の kitty_graphics = false で終わる

BeforeAll {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $Utf8 = [Text.UTF8Encoding]::new($false)
  # 共通のファイルは Windows の取り出し方（core.autocrlf）で CRLF になり得るので LF にそろえて比べる。Windows 用は LF で取り出す
  $Shared = [IO.File]::ReadAllText((Join-Path $Root 'config\herdr\config.toml'), $Utf8) -replace "`r`n", "`n"
  $Win = [IO.File]::ReadAllText((Join-Path $Root 'windows\herdr\config.toml'), $Utf8)
  $SharedLines = $Shared.TrimEnd("`n") -split "`n"
  # 共通のファイルの最後のブロック: コメント 1 行 + [experimental] + kitty_graphics = true
  $Cut = $SharedLines.Count - 3
  $Prefix = (($SharedLines[0..($Cut - 1)]) -join "`n") + "`n"
}

Describe 'windows/herdr/config.toml' {
  It '共通のファイルは kitty の画像のブロックで終わる（比べる前提）' {
    $SharedLines[$Cut] | Should -Match '^# '
    $SharedLines[$Cut + 1] | Should -BeExactly '[experimental]'
    $SharedLines[$Cut + 2] | Should -BeExactly 'kitty_graphics = true'
  }
  It 'kitty のブロックより前は共通のファイルと同じ' {
    $Win.StartsWith($Prefix, [StringComparison]::Ordinal) | Should -BeTrue
  }
  It '最後はコメント 1 行と [terminal] / kitty_graphics = false だけ（LF で終わる）' {
    $Win | Should -Not -Match "`r"
    $Win.EndsWith("`n") | Should -BeTrue
    $rest = $Win.Substring($Prefix.Length).TrimEnd("`n") -split "`n"
    $rest.Count | Should -Be 3
    $rest[0] | Should -Match '^# .*Windows Terminal'
    $rest[1] | Should -BeExactly '[terminal]'
    $rest[2] | Should -BeExactly 'kitty_graphics = false'
  }
}
