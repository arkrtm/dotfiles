#Requires -Version 7
# Claude Code のステータスライン（Windows。config/claude/statusline.sh の移植。出力は同じ Nerd Font アイコン付き 2 行。jq・awk を使わない）
# 1 行目: Claude のモデルと effort → Codex（レビュー役）のモデルと effort → ブランチ、2 行目: コンテキスト・5 時間・週の上限のメーター（緑 → 黄 → 赤。それぞれの前に Claude のアイコン）→ Codex のアイコンと 5 時間・週の上限のメーター。アイコンは Claude を橙、Codex を白
# herdr の中では、この pane の名前を main · モデル effort にする（agent-pane のサブエージェントの pane と見分ける）
# 入力の欠けたフィールドは空として扱い、例外で止めない（{} でも 2 行を出す）
$utf8 = [Text.UTF8Encoding]::new($false)
# 端末のコードページ（932）のままだとアイコンとバーが ? になる。コンソールが無いと設定に失敗するので、そのときは出力をバイト列で書く
try { [Console]::InputEncoding = $utf8 } catch { }
$rawOut = $false
try { [Console]::OutputEncoding = $utf8 } catch { $rawOut = $true }

$in = ''
try { $in = [IO.StreamReader]::new([Console]::OpenStandardInput(), $utf8).ReadToEnd() } catch { }
$j = $null
try { $j = $in | ConvertFrom-Json -Depth 64 -ErrorAction Stop } catch { }
# jq の「パス // empty」: 無い・null・false は空文字
function get([string]$path) {
  $v = $j
  foreach ($k in $path.TrimStart('.').Split('.')) {
    if ($null -eq $v -or $v -isnot [psobject] -or $null -eq $v.PSObject.Properties[$k]) { return '' }
    $v = $v.PSObject.Properties[$k].Value
  }
  if ($null -eq $v -or ($v -is [bool] -and -not $v)) { return '' }
  if ($v -is [bool]) { return 'true' }
  [string]$v
}

$E = [char]27
$I_CLAUDE = "$E[38;5;173m$([char]0xEC82)$E[0m"  # nf-cod-claude   U+EC82（Nerd Fonts 3.5.0 以降）。橙
$I_OPENAI = "$E[97m$([char]0xEC81)$E[0m"        # nf-cod-openai   U+EC81（同上）。白
$I_BRANCH = [string][char]0xE0A0                # branch          U+E0A0
$I_CTX = [string][char]0xF1C0                   # nf-fa-database  U+F1C0
$I_5H = [string][char]0xF017                    # nf-fa-clock_o   U+F017
$I_7D = [string][char]0xF073                    # nf-fa-calendar  U+F073
$I_RESET = [string][char]0xF021                 # nf-fa-refresh   U+F021
$R = "$E[0m"; $DIM = "$E[2m"

# ${x%.*}: 最後の . から後ろを落とす（小数を切り捨てる）
function trunc([string]$s) { $s -replace '\.[^.]*$', '' }
function num([string]$s) {
  $n = 0L
  if ([long]::TryParse((trunc $s), [ref]$n)) { return $n }
  $d = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return [long][math]::Truncate($d) }
  0L
}
function hm([string]$t) {
  try { [DateTimeOffset]::FromUnixTimeSeconds((num $t)).ToLocalTime().ToString('HH:mm') } catch { '' }
}
# 値 黄のしきい値 赤のしきい値 → 色
function col([long]$v, [long]$yel, [long]$red) { if ($v -ge $red) { "$E[31m" } elseif ($v -ge $yel) { "$E[33m" } else { "$E[32m" } }
# 10 マスのバー
function bar([long]$p) {
  $n = [math]::Min([math]::Max([math]::Floor(($p + 5) / 10), 0), 10)
  ('█' * $n) + ('░' * (10 - $n))
}
# アイコン 値 黄 赤
# （PowerShell の変数名は大文字と小文字を区別しないので、$R と重なる名前を引数に使わない）
function meter([string]$icon, [string]$val, [long]$yel, [long]$red) {
  $p = num $val
  '{0}{1} {2} {3,3}%{4}' -f (col $p $yel $red), $icon, (bar $p), $p, $R
}

# 1 行目: Claude のモデル・effort（対応していないモデルでは入力に無い）→ Codex → ブランチ
$line1 = "$I_CLAUDE $(get .model.display_name)"
$eff = get .effort.level
if ($eff) { $line1 += " $DIM$eff$R" }
# Codex の設定の先頭（最初の表より前）の model と model_reasoning_effort
$ch = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$head = @()
try {
  foreach ($ln in [IO.File]::ReadLines((Join-Path $ch 'config.toml'), $utf8)) {
    if ($ln.StartsWith('[')) { break }
    $head += $ln
  }
} catch { }
function cx([string]$k) {
  foreach ($ln in $head) { if ($ln -cmatch "^$([regex]::Escape($k)) *= *`"([^`"]*)") { return $Matches[1] } }
  ''
}
$cm = cx model; $ce = cx model_reasoning_effort
if ($cm) {
  $line1 += "   $I_OPENAI $cm"
  if ($ce) { $line1 += " $DIM$ce$R" }
}
$br = ''
if (Get-Command git -CommandType Application -ErrorAction Ignore) {
  $wd = get .workspace.current_dir
  try {
    $br = if ($wd) { git -C $wd branch --show-current 2>$null } else { git branch --show-current 2>$null }
    $br = "$($br | Select-Object -First 1)".Trim()
  } catch { $br = '' }
}
if ($br) { $line1 += "   $DIM$I_BRANCH $br$R" }

# 2 行目: コンテキスト・5 時間・週のメーター。それぞれの前に Claude のアイコン
$line2 = ''
$ctx = get .context_window.used_percentage
# 使用率を context-nudge（PostToolUse のフック。入力に使用率が無い）に渡す。改行は LF だけ（context-nudge は数字以外を捨てる）
$sid = get .session_id
if ($ctx -and ($sid -notin '', '.', '..') -and ($sid -notmatch '[/\\]')) {
  try {
    $st = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path $HOME '.local\state' }
    $d = Join-Path $st 'claude-context'
    [void][IO.Directory]::CreateDirectory($d)
    [IO.File]::WriteAllText((Join-Path $d $sid), "$(trunc $ctx)`n", $utf8)
  } catch { }
}
if ($ctx) { $line2 += "$I_CLAUDE $(meter $I_CTX $ctx 50 70)   " }
$h5 = get .rate_limits.five_hour.used_percentage
if ($h5) {
  $line2 += "$I_CLAUDE $(meter $I_5H $h5 50 80)"
  $r5 = get .rate_limits.five_hour.resets_at
  if ($r5) { $line2 += " $DIM$I_RESET $(hm $r5)$R" }
  $line2 += '   '
}
$d7 = get .rate_limits.seven_day.used_percentage
if ($d7) { $line2 += "$I_CLAUDE $(meter $I_7D $d7 50 80)   " }

# Codex の使用量: 更新の新しいセッションから、記録のある 2 ファイルの最後の 5 行ずつを古い順に集める（ファイルが数 MB あるので、文字列で絞った行だけを JSON として読む。
# 再開したセッションは古いファイルに追記されるので、名前でなく更新時刻で選ぶ）
# shortcut: 2 ファイルとも最後の 5 行が読めない行（} で終わるのに JSON でない）だけなら出さない。Codex を並列で何本も動かす使い方になったら増やす
# shortcut: 新しい 7 日分の日のディレクトリだけを見る（7 日より前に始めて再開したセッションは見ない）
$files = @()
try {
  $days = @(Get-ChildItem -Path (Join-Path $ch 'sessions\*\*\*') -Directory -ErrorAction Ignore | Sort-Object FullName -Culture '' | Select-Object -Last 7)
  $files = @($days | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter *.jsonl -File -ErrorAction Ignore } |
      Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 20)
} catch { }
$groups = [Collections.Generic.List[object]]::new()
foreach ($f in $files) {
  if ($groups.Count -ge 2) { break }
  # 書き込み中のファイルも読めるように共有で開く。読めないファイルは飛ばす。書き込み途中の行は } で終わらないことが多いので、途切れた行だけのファイルは数えない
  $m = [Collections.Generic.Queue[string]]::new()
  try {
    $fs = [IO.FileStream]::new($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
      $sr = [IO.StreamReader]::new($fs, $utf8)
      while ($null -ne ($ln = $sr.ReadLine())) {
        if ($ln.Contains('"rate_limits":{"limit_id":"codex"', [StringComparison]::Ordinal) -and $ln.EndsWith('}')) {
          $m.Enqueue($ln); if ($m.Count -gt 5) { [void]$m.Dequeue() }
        }
      }
    } finally { $fs.Dispose() }
  } catch { continue }
  if ($m.Count -gt 0) { $groups.Insert(0, @($m)) }
}
# 窓は位置（primary・secondary）でなく長さ（分）で見分ける。リセット時刻を過ぎた窓は 0%（時刻は出さない）。読めた行のうち最後のもの
$rl = $null; $found = $false
foreach ($g in $groups) {
  foreach ($ln in $g) {
    try { $o = $ln | ConvertFrom-Json -Depth 64 -ErrorAction Stop; $rl = $o.payload.rate_limits; $found = $true } catch { }
  }
}
$cx = ''
if ($found -and $null -ne $rl) {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $ws = @($rl.primary, $rl.secondary | Where-Object { $_ }) | Sort-Object { [double]$_.window_minutes }
  foreach ($w in $ws) {
    $wm = [string]$w.window_minutes
    $past = $null -eq $w.resets_at -or [double]$w.resets_at -lt $now
    $p = if ($past) { '0' } else { [string]$w.used_percent }
    switch ($wm) {
      '300' {
        $cx += meter $I_5H $p 50 80
        if (-not $past) { $cx += " $DIM$I_RESET $(hm ([string]$w.resets_at))$R" }
        $cx += '   '
      }
      '10080' { $cx += "$(meter $I_7D $p 50 80)   " }
    }
  }
}
if ($cx) { $line2 += "$I_OPENAI $cx" }

# herdr の中では、この pane の名前を「main · モデルの正式な名前 effort」にする（agent-pane のサブエージェントの pane と見分ける）。
# 今の名前と違うときだけ付ける（herdr を立ち上げ直して名前が消えても付け直せるよう、覚えずに毎回聞く）
$mid = get .model.id
if ($env:HERDR_ENV -eq '1' -and $env:HERDR_PANE_ID -and $mid -and (Get-Command herdr -ErrorAction Ignore)) {
  $pn = "main · $($mid -replace '\[.*$', '')$(if ($eff) { " $eff" })"
  $cur = ''
  try { $cur = [string](((herdr pane get $env:HERDR_PANE_ID 2>$null) -join "`n" | ConvertFrom-Json -ErrorAction Stop).result.pane.label) } catch { }
  if ($cur -cne $pn) { try { herdr pane rename $env:HERDR_PANE_ID $pn *>$null } catch { } }
}

$out = "$line1`n$line2`n"
if ($rawOut) {
  $b = $utf8.GetBytes($out); $o = [Console]::OpenStandardOutput(); $o.Write($b, 0, $b.Length); $o.Flush()
} else {
  [Console]::Out.Write($out)
}
exit 0
