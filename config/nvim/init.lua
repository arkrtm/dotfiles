-- コードを「読む」用途向けの最小構成

vim.g.mapleader = " "

local o = vim.opt
o.number = true
o.cursorline = true
o.signcolumn = "yes"
o.scrolloff = 5
o.ignorecase = true
o.smartcase = true
o.termguicolors = true
o.undofile = true
o.clipboard = "unnamedplus"

-- SSH 越しは OSC52 でローカルのクリップボードへコピー（貼り付けは端末側で行う）
if vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end

-- treesitter のパーサーがある言語は treesitter でハイライト（無ければ従来のハイライト）
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- ===== プラグイン（lazy.nvim）=====
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath })
  -- lazy.nvim 自身も lazy-lock.json のコミットに揃える（端末ごとにずれて lock に差分が出るのを防ぐ）
  local ok, lock = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
  end)
  if ok and lock["lazy.nvim"] then
    vim.fn.system({ "git", "-C", lazypath, "checkout", "-q", lock["lazy.nvim"].commit })
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
      require("onedark").load()
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "onedark",
        globalstatus = true, -- 分割時もステータスラインは 1 本
        component_separators = "",
        section_separators = "",
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = {
          "branch",
          {
            "diff",
            source = function()
              local g = vim.b.gitsigns_status_dict
              return g and { added = g.added, modified = g.changed, removed = g.removed }
            end,
          },
        },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "diagnostics", "filetype" },
        lualine_y = {},
        lualine_z = { "location" },
      },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "ファイル検索" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "全文検索" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "バッファ一覧" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "最近開いたファイル" },
      { "<leader>fs", "<cmd>Telescope git_status<cr>", desc = "git の変更ファイル" },
    },
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(buf)
        local gs = require("gitsigns")
        local map = function(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
        end
        map("]c", function() gs.nav_hunk("next") end, "次の変更")
        map("[c", function() gs.nav_hunk("prev") end, "前の変更")
        map("<leader>hp", gs.preview_hunk, "変更内容を表示")
        map("<leader>hb", function() gs.blame_line({ full = true }) end, "この行の blame")
        map("<leader>hd", gs.diffthis, "ファイル全体の diff")
      end,
    },
  },

  {
    "mikavilpas/yazi.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    keys = {
      { "<leader>e", "<cmd>Yazi<cr>", desc = "yazi（現在のファイルの場所）" },
      { "<leader>E", "<cmd>Yazi cwd<cr>", desc = "yazi（作業ディレクトリ）" },
    },
    opts = { open_for_directories = true },
  },

  -- パーサーのビルドに C コンパイラと tree-sitter CLI（mise）が必要。使えない端末では読み込まない
  -- （tree-sitter の配布バイナリは glibc 2.39 以上が必要で、Debian 12 では起動しない）
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    cond = vim.fn.executable("cc") == 1
      and vim.fn.executable("tree-sitter") == 1
      and vim.system({ "tree-sitter", "--version" }):wait().code == 0,
    config = function()
      require("nvim-treesitter").install({
        "bash", "css", "dockerfile", "go", "html", "javascript", "json", "lua",
        "markdown", "markdown_inline", "python", "rust", "sql", "toml", "tsx",
        "typescript", "yaml",
      })
    end,
  },
}, {
  install = { colorscheme = { "onedark" } },
  change_detection = { notify = false },
  rocks = { enabled = false },
})
