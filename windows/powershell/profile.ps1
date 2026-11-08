#Requires -Version 7.4
# pwsh のプロファイル（CurrentUserAllHosts。install.ps1 が Documents\PowerShell\profile.ps1 へリンク）。
# shell/zshenv + zprofile + zshrc の移植。前半は非対話（pwsh -Command / -File）でも毎回読まれるので、プロセスを起動しない。
# 永続する値（EDITOR、ユーザー PATH）は install.ps1 が HKCU\Environment にも書く。ここは今のセッション用

# ===== 環境（zshenv + zprofile）=====
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'
# Windows は Machine PATH が User PATH より前に来るので、ユーザー領域をここで先頭に戻す（zprofile と同じ順）
$dotfilesPathPre = @("$HOME\.local\bin", "$env:LOCALAPPDATA\mise\shims")
if (Test-Path -LiteralPath "$HOME\.cargo\bin") { $dotfilesPathPre += "$HOME\.cargo\bin" }
# 入れ子の pwsh で同じディレクトリが積まれないように畳む（typeset -U path 相当。Windows の PATH は大文字小文字を区別しない）
$env:PATH = (($dotfilesPathPre + ($env:PATH -split ';')) | Where-Object { $_ } | Select-Object -Unique -CaseInsensitive) -join ';'
Remove-Variable dotfilesPathPre

# ===== ここから対話のみ（zshrc）=====
# ConsoleHost は対話セッションでだけ PSReadLine を読み込む。-Command / -File / -NonInteractive はここで抜ける
if (-not (Get-Module PSReadLine)) { return }

# システムのコードページが 932 なので、UTF-8 に揃える（starship、eza などの出力と日本語入力）
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

# ===== キー操作（vi 風）=====
# -EditMode はキー割り当てを全部初期化するので最初に置く
Set-PSReadLineOption -EditMode Vi

# ===== 履歴 =====
# 保存先は PSReadLine の既定（%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine）。SaveIncrementally で他のセッションと共有
# $MaximumHistoryCount（Get-History 側、上限 32767）は触らない
Set-PSReadLineOption -MaximumHistoryCount 50000 -HistoryNoDuplicates -HistorySaveStyle SaveIncrementally
# 空白で始まる行はファイルに書かない（hist_ignore_space。次のコマンドまでは呼び出せる）。
# それ以外は既定の判定に任せる（password、token などを含む行をファイルに書かない既定のフィルタを残す）
Set-PSReadLineOption -AddToHistoryHandler {
  param([string]$line)
  if ($line -match '^\s') { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly }
  [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
}
# 履歴からの入力候補（zsh-autosuggestions 相当。行末で → で確定）。出力がリダイレクトされた端末では使えないので飛ばす
try { Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView -ErrorAction Stop } catch { }

# ===== 補完 =====
# 候補を一覧から選ぶ（menu select 相当。PowerShell の補完は元から大文字小文字を区別しない）
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ViMode Insert

# モードに合わせてカーソル形状を変える（挿入: 縦棒 / ノーマル: ブロック）。
# starship init より前に置く（starship は既存のハンドラを包んで ❮ 表示を足す。後から置くと starship のものを消す）
Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler {
  if ($args[0] -eq 'Command') { [Console]::Write("`e[2 q") } else { [Console]::Write("`e[6 q") }
}
# プロンプトのたびに縦棒へ戻す（zle-line-init 相当。nvim などがブロックのまま終わった後用）。starship が毎回呼ぶ
function Invoke-Starship-PreCommand { [Console]::Write("`e[6 q") }

# ===== ツール =====
# 順序は zshrc と違う: mise activate は今の prompt 関数を包んで毎回 hook-env を走らせるので、starship（prompt を定義）を先に読む
if (Get-Command starship -ErrorAction Ignore) { Invoke-Expression (& starship init powershell | Out-String) }
if (Get-Command mise -ErrorAction Ignore) { mise activate pwsh | Out-String | Invoke-Expression }
# fzf: Ctrl-R 履歴検索 / Ctrl-T ファイル / Alt-C ディレクトリ移動（fzf に PowerShell 用の組み込みはないので PSFzf。
# -EditMode Vi の後に読むと vi の両モードに割り当てる）
if ((Get-Command fzf -ErrorAction Ignore) -and (Get-Module -ListAvailable PSFzf)) {
  Import-Module PSFzf
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# ls / cat 自体は置き換えない（Claude Code 等が実行するコマンドの挙動を変えないため）。
# PowerShell の alias は引数を持てないので関数にする
function ll { eza -l --git --icons @args }
function la { eza -la --git --icons @args }
function lt { eza --tree --level=2 --icons @args }
function lg { lazygit @args }
function lzd { lazydocker @args }
# 並列作業: git worktree を作ってその中で Claude Code を起動（cw <名前>）。herdr の新しいタブで実行すると状態表示もタブごとに出る
function cw { claude -w @args }
