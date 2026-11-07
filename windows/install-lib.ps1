#Requires -Version 7.4
# install.ps1 とテストが dot-source する関数（読み込むだけでは何も変えない）

# 退避の名前に付ける時刻（install.sh の date +%Y%m%d%H%M%S と同じ形）
function Get-BackupStamp { Get-Date -Format 'yyyyMMddHHmmss' }

# リンク先の比較用: 区切りを \ に揃え、\\?\ と末尾の \ を外して絶対パスにする
function ConvertTo-ComparablePath {
  param([Parameter(Mandatory)][string]$Path, [string]$BaseDir)
  $p = $Path -replace '/', '\'
  if ($p.StartsWith('\\?\UNC\')) { $p = '\\' + $p.Substring(8) }
  elseif ($p.StartsWith('\\?\')) { $p = $p.Substring(4) }
  if (-not [IO.Path]::IsPathRooted($p) -and $BaseDir) { $p = Join-Path $BaseDir $p }
  [IO.Path]::GetFullPath($p).TrimEnd('\')
}

# パスそのもの（リンクなら辿らない）の情報。無ければ $null（壊れたリンクも「ある」）
function Get-PathEntry {
  param([Parameter(Mandatory)][string]$Path)
  try { $attr = [IO.File]::GetAttributes($Path) } catch { return $null }
  $isDir = $attr.HasFlag([IO.FileAttributes]::Directory)
  $info = if ($isDir) { [IO.DirectoryInfo]::new($Path) } else { [IO.FileInfo]::new($Path) }
  $target = if ($attr.HasFlag([IO.FileAttributes]::ReparsePoint)) { $info.LinkTarget } else { $null }
  [pscustomobject]@{ IsDir = $isDir; Target = $target; Info = $info }
}

# シンボリックリンクを作れるか（開発者モードか管理者）。一時ディレクトリで試して片づける
function Test-SymlinkSupport {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-symlink-' + [guid]::NewGuid().ToString('N'))
  try {
    $null = New-Item -ItemType Directory -Path $dir
    $src = Join-Path $dir 'src'
    [IO.File]::WriteAllText($src, '')
    $null = [IO.File]::CreateSymbolicLink((Join-Path $dir 'link'), $src)
    $true
  } catch {
    $false
  } finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# install.sh の link() と同じ: 同じ先を指すリンクなら何もしない。ほかに何かあれば .bak.<時刻> に退避してからリンクする。
# リンク元がまだ無いときは -Directory でディレクトリのリンクにする（Windows はファイルとディレクトリでリンクの種類が違う）
function Link-Item {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,
    [switch]$Directory
  )
  $srcExists = Test-Path -LiteralPath $Source
  $isDir = if ($srcExists) { Test-Path -LiteralPath $Source -PathType Container } else { [bool]$Directory }
  if (-not $srcExists) { Write-Host "warning: リンク元が無い（リンクだけ作る）: $Source" }
  $parent = Split-Path -Parent $Destination
  if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }

  $entry = Get-PathEntry $Destination
  if ($entry -and $entry.Target) {
    $current = ConvertTo-ComparablePath $entry.Target -BaseDir $parent
    $wanted = ConvertTo-ComparablePath $Source
    if ($current -ieq $wanted -and $entry.IsDir -eq $isDir) { return }
  }
  if ($entry) {
    $bak = "$Destination.bak.$(Get-BackupStamp)"
    $entry.Info.MoveTo($bak)
    Write-Host "backup: $Destination -> $bak"
  }
  if ($isDir) { $null = [IO.Directory]::CreateSymbolicLink($Destination, $Source) }
  else { $null = [IO.File]::CreateSymbolicLink($Destination, $Source) }
  Write-Host "link:   $Destination -> $Source"
}

# 環境変数の変更を開いているプログラム（エクスプローラー経由で起動するもの）に知らせる。
# .NET の SetEnvironmentVariable は User を書くと WM_SETTINGCHANGE を送るので、無い変数を消して送らせる
function Send-EnvironmentChange {
  [Environment]::SetEnvironmentVariable('DOTFILES_ENV_REFRESH', $null, 'User')
}

function Open-UserEnvironmentKey {
  [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
}

# パスの頭をなるべく %LOCALAPPDATA% / %USERPROFILE% に戻す（ユーザー名が変わっても使えるように）
function ConvertTo-EnvRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  foreach ($name in 'LOCALAPPDATA', 'USERPROFILE') {
    $base = [Environment]::GetEnvironmentVariable($name)
    if ($base -and ($Path -ieq $base -or $Path.StartsWith("$base\", [StringComparison]::OrdinalIgnoreCase))) {
      return "%$name%" + $Path.Substring($base.Length)
    }
  }
  $Path
}

# HKCU\Environment に書く（% を含めば REG_EXPAND_SZ）。今のプロセスにも展開して入れる。変わったら $true
function Set-UserEnv {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
  $kind = if ($Value.Contains('%')) { [Microsoft.Win32.RegistryValueKind]::ExpandString } else { [Microsoft.Win32.RegistryValueKind]::String }
  $key = Open-UserEnvironmentKey
  $changed = $false
  try {
    $old = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $oldKind = if ($null -ne $old) { $key.GetValueKind($Name) } else { $null }
    if ($old -cne $Value -or $oldKind -ne $kind) {
      $key.SetValue($Name, $Value, $kind)
      $changed = $true
    }
  } finally { $key.Dispose() }
  Set-Item -LiteralPath "env:$Name" -Value ([Environment]::ExpandEnvironmentVariables($Value))
  if ($changed) { Send-EnvironmentChange }
  $changed
}

# ユーザーの Path の先頭に順に入れる（大文字小文字を区別せず、展開後の形で重複を除く）。生の値を読み、REG_EXPAND_SZ で書く
function Add-UserPath {
  param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Dir)
  $keyOf = { param($p) [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\').ToLowerInvariant() }
  $key = Open-UserEnvironmentKey
  $changed = $false
  try {
    $raw = $key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $oldKind = if ($null -ne $raw) { $key.GetValueKind('Path') } else { $null }
    $seen = [Collections.Generic.HashSet[string]]::new()
    $list = foreach ($p in @($Dir) + @(([string]$raw) -split ';')) {
      if ([string]::IsNullOrWhiteSpace($p)) { continue }
      if ($seen.Add((& $keyOf $p))) { $p }
    }
    $new = @($list) -join ';'
    if ($new -cne $raw -or $oldKind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) {
      $key.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
      $changed = $true
    }
  } finally { $key.Dispose() }
  $expanded = @($Dir | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
  $env:Path = (@($expanded) + @($env:Path -split ';') | Where-Object { $_ } | Select-Object -Unique -CaseInsensitive) -join ';'
  if ($changed) { Send-EnvironmentChange }
  $changed
}

# 古いプロセスから起動されると Path が古い（git や gh が見えない）ので、レジストリの Machine と User の Path から足りない分を後ろに足す
function Update-ProcessPath {
  $reg = foreach ($scope in 'Machine', 'User') { [Environment]::GetEnvironmentVariable('Path', $scope) -split ';' }
  $env:Path = (@($env:Path -split ';') + @($reg) | Where-Object { $_ } | Select-Object -Unique -CaseInsensitive) -join ';'
}

# 失敗した手順を名前と理由で記録し、warning を出す（手順は続ける）
function Add-StepFailure {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Log,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Reason
  )
  $Log.Add([pscustomobject]@{ Name = $Name; Reason = $Reason })
  Write-Host "warning: ${Name}: ${Reason}（続行）"
}

# 手順を動かす。例外は記録して外に出さず、次の手順へ進む。本体は呼び出し側の変数を読む（引数と同じ名前の Log・Name・Body は引数が見える）
function Invoke-Step {
  param(
    [Parameter(Mandatory, Position = 0)][AllowEmptyCollection()][Collections.Generic.List[object]]$Log,
    [Parameter(Mandatory, Position = 1)][string]$Name,
    [Parameter(Mandatory, Position = 2)][scriptblock]$Body
  )
  try { & $Body } catch { Add-StepFailure $Log $Name $_.Exception.Message }
}

# 最後の表示と終了コード。失敗の一覧があれば done. を出さず 1、無ければ done. と案内を出して 0
function Complete-Install {
  param([Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Log)
  if ($Log.Count -gt 0) {
    Write-Host '失敗した手順（理由を直して install.ps1 を再実行する）:'
    foreach ($f in $Log) { Write-Host "- $($f.Name): $($f.Reason)" }
    return [int]1
  }
  Write-Host 'done.'
  Write-Host '残りの手順: windows/README.md の「新しい PC での導入」の install.ps1 より後'
  [int]0
}

# CRLF で取り出された追跡ファイル（取り出し直せば LF になるもの: index は LF、作業ツリーは CRLF）。
# 属性で CRLF を求めるもの（windows/.gitattributes の *.cmd text eol=crlf）は CRLF が正しいので除く
function Get-CrlfCheckout {
  param([Parameter(Mandatory)][string]$Repo)
  $out = git -C $Repo ls-files --eol -z
  if ($LASTEXITCODE) { throw 'git ls-files に失敗' }
  @((@($out) -join "`n") -split "`0" | ForEach-Object {
      $info, $path = $_ -split "`t", 2
      if ($path -and $info -match '\bi/lf\b' -and $info -match '\bw/crlf\b' -and $info -notmatch '\beol=crlf\b') { $path }
    })
}

# 指定した追跡ファイル（Get-CrlfCheckout の結果）だけを LF で書き直す。ファイルは消さない（git の設定のリンク先も追跡ファイルで、消すと git が動かなくなる）。
# 索引は読み直さず空にもしない（途中で失敗しても追跡の一覧とフラグが残り、再実行で直る）。skip-worktree・assume-unchanged のファイルは
# 手元の編集を持つかもしれない（git status に出ない）ので書き直さない。stat が索引と合うファイルは --force でも書き直されないので、
# 更新時刻を今の値より 1 日古くして（失敗の後に git status が索引へ書いた値とも違う。git for Windows の stat は秒単位）合わなくしてから checkout-index で書き直す（-u で stat も更新する）。
# checkout-index は 1 つでも失敗すると索引を書かないので 1 ファイルずつ呼ぶ（書き直せたファイルの stat を索引に残し、git status を空に保つ）
function Repair-LfCheckout {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Path)
  $v = git -C $Root ls-files -v -z
  if ($LASTEXITCODE) { throw 'git ls-files に失敗' }
  # 先頭の 1 文字が H 以外（S: skip-worktree、小文字: assume-unchanged など）のファイルは対象にしない
  $held = @((@($v) -join "`n") -split "`0" | Where-Object { $_.Length -gt 2 -and $_[0] -cne 'H' } | ForEach-Object { $_.Substring(2) })
  $targets = @($Path | Where-Object { $_ -and $_ -notin $held })
  if ($targets.Count -eq 0) { return }
  $failed = foreach ($p in $targets) {
    $full = Join-Path $Root $p
    [IO.File]::SetLastWriteTimeUtc($full, [IO.File]::GetLastWriteTimeUtc($full).AddDays(-1))
    git -C $Root checkout-index --force -u -- $p
    if ($LASTEXITCODE) { $p }
  }
  if ($failed) { throw "git checkout-index に失敗: $(@($failed) -join ', ')" }
}

# 自分・SYSTEM・Administrators 以外で書き込める主体の SID（OpenSSH は他人が書ける設定ファイルを拒否する）
function Get-UnsafeWriter {
  param([Parameter(Mandatory)][string]$Path)
  $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
  # WriteData・AppendData・ChangePermissions・TakeOwnership・GENERIC_ALL・GENERIC_WRITE
  $writeMask = 0x2 -bor 0x4 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
  $rules = (Get-Acl -LiteralPath $Path).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])
  @($rules | Where-Object {
      $_.AccessControlType -eq 'Allow' -and ([long]$_.FileSystemRights -band $writeMask) -and $_.IdentityReference.Value -notin $allowed
    } | ForEach-Object { $_.IdentityReference.Value } | Select-Object -Unique)
}

# TOML の基本文字列の中身のエスケープ（\b \t \n \f \r \" \\ \uXXXX \UXXXXXXXX。ほかは不正）を実際の文字にする
function ConvertFrom-TomlEscape {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  $map = @{ b = "`b"; t = "`t"; n = "`n"; f = "`f"; r = "`r"; '"' = '"'; '\' = '\' }
  [regex]::Replace($Text, '\\(?:u(?<s>[0-9A-Fa-f]{4})|U(?<l>[0-9A-Fa-f]{8})|(?<c>.))', {
      param($m)
      if ($m.Groups['s'].Success -or $m.Groups['l'].Success) {
        $hex = $m.Groups['s'].Value + $m.Groups['l'].Value
        try { [char]::ConvertFromUtf32([Convert]::ToInt32($hex, 16)) } catch { throw "config.toml のキーに不正なエスケープがある（書かない）: $($m.Value)" }
      }
      elseif ($map.ContainsKey($m.Groups['c'].Value)) { $map[$m.Groups['c'].Value] }
      else { throw "config.toml のキーに不正なエスケープがある（書かない）: $($m.Value)" }
    })
}

# TOML のキー（a."b.c".'d'。ドットの前後の空白可）を部分に分けて正規化し、NUL でつなぐ。引用符と空白の書き方が違っても同じキーなら同じ文字列になり、違うキーなら違う文字列になる
function ConvertTo-TomlKeyPath {
  param([Parameter(Mandatory)][string]$Text)
  $parts = foreach ($m in [regex]::Matches($Text, '[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|''[^'']*''')) {
    $v = $m.Value
    $p = if ($v[0] -ceq [char]'"') { ConvertFrom-TomlEscape $v.Substring(1, $v.Length - 2) }
    elseif ($v[0] -ceq [char]"'") { $v.Substring(1, $v.Length - 2) }
    else { $v }
    # つなぎ目の NUL・Assert-TomlUnique の印（U+0001）と混ざらないよう部分の中の \ NUL U+0001 をエスケープし、空の部分は \e にする（空の名前はトップレベルを表す）
    $p = $p.Replace('\', '\\').Replace([string][char]0, '\0').Replace([string][char]1, '\1')
    if ($p.Length -eq 0) { '\e' } else { $p }
  }
  @($parts) -join [char]0
}

# 1 行ぶんの値の走査。括弧の深さ（Depth）と開いたままの複数行の文字列（Quote）を State に持ち、行をまたいで引き継ぐ。
# State に Head（値の最初の文字）・Firsts（最も外の [ ] の要素ごとの最初の文字）・Expect があれば、値が表かどうか（Test-TomlTableValue）を調べるために記録する
function Step-TomlValue {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][hashtable]$State)
  $i = 0
  $n = $Text.Length
  while ($i -lt $n) {
    $three = if ($i + 3 -le $n) { $Text.Substring($i, 3) } else { '' }
    # 複数行の文字列は、閉じる区切りの直前に引用符を 1〜2 個置ける（3〜5 個の連続を全部閉じる区切りとして消費する）
    if ($State.Quote -eq '"""') {
      if ($three -eq '"""') { $State.Quote = ''; $i += [Math]::Min(5, [regex]::Match($Text.Substring($i), '^"+').Length) }
      elseif ($Text[$i] -eq '\') { $i += 2 } else { $i++ }
      continue
    }
    if ($State.Quote -eq "'''") {
      if ($three -eq "'''") { $State.Quote = ''; $i += [Math]::Min(5, [regex]::Match($Text.Substring($i), "^'+").Length) }
      else { $i++ }
      continue
    }
    $c = $Text[$i]
    if ($State.ContainsKey('Head') -and -not [char]::IsWhiteSpace($c) -and $c -ne '#') {
      if ($State.Head -eq '') { $State.Head = [string]$c; $State.Expect = ($c -eq '[') }
      elseif ($State.Expect -and $c -ne ']') { $State.Firsts.Add([string]$c); $State.Expect = $false }
    }
    if ($three -eq '"""' -or $three -eq "'''") { $State.Quote = $three; $i += 3; continue }
    if ($c -eq '"') {
      $j = $i + 1
      while ($j -lt $n -and $Text[$j] -ne '"') { if ($Text[$j] -eq '\') { $j += 2 } else { $j++ } }
      $i = [Math]::Min($j + 1, $n)
      continue
    }
    if ($c -eq "'") {
      $j = $Text.IndexOf([char]39, $i + 1)
      $i = if ($j -lt 0) { $n } else { $j + 1 }
      continue
    }
    if ($c -eq '#') { break }
    if ($c -eq ',' -and $State.Depth -eq 1 -and $State.ContainsKey('Head') -and $State.Head -eq '[') { $State.Expect = $true }
    if ($c -eq '[' -or $c -eq '{') { $State.Depth++ } elseif ($c -eq ']' -or $c -eq '}') { $State.Depth-- }
    $i++
  }
}

# 値がインライン表、または表だけの配列（[[x]] と同じ意味になるもの）か。Split-TomlTable の State で走査した後に呼ぶ
function Test-TomlTableValue {
  param([Parameter(Mandatory)][hashtable]$State)
  $State.Head -eq '{' -or ($State.Head -eq '[' -and $State.Firsts.Count -gt 0 -and @($State.Firsts | Where-Object { $_ -ne '{' }).Count -eq 0)
}

# TOML を行単位で表と項目に分ける（値の中は解釈しない。複数行の値は 1 項目）。先頭は必ずトップレベル（Name が空）。
# 空行とコメントの行は捨てる。見出しは Name（正規化したキー）・IsArray・Header（行そのまま）・HeaderIndex、項目は Key（正規化。キーでない行は $null）・Parts（キーの各部分の書いたまま）・Value（最初の行の = の後ろ）・IsTable（値がインライン表か表だけの配列）・Lines・Last（最後の行の番号）を持つ
function Split-TomlTable {
  param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)
  $part = '(?:[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|''[^'']*'')'
  $keyRe = "^\s*(?<k>$part(?:\s*\.\s*$part)*)\s*=(?<v>.*)`$"
  # 見出しの名前もキーと同じく引用符の中を見る（"a]#" の ] や # を見出しの終わりやコメントと読まない）
  $arrayRe = "^\s*\[\[\s*(?<n>$part(?:\s*\.\s*$part)*)\s*\]\]\s*(#.*)?`$"
  $tableRe = "^\s*\[\s*(?<n>$part(?:\s*\.\s*$part)*)\s*\]\s*(#.*)?`$"
  $new = { param($name, $isArray, $header, $index) [pscustomobject]@{ Name = $name; IsArray = $isArray; Header = $header; HeaderIndex = $index; Entries = [Collections.Generic.List[object]]::new() } }
  $tables = [Collections.Generic.List[object]]::new()
  $cur = & $new '' $false $null -1
  $tables.Add($cur)
  for ($i = 0; $i -lt $Line.Count; $i++) {
    $l = $Line[$i]
    if ($l -match '^\s*(#.*)?$') { continue }
    if ($l -match $arrayRe) {
      $cur = & $new (ConvertTo-TomlKeyPath $Matches.n) $true $l $i
      $tables.Add($cur)
      continue
    }
    if ($l -match $tableRe) {
      $cur = & $new (ConvertTo-TomlKeyPath $Matches.n) $false $l $i
      $tables.Add($cur)
      continue
    }
    $key = $null
    $parts = $null
    $value = $null
    $isTable = $false
    $lines = @($l)
    if ($l -match $keyRe) {
      $key = ConvertTo-TomlKeyPath $Matches.k
      $parts = [string[]]@([regex]::Matches($Matches.k, $part) | ForEach-Object { $_.Value })
      $value = $Matches.v
      $state = @{ Depth = 0; Quote = ''; Head = ''; Expect = $false; Firsts = [Collections.Generic.List[string]]::new() }
      Step-TomlValue $value $state
      while (($state.Depth -gt 0 -or $state.Quote -ne '') -and $i + 1 -lt $Line.Count) {
        $i++
        $lines += $Line[$i]
        Step-TomlValue $Line[$i] $state
      }
      $isTable = Test-TomlTableValue $state
    }
    $cur.Entries.Add([pscustomobject]@{ Key = $key; Parts = $parts; Value = $value; IsTable = $isTable; Lines = [string[]]$lines; Last = $i })
  }
  $tables.ToArray()
}

# 同じキーが 2 回ある TOML は Codex が読めない。表の名前・キーの完全なパスの重複（書き方の違いは正規化して比べる）があれば throw する。ドット付きのキーの途中までの名前が表の見出しと同じ場合も throw する。
# 配列の表（[[…]]）は何回あってもよく、その中のキーの重複だけ見る（同じ名前のキー・表・暗黙の表があれば throw する）。値で定義したキー（インライン表など）の下に表の見出しやドット付きのキーがある場合も throw する
function Assert-TomlUnique {
  param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)
  $nul = [string][char]0
  $mark = [string][char]1
  $show = { param($p) [regex]::Replace($p.Replace($nul, '.'), "$mark\d+", '') }
  # 配列の表（[[…]]）は要素ごとに別の範囲。名前の途中までの各形に、そこまでにある配列の表の何番目の要素かを付け、要素をまたいだ名前を別物にする
  $arrayCount = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
  $qualify = {
    param($name)
    $acc = ''
    $raw = ''
    $out = [Collections.Generic.List[string]]::new()
    $parts = $name.Split([char]0)
    for ($i = 0; $i -lt $parts.Count; $i++) {
      $raw = if ($i -eq 0) { $parts[$i] } else { $raw + $nul + $parts[$i] }
      $q = $parts[$i]
      if ($arrayCount.ContainsKey($raw)) { $q += $mark + $arrayCount[$raw] }
      $acc = if ($i -eq 0) { $q } else { $acc + $nul + $q }
      $out.Add($acc)
    }
    , $out.ToArray()
  }
  $tableNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $arrayNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $allNames = [Collections.Generic.List[object]]::new()
  $dotted = [Collections.Generic.List[object]]::new()
  foreach ($t in (Split-TomlTable $Line)) {
    if ($t.IsArray) { $arrayCount[$t.Name] = 1 + $(if ($arrayCount.ContainsKey($t.Name)) { $arrayCount[$t.Name] } else { 0 }) }
    # 名前の比較は Length で見る（-ne '' は U+00AD のような無視される文字だけの名前を空とみなす）
    $q = if ($t.Name.Length -gt 0) { & $qualify $t.Name } else { @('') }
    # 表そのものの名前。自分が配列の表でも要素の番号は付けず、親にだけ付ける（キー・表・配列の表の同じ名前をぶつけて調べるため）
    $own = if ($t.Name.Length -eq 0) { '' } elseif ($q.Count -ge 2) { $q[$q.Count - 2] + $nul + $t.Name.Split([char]0)[-1] } else { $t.Name }
    if ($t.Name.Length -gt 0) { $allNames.Add($q) }
    if ($t.IsArray) {
      $null = $arrayNames.Add($own)
      $local = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      foreach ($e in $t.Entries) {
        if ($null -ne $e.Key -and -not $local.Add($e.Key)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show ($t.Name + $nul + $e.Key))" }
      }
      continue
    }
    if ($t.Name.Length -gt 0 -and -not $tableNames.Add($own)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show $own)" }
    foreach ($e in $t.Entries) {
      if ($null -eq $e.Key) { continue }
      $path = if ($t.Name.Length -eq 0) { $e.Key } else { $own + $nul + $e.Key }
      if (-not $paths.Add($path)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show $path)" }
      if ($e.Key.Contains($nul)) { $dotted.Add(@{ Table = $own; Key = $e.Key }) }
    }
  }
  foreach ($name in $tableNames) {
    if ($paths.Contains($name)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show $name)" }
  }
  # 暗黙に作られる表の名前（ドット付きのキーの途中までと、表の見出しの親）。値のキー・配列の表と同じ名前だと、定義が食い違う
  $implicit = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  # ドット付きのキーは、その途中までの名前の表を作る。同じ名前の表の見出しがあると、同じ表を 2 回定義することになる。値のキーの下には作れない
  foreach ($d in $dotted) {
    $parts = $d.Key.Split([char]0)
    for ($n = 1; $n -lt $parts.Count; $n++) {
      $name = (@($d.Table | Where-Object { $_ }) + $parts[0..($n - 1)]) -join $nul
      if ($tableNames.Contains($name)) { throw "config.toml にドット付きのキーと同じ名前の表がある（書かない）: $(& $show $name)" }
      if ($paths.Contains($name)) { throw "config.toml に値で定義した名前の下にドット付きのキーがある（書かない）: $(& $show $name)" }
      $null = $implicit.Add($name)
    }
  }
  # 値（インライン表・配列など）で定義した名前の下には表を作れない（親のキーのパスが、表の名前の先頭になっている）
  foreach ($prefixes in $allNames) {
    for ($n = 0; $n -lt $prefixes.Count - 1; $n++) {
      $parent = $prefixes[$n]
      if ($paths.Contains($parent)) { throw "config.toml に値で定義した名前の下に表がある（書かない）: $(& $show $parent)" }
      $null = $implicit.Add($parent)
    }
  }
  # 配列の表は、同じ名前のキー・表・暗黙の表とは両立しない
  foreach ($name in $arrayNames) {
    if ($tableNames.Contains($name) -or $paths.Contains($name) -or $implicit.Contains($name)) { throw "config.toml に配列の表と同じ名前がある（書かない）: $(& $show $name)" }
  }
}

# TOML の意味（表の名前・キー・値の組の集まり）を文字列の集合にする。並び・コメント・空行・書き方（引用符と空白）の違いは無視する。
# 配列の表（[[…]]）は何番目の要素かを名前に付ける（要素の順は意味。番号の前の印は U+0001 で、キーの部分には現れない）。その下の表は、直近の要素に属するものとして同じく番号を付ける
function Get-TomlMeaning {
  param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)
  $nul = [string][char]0
  $count = @{}
  $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($t in (Split-TomlTable $Line)) {
    if ($t.IsArray) { $count[$t.Name] = 1 + $(if ($count.ContainsKey($t.Name)) { $count[$t.Name] } else { 0 }) }
    $raw = ''
    $name = @(foreach ($p in $(if ($t.Name.Length) { $t.Name.Split([char]0) })) {
        $raw = if ($raw.Length) { $raw + $nul + $p } else { $p }
        if ($count.ContainsKey($raw)) { "$p$([char]1)$($count[$raw])" } else { $p }
      }) -join $nul
    $null = $set.Add("T$nul$name")
    foreach ($e in $t.Entries) {
      $text = if ($null -eq $e.Key) { ($e.Lines -join "`n").Trim() } else { ((@($e.Value) + @($e.Lines | Select-Object -Skip 1)) -join "`n").Trim() }
      $null = $set.Add("E$nul$name$nul$($e.Key)$nul$text")
    }
  }
  , $set
}

# Codex の config.toml をテンプレートから作る（@HOME@ は / 区切りのホーム。\ は TOML の文字列でエスケープになる）。
# テンプレートにあるキー（トップレベルと各表）はテンプレートの値にし、ほかのキーと表（Codex デスクトップが書く notify・[desktop]・プラグインなど）は値ごと引き継ぐ。
# ドット付きのキーで書いたテンプレートの表の項目（mcp_servers.linear.x = 1 など）はその表に結合する。install.sh は引き継ぐ表を限る。値の外のコメントと空行は引き継がない。キーと表の名前は引用符と空白を除いて比べ、それでも同じキーが 2 回になるなら書かずに失敗する。テンプレートのキー（値）を既存がインライン表や表の配列で定義しているときも、表と値がぶつかって表せないので書かずに失敗する。
# 意味（表の名前・キー・値）が違うときだけ退避して置き換える。変わったら $true
function New-CodexConfig {
  param(
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$HomeDir
  )
  $utf8 = [Text.UTF8Encoding]::new($false)
  $homeSlash = $HomeDir.TrimEnd('\', '/') -replace '\\', '/'
  $tmplText = [IO.File]::ReadAllText($Template, $utf8).Replace('@HOME@', $homeSlash)
  if ($tmplText.EndsWith("`n")) { $tmplText = $tmplText.Substring(0, $tmplText.Length - 1) }
  $t = $tmplText -split "`n"
  $tmplTables = @(Split-TomlTable $t)
  # テンプレートの行の番号 → その直後に入れる行（テンプレートの表の最後の項目の後ろ。トップレベルに項目が無ければ -1 = 先頭の前）
  $after = @{}
  foreach ($tt in $tmplTables) {
    $idx = if ($tt.Entries.Count) { $tt.Entries[$tt.Entries.Count - 1].Last } else { $tt.HeaderIndex }
    $after[$idx] = [Collections.Generic.List[string]]::new()
  }
  # テンプレートの表ごとの、キーの集合と、行を入れる位置（$after の添字）
  $tmplKeys = foreach ($tt in $tmplTables) {
    , [Collections.Generic.HashSet[string]]::new([string[]]@($tt.Entries | Where-Object { $null -ne $_.Key } | ForEach-Object { $_.Key }), [StringComparer]::Ordinal)
  }
  $tmplIdx = foreach ($tt in $tmplTables) { if ($tt.Entries.Count) { $tt.Entries[$tt.Entries.Count - 1].Last } else { $tt.HeaderIndex } }
  # 既存の表（名前の部分 $tp）の項目のキー（部分 $kp）が、ドットでテンプレートの表の下を指すとき、その表の番号と、表の下でのキーを返す（無ければ $null）
  $route = {
    param($tp, $kp)
    for ($k = 1; $k -lt $tmplTables.Count; $k++) {
      $c = $tmplTables[$k]
      if ($c.IsArray -or $c.Name.Length -eq 0) { continue }
      $np = $c.Name.Split([char]0)
      if ($np.Count -le $tp.Count -or $np.Count -ge $tp.Count + $kp.Count) { continue }
      $same = $true
      for ($j = 0; $j -lt $np.Count -and $same; $j++) {
        $x = if ($j -lt $tp.Count) { $tp[$j] } else { $kp[$j - $tp.Count] }
        $same = [string]::Equals($x, $np[$j], [StringComparison]::Ordinal)
      }
      if ($same) { return [pscustomobject]@{ Index = $k; Skip = $np.Count - $tp.Count; Rest = ($kp[($np.Count - $tp.Count)..($kp.Count - 1)] -join [char]0) } }
    }
  }
  $kept = [Collections.Generic.List[object]]::new()
  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $oldLines = @([IO.File]::ReadAllText($ConfigPath, $utf8).TrimStart([char]0xFEFF) -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    foreach ($ot in (Split-TomlTable $oldLines)) {
      $ti = -1
      if (-not $ot.IsArray) {
        for ($k = 0; $k -lt $tmplTables.Count; $k++) {
          if (-not $tmplTables[$k].IsArray -and [string]::Equals($tmplTables[$k].Name, $ot.Name, [StringComparison]::Ordinal)) { $ti = $k; break }
        }
      }
      $tp = @(if ($ot.Name.Length -gt 0) { $ot.Name.Split([char]0) })
      $stay = [Collections.Generic.List[object]]::new()
      foreach ($e in $ot.Entries) {
        # ドット付きのキーで書いたテンプレートの表の項目は、その表に結合する（キーが同じならテンプレートの値）
        $r = if (-not $ot.IsArray -and $null -ne $e.Key) { & $route $tp $e.Key.Split([char]0) }
        if ($r) {
          if ($tmplKeys[$r.Index].Contains($r.Rest) -and $e.IsTable) { throw "config.toml がテンプレートのキーを表で定義している（書かない）: $(@($tp) + $e.Key.Split([char]0) -join '.')" }
          if (-not $tmplKeys[$r.Index].Contains($r.Rest)) {
            $moved = @(($e.Parts[$r.Skip..($e.Parts.Count - 1)] -join '.') + ' =' + $e.Value) + @($e.Lines | Select-Object -Skip 1)
            $after[$tmplIdx[$r.Index]].AddRange([string[]]$moved)
          }
        }
        elseif ($ti -lt 0) { $stay.Add($e) }
        elseif ($null -ne $e.Key -and $e.IsTable -and $tmplKeys[$ti].Contains($e.Key)) { throw "config.toml がテンプレートのキーを表で定義している（書かない）: $(@($tp) + $e.Key.Split([char]0) -join '.')" }
        elseif ($null -eq $e.Key -or -not $tmplKeys[$ti].Contains($e.Key)) { $after[$tmplIdx[$ti]].AddRange([string[]]$e.Lines) }
      }
      if ($ti -lt 0) { $kept.Add([pscustomobject]@{ Header = $ot.Header; Entries = $stay }) }
    }
  }
  $out = [Collections.Generic.List[string]]::new()
  if ($after.ContainsKey(-1)) { $out.AddRange($after[-1]) }
  for ($i = 0; $i -lt $t.Count; $i++) {
    $out.Add($t[$i])
    if ($after.ContainsKey($i)) { $out.AddRange($after[$i]) }
  }
  foreach ($kt in $kept) {
    $out.Add('')
    $out.Add($kt.Header)
    foreach ($e in $kt.Entries) { $out.AddRange([string[]]$e.Lines) }
  }
  Assert-TomlUnique $out.ToArray()
  $newBytes = $utf8.GetBytes(($out -join "`n") + "`n")
  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $oldBytes = [IO.File]::ReadAllBytes($ConfigPath)
    if ([Linq.Enumerable]::SequenceEqual([byte[]]$oldBytes, [byte[]]$newBytes)) { return $false }
    # Codex の CLI は表を自分の順で書き直す。意味が同じで並びだけ違うなら書かない（退避が増えるため）
    # 既存が不正（同じキーや表が 2 回）なら比べずに直す。集合にすると重複が消えて同じに見えるため
    $oldValid = try { Assert-TomlUnique $oldLines; $true } catch { $false }
    if ($oldValid -and (Get-TomlMeaning $oldLines).SetEquals((Get-TomlMeaning $out.ToArray()))) { return $false }
  }
  $dir = Split-Path -Parent $ConfigPath
  if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
  if (Get-PathEntry $ConfigPath) {
    $bak = "$ConfigPath.bak.$(Get-BackupStamp)"
    Move-Item -LiteralPath $ConfigPath -Destination $bak
    Write-Host "backup: $ConfigPath -> $bak"
  }
  [IO.File]::WriteAllBytes($ConfigPath, $newBytes)
  $true
}

# PSCustomObject にキーを足すか上書きする
function Set-JsonMember {
  param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, $Value)
  if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
  else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# PowerShell 7 の既定のプロファイル（Windows Terminal が自動で作るもの）
$TerminalPwshGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

# Windows Terminal の settings.json の profiles.defaults に配色・フォント・余白・履歴を入れる（fragment は defaults に勝てないため）。
# ほかのキーとプロファイルはそのまま。結果が変わるときだけ .bak.<時刻> に写してから UTF-8（BOM なし）で書く。変わったら $true
function Update-TerminalSettings {
  param([Parameter(Mandatory)][string]$Path)
  $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
  $opts = @{ Depth = 50 }
  # 日付らしい文字列を DateTime に変えない（書き戻すと形が変わる）
  if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $opts.DateKind = 'String' }
  $before = ConvertTo-Json -InputObject ($raw | ConvertFrom-Json @opts) -Depth 50
  $json = $raw | ConvertFrom-Json @opts

  if ($null -eq $json.profiles) { Set-JsonMember $json 'profiles' ([pscustomobject]@{}) }
  elseif ($json.profiles -is [array]) { $json.profiles = [pscustomobject]@{ list = $json.profiles } }
  $profiles = $json.profiles
  if ($null -eq $profiles.defaults) { Set-JsonMember $profiles 'defaults' ([pscustomobject]@{}) }
  $d = $profiles.defaults
  Set-JsonMember $d 'colorScheme' 'Atom One Dark'
  if ($null -eq $d.font -or $d.font -isnot [pscustomobject]) { Set-JsonMember $d 'font' ([pscustomobject]@{}) }
  Set-JsonMember $d.font 'face' 'Hack Nerd Font Mono'
  Set-JsonMember $d.font 'size' 12
  Set-JsonMember $d 'padding' '6, 4'
  Set-JsonMember $d 'historySize' 50000
  $hasPwsh = @($profiles.list | Where-Object { $_.guid -ieq $TerminalPwshGuid }).Count -gt 0
  if ($hasPwsh) { Set-JsonMember $json 'defaultProfile' $TerminalPwshGuid }

  $after = ConvertTo-Json -InputObject $json -Depth 50
  $changed = $after -cne $before
  if ($changed) {
    $bak = "$Path.bak.$(Get-BackupStamp)"
    Copy-Item -LiteralPath $Path -Destination $bak
    Write-Host "backup: $Path -> $bak"
    [IO.File]::WriteAllText($Path, ($after -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
  }
  # ほかの設定は書いたうえで失敗にする（Windows Terminal が PowerShell 7 のプロファイルを作るのは起動したとき）
  if (-not $hasPwsh) { throw 'PowerShell 7 のプロファイルが Windows Terminal に無い（Windows Terminal を開き直してから再実行する）' }
  $changed
}
