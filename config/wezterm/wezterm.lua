-- WezTerm（Windows）。Windows の環境変数 WEZTERM_CONFIG_FILE でこのファイルを指す（config/wezterm/README.md）
-- WSL へは WezTerm 内蔵の SSH で localhost の sshd につなぐ。ConPTY（WSL ドメイン）は kitty 方式の画像を落とし、
-- iTerm2 方式でも位置がずれる。wsl.exe 越しの `wezterm cli proxy` は Windows の GUI からだと応答が返らず止まる
-- 既定は WSL。Ctrl+Shift+1 で WSL、Ctrl+Shift+2 で PowerShell のタブ、Ctrl+Shift+O でランチャー
local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

local wsl = 'wsl'
-- PowerShell 7 は Store 版（WindowsApps の実行エイリアス）で、WezTerm は名前だけだと見つけられない（os error 2）のでフルパスで指す
local pwsh = { wezterm.home_dir .. '\\AppData\\Local\\Microsoft\\WindowsApps\\pwsh.exe', '-NoLogo' }
-- 新しいタブは今のペインの cwd を引き継ぐので、WSL のパス（/home/…）のまま Windows のプロセスを起動して失敗しないよう明示する
local win_home = wezterm.home_dir

config.ssh_domains = {
  {
    name = wsl,
    remote_address = '127.0.0.1', -- WSL の mirrored networking で Windows の localhost が WSL の sshd に届く
    username = 'arakih100', -- WSL のユーザー（Windows のユーザー名とは別）
    multiplexing = 'None', -- 画像は WezTerm の GUI が直接描く
    ssh_option = { identityfile = wezterm.home_dir .. '/.ssh/wezterm_wsl' }, -- この接続専用の鍵（WSL では from="127.0.0.1,::1" に限る）
  },
}
config.default_domain = wsl
config.launch_menu = {
  { label = 'PowerShell', domain = { DomainName = 'local' }, args = pwsh, cwd = win_home },
}

-- 見た目は config/ghostty/config に合わせる
config.font = wezterm.font_with_fallback { 'Hack Nerd Font Mono', 'Hack Nerd Font' }
config.font_size = 12
config.color_scheme = 'OneDark (base16)'
config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }

-- herdr の中の yazi の画像プレビュー（herdr は kitty 方式だけを通す。config/herdr/config.toml の experimental.kitty_graphics）
config.enable_kitty_graphics = true

-- 数字は物理キーで指定（JIS 配列でも Shift+数字の記号に依らない）。既定の Ctrl+Shift+1・2（タブの切り替え）を置き換える
config.keys = {
  { key = 'phys:1', mods = 'CTRL|SHIFT', action = act.SpawnTab { DomainName = wsl } },
  { key = 'phys:2', mods = 'CTRL|SHIFT', action = act.SpawnCommandInNewTab { domain = { DomainName = 'local' }, args = pwsh, cwd = win_home } },
  { key = 'o', mods = 'CTRL|SHIFT', action = act.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS|DOMAINS' } },
}

return config
