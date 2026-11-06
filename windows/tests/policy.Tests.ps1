#Requires -Version 7.4
# リポジトリ全体の決まり（ubuntu の CI の tests/static.sh・tests/acceptance/claude-config.sh と bin/integrate が見るもの）を、新しいファイルに先に当てる。
# 既存の追跡しているファイルを変えていないこと、windows/ と .github/workflows/windows.yml の外にファイルを足していないこと
# （このファイル自身も検査の対象なので、禁止の文字列は [ ] で崩して書く）

BeforeDiscovery {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'windows') -Recurse -File -Force)
  $wf = Join-Path $Root '.github\workflows\windows.yml'
  if (Test-Path -LiteralPath $wf) { $files += Get-Item -LiteralPath $wf }
  $New = @($files | ForEach-Object { @{ Rel = [IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/'; Path = $_.FullName } })
}

BeforeAll {
  $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  function Invoke-Git { & git -C $Root -c core.quotePath=false @args }
  # Pester 5 は BeforeDiscovery の変数を It の中（実行時）に渡さないので、実行時に使うものはここで定義する
  # 大文字小文字を区別する正規表現
  $Patterns = @(
    @{ Name = 'issue の番号'; Re = 'AR[K]-[0-9]' }
    @{ Name = 'claude-config.sh の禁止語 1'; Re = '\b[P]i\b' }
    @{ Name = 'claude-config.sh の禁止語 2'; Re = '\.p[i]/' }
    @{ Name = 'claude-config.sh の禁止語 3'; Re = 'bigpower[s]' }
    @{ Name = 'claude-config.sh の禁止語 4'; Re = '/skil[l]:' }
    @{ Name = 'claude-config.sh の禁止語 5'; Re = 'pi-tinymemor[y]' }
    @{ Name = 'claude-config.sh の禁止語 6'; Re = 'yamlfi[x]' }
    @{ Name = 'claude-config.sh の禁止語 7'; Re = 'ask_user_questio[n]' }
    @{ Name = 'integrate の検査の抑止 1'; Re = 'noq[a]' }
    @{ Name = 'integrate の検査の抑止 2'; Re = 'type: *ignor[e]' }
    @{ Name = 'integrate の検査の抑止 3'; Re = 'pytest\.mark\.(ski[p]|xfai[l])' }
    @{ Name = 'integrate の検査の抑止 4'; Re = 'unittest\.ski[p]' }
  )
  function Find-Forbidden([string]$Text) {
    foreach ($p in $Patterns) {
      foreach ($m in [regex]::Matches($Text, $p.Re)) { "$($p.Name): $($m.Value)" }
    }
  }
}

Describe '禁止の文字列' {
  It '<Rel> に禁止の文字列が無い' -ForEach $New {
    # git grep は -I なしでバイナリも見るので、バイト列をそのまま文字列にして見る
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path))
    @(Find-Forbidden $text) | Should -BeNullOrEmpty
  }
}

Describe '禁止の文字列の検査そのもの' {
  It 'パターンが実行時に読み込まれている' {
    $Patterns.Count | Should -Be 12
  }
  It '禁止の文字列を含む文字列はパターンごとに検出される（ファイルに書かないよう実行時に組み立てる）' {
    $samples = @(
      ('AR' + 'K-1')
      ('a P' + 'i b')
      ('.p' + 'i/')
      ('bigpower' + 's')
      ('/skil' + 'l:')
      ('pi-tinymemor' + 'y')
      ('yamlfi' + 'x')
      ('ask_user_questio' + 'n')
      ('noq' + 'a')
      ('type: ig' + 'nore')
      ('pytest.mark.ski' + 'p')
      ('unittest.ski' + 'p')
    )
    $samples.Count | Should -Be $Patterns.Count
    for ($i = 0; $i -lt $samples.Count; $i++) {
      $hits = @(Find-Forbidden $samples[$i])
      $hits | Should -Not -BeNullOrEmpty -Because $Patterns[$i].Name
      $hits[0] | Should -BeLike "$($Patterns[$i].Name): *"
    }
  }
  It '普通の文字列は検出されない' {
    @(Find-Forbidden 'windows/bin/notify.cmd を呼ぶ') | Should -BeNullOrEmpty
  }
}

Describe 'ファイル名' {
  It '<Rel> は ASCII で空白が無い' -ForEach $New {
    $Rel | Should -MatchExactly '^[\x21-\x7e]+$'
  }
  It '<Rel> は退避・ログ・ビルドの残り物でない' -ForEach $New {
    $Rel | Should -Not -Match '\.bak\.\d{14}$|\.log$|\.pyc$|(^|/)(__pycache__|build|dist|\.venv)/|\.egg-info(/|$)|testResults\.xml$|\.partial$'
  }
}

Describe 'git の作業ツリー' {
  It '既存の追跡しているファイルは変わっていない（windows/ と windows.yml の外）' {
    $diff = Invoke-Git diff --name-status HEAD -- . ':!windows' ':!.github/workflows/windows.yml'
    $LASTEXITCODE | Should -Be 0
    @($diff) | Should -BeNullOrEmpty
  }
  It '追跡していないファイルは windows/ と .github/workflows/windows.yml だけ' {
    $st = Invoke-Git status --porcelain --untracked-files=all
    $LASTEXITCODE | Should -Be 0
    $stray = @($st | Where-Object { $_ } | ForEach-Object { $_.Substring(3).Trim('"') } |
        Where-Object { -not ($_.StartsWith('windows/') -or $_ -eq '.github/workflows/windows.yml') })
    $stray | Should -BeNullOrEmpty
  }
  It 'windows/.gitattributes で .cmd は CRLF、ほかは LF で取り出す' {
    $a = Invoke-Git check-attr eol -- windows/bin/notify.cmd windows/posix/run windows/install.ps1
    $a | Should -Be @('windows/bin/notify.cmd: eol: crlf', 'windows/posix/run: eol: lf', 'windows/install.ps1: eol: lf')
  }
}
