#!/bin/sh
# Neovim の設定（config/nvim）の検査: 実際の設定で headless 起動し、エラーが無いこと、noice.nvim（依存の nui.nvim）が
# lazy.nvim の spec と lazy-lock.json にあり、設定どおりに起動すること（ARK-39）
#   sh tests/nvim.sh   （install.sh 済みの端末で。プラグインは Lazy! restore で入っていること）
set -eu
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(readlink "$HOME/.config/nvim")" != "$DOTFILES/config/nvim" ]; then
  echo "FAIL 前提: ~/.config/nvim がこのリポジトリの config/nvim へのリンクであること（install.sh）"; exit 1
fi
SCRIPT="$(mktemp)"
trap 'rm -f "$SCRIPT"' EXIT
cat > "$SCRIPT" <<'LUA'
local fail = false
local function check(desc, ok, detail)
  io.stdout:write((ok and "ok   " or "FAIL ") .. desc .. ((not ok and detail) and ("（" .. detail .. "）") or "") .. "\n")
  if not ok then fail = true end
end

local function checks()
  check("起動時にエラーが無い", vim.v.errmsg == "", vim.v.errmsg)
  local plugins = require("lazy.core.config").plugins
  local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
  for _, name in ipairs({ "noice.nvim", "nui.nvim" }) do
    check(name .. " が lazy.nvim の spec にある", plugins[name] ~= nil)
    check(name .. " の版が lazy-lock.json に記録されている", lock[name] ~= nil)
  end
  -- headless では VeryLazy が来ないので明示的に読み込む。lazy.nvim は config の例外を握りつぶし、noice の setup は
  -- vim.schedule で後回しになるので、読み込めただけでは足りない。動き出すまで待って確かめる
  require("lazy").load({ plugins = { "noice.nvim" } })
  local running = vim.wait(5000, function() return require("noice.config").is_running() end, 50)
  check("noice.nvim が設定どおりに起動する", running, "5 秒待っても起動しない: " .. vim.v.errmsg)
end

-- +luafile は VimEnter の前に動くが、noice の setup は VimEnter の後に動くので、検査も VimEnter の後に行う。
-- 途中の例外で終了処理に届かないと nvim がハングするので pcall で包む
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      local done, err = pcall(checks)
      if not done then check("検査スクリプトが最後まで動く", false, tostring(err)) end
      vim.cmd(fail and "cquit 1" or "qall!")
    end)
  end,
})
LUA
nvim --headless "+luafile $SCRIPT"
