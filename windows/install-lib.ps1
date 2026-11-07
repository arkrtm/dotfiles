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

# TOML のキー（a."b.c".'d'。ドットの前後の空白可）を部分に分けて正規化し、NUL でつなぐ。引用符と空白の書き方が違っても同じキーなら同じ文字列になる
function ConvertTo-TomlKeyPath {
  param([Parameter(Mandatory)][string]$Text)
  $parts = foreach ($m in [regex]::Matches($Text, '[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|''[^'']*''')) {
    $v = $m.Value
    if ($v.StartsWith('"')) { ConvertFrom-TomlEscape $v.Substring(1, $v.Length - 2) }
    elseif ($v.StartsWith("'")) { $v.Substring(1, $v.Length - 2) }
    else { $v }
  }
  @($parts) -join [char]0
}

# 1 行ぶんの値の走査。括弧の深さ（Depth）と開いたままの複数行の文字列（Quote）を State に持ち、行をまたいで引き継ぐ
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
    if ($three -eq '"""' -or $three -eq "'''") { $State.Quote = $three; $i += 3; continue }
    $c = $Text[$i]
    if ($c -eq '"') {
      $j = $i + 1
      while ($j -lt $n -and $Text[$j] -ne '"') { if ($Text[$j] -eq '\') { $j += 2 } else { $j++ } }
      $i = [Math]::Min($j + 1, $n)
      continue
    }
    if ($c -eq "'") {
      $j = $Text.IndexOf("'", $i + 1)
      $i = if ($j -lt 0) { $n } else { $j + 1 }
      continue
    }
    if ($c -eq '#') { break }
    if ($c -eq '[' -or $c -eq '{') { $State.Depth++ } elseif ($c -eq ']' -or $c -eq '}') { $State.Depth-- }
    $i++
  }
}

# TOML を行単位で表と項目に分ける（値の中は解釈しない。複数行の値は 1 項目）。先頭は必ずトップレベル（Name が空）。
# 空行とコメントの行は捨てる。見出しは Name（正規化したキー）・IsArray・Header（行そのまま）・HeaderIndex、項目は Key（正規化。キーでない行は $null）・Lines・Last（最後の行の番号）を持つ
function Split-TomlTable {
  param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)
  $part = '(?:[A-Za-z0-9_-]+|"(?:[^"\\]|\\.)*"|''[^'']*'')'
  $keyRe = "^\s*(?<k>$part(?:\s*\.\s*$part)*)\s*=(?<v>.*)`$"
  $new = { param($name, $isArray, $header, $index) [pscustomobject]@{ Name = $name; IsArray = $isArray; Header = $header; HeaderIndex = $index; Entries = [Collections.Generic.List[object]]::new() } }
  $tables = [Collections.Generic.List[object]]::new()
  $cur = & $new '' $false $null -1
  $tables.Add($cur)
  for ($i = 0; $i -lt $Line.Count; $i++) {
    $l = $Line[$i]
    if ($l -match '^\s*(#.*)?$') { continue }
    if ($l -match '^\s*\[\[\s*(?<n>.+?)\s*\]\]\s*(#.*)?$') {
      $cur = & $new (ConvertTo-TomlKeyPath $Matches.n) $true $l $i
      $tables.Add($cur)
      continue
    }
    if ($l -match '^\s*\[\s*(?<n>.+?)\s*\]\s*(#.*)?$') {
      $cur = & $new (ConvertTo-TomlKeyPath $Matches.n) $false $l $i
      $tables.Add($cur)
      continue
    }
    $key = $null
    $lines = @($l)
    if ($l -match $keyRe) {
      $key = ConvertTo-TomlKeyPath $Matches.k
      $state = @{ Depth = 0; Quote = '' }
      Step-TomlValue $Matches.v $state
      while (($state.Depth -gt 0 -or $state.Quote -ne '') -and $i + 1 -lt $Line.Count) {
        $i++
        $lines += $Line[$i]
        Step-TomlValue $Line[$i] $state
      }
    }
    $cur.Entries.Add([pscustomobject]@{ Key = $key; Lines = [string[]]$lines; Last = $i })
  }
  $tables.ToArray()
}

# 同じキーが 2 回ある TOML は Codex が読めない。表の名前・キーの完全なパスの重複（書き方の違いは正規化して比べる）があれば throw する。ドット付きのキーの途中までの名前が表の見出しと同じ場合も throw する。
# 配列の表（[[…]]）は何回あってもよく、その中のキーの重複だけ見る。値で定義したキー（インライン表など）の下に表の見出しがある場合も throw する
function Assert-TomlUnique {
  param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)
  $nul = [string][char]0
  $mark = [string][char]1
  $show = { param($p) [regex]::Replace($p.Replace($nul, '.'), "$mark\d+", '') }
  # 配列の表（[[…]]）は要素ごとに別の範囲。名前の途中までの各形に、そこまでにある配列の表の何番目の要素かを付け、要素をまたいだ名前を別物にする
  $arrayCount = @{}
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
  $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $allNames = [Collections.Generic.List[object]]::new()
  $dotted = [Collections.Generic.List[object]]::new()
  foreach ($t in (Split-TomlTable $Line)) {
    if ($t.IsArray) { $arrayCount[$t.Name] = 1 + [int]$arrayCount[$t.Name] }
    $q = if ($t.Name -ne '') { & $qualify $t.Name } else { @('') }
    $qName = $q[$q.Count - 1]
    if ($t.Name -ne '') { $allNames.Add($q) }
    if ($t.IsArray) {
      $local = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      foreach ($e in $t.Entries) {
        if ($null -ne $e.Key -and -not $local.Add($e.Key)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show ($t.Name + $nul + $e.Key))" }
      }
      continue
    }
    if ($t.Name -ne '' -and -not $tableNames.Add($qName)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show $qName)" }
    foreach ($e in $t.Entries) {
      if ($null -eq $e.Key) { continue }
      $path = if ($t.Name -eq '') { $e.Key } else { $qName + $nul + $e.Key }
      if (-not $paths.Add($path)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show $path)" }
      if ($e.Key.Contains($nul)) { $dotted.Add(@{ Table = $qName; Key = $e.Key }) }
    }
  }
  foreach ($name in $tableNames) {
    if ($paths.Contains($name)) { throw "config.toml に同じキーが 2 回ある（書かない）: $(& $show $name)" }
  }
  # ドット付きのキーは、その途中までの名前の表を作る。同じ名前の表の見出しがあると、同じ表を 2 回定義することになる
  foreach ($d in $dotted) {
    $parts = $d.Key.Split([char]0)
    for ($n = 1; $n -lt $parts.Count; $n++) {
      $name = (@($d.Table | Where-Object { $_ }) + $parts[0..($n - 1)]) -join $nul
      if ($tableNames.Contains($name)) { throw "config.toml にドット付きのキーと同じ名前の表がある（書かない）: $(& $show $name)" }
    }
  }
  # 値（インライン表・配列など）で定義した名前の下には表を作れない（親のキーのパスが、表の名前の先頭になっている）
  foreach ($prefixes in $allNames) {
    for ($n = 0; $n -lt $prefixes.Count - 1; $n++) {
      $parent = $prefixes[$n]
      if ($paths.Contains($parent)) { throw "config.toml に値で定義した名前の下に表がある（書かない）: $(& $show $parent)" }
    }
  }
}

# Codex の config.toml をテンプレートから作る（@HOME@ は / 区切りのホーム。\ は TOML の文字列でエスケープになる）。
# テンプレートにあるキー（トップレベルと各表）はテンプレートの値にし、ほかのキーと表（Codex デスクトップが書く notify・[desktop]・プラグインなど）は値ごと引き継ぐ。
# install.sh は引き継ぐ表を限る。値の外のコメントと空行は引き継がない。キーと表の名前は引用符と空白を除いて比べ、それでも同じキーが 2 回になるなら書かずに失敗する。
# 中身が違うときだけ退避して置き換える。変わったら $true
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
  $kept = [Collections.Generic.List[object]]::new()
  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $oldLines = @([IO.File]::ReadAllText($ConfigPath, $utf8).TrimStart([char]0xFEFF) -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    foreach ($ot in (Split-TomlTable $oldLines)) {
      $ti = -1
      if (-not $ot.IsArray) {
        for ($k = 0; $k -lt $tmplTables.Count; $k++) {
          if (-not $tmplTables[$k].IsArray -and $tmplTables[$k].Name -ceq $ot.Name) { $ti = $k; break }
        }
      }
      if ($ti -lt 0) { $kept.Add($ot); continue }
      $tt = $tmplTables[$ti]
      $keys = @($tt.Entries | Where-Object { $null -ne $_.Key } | ForEach-Object { $_.Key })
      $idx = if ($tt.Entries.Count) { $tt.Entries[$tt.Entries.Count - 1].Last } else { $tt.HeaderIndex }
      foreach ($e in $ot.Entries) {
        if ($null -eq $e.Key -or $e.Key -cnotin $keys) { $after[$idx].AddRange([string[]]$e.Lines) }
      }
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
