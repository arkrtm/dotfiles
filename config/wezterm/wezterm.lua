-- WezTerm（Windows）。Windows の環境変数 WEZTERM_CONFIG_FILE でこのファイルを指す（README の Windows の節）
-- 既定は WSL。Ctrl+Shift+1 で WSL、Ctrl+Shift+2 で PowerShell のタブ、Ctrl+Shift+O でランチャー
local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

local wsl = 'WSL:Ubuntu-22.04'
local pwsh = { 'pwsh.exe', '-NoLogo' }

config.default_domain = wsl
config.launch_menu = {
  { label = 'PowerShell', domain = { DomainName = 'local' }, args = pwsh },
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
  { key = 'phys:2', mods = 'CTRL|SHIFT', action = act.SpawnCommandInNewTab { domain = { DomainName = 'local' }, args = pwsh } },
  { key = 'o', mods = 'CTRL|SHIFT', action = act.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS|DOMAINS' } },
}

return config
