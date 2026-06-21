-- ── Bootstrap Lazy.nvim ──────────────────────────────────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── General Configuration ────────────────────────────────
-- Leader = F1 (avoids any Shift / case issues from held letter keys)
vim.g.mapleader = "<F1>"
vim.g.maplocalleader = "<F1>"

-- UI & Layout
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true

-- ── Remote Clipboard (OSC 52) ────────────────────────────
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
    ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
  },
}
vim.opt.clipboard = "unnamedplus"

-- ── Auto-Commands ────────────────────────────────────────
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  command = [[%s/\s\+$//e]],
  desc = "Automatically remove trailing whitespace on save",
})

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  pattern = { "*.c", "*.cpp", "*.h", "*.hpp" },
  callback = function()
    pcall(vim.fn.matchdelete, vim.w.long_comment_match_id)
    local match_id = vim.fn.matchadd("ErrorMsg", [[^\s*\(\/\/\|\/\*\|\*\).*\zs\%>72v.\+]])
    vim.w.long_comment_match_id = match_id
  end,
  desc = "Highlight comments exceeding 72 columns",
})

-- ── Plugin Specification ─────────────────────────────────
require("lazy").setup({
  -- UI & Theme
  {
    "folke/tokyonight.nvim",
    priority = 1000, -- Forces theme to load first to prevent unstyled text flashes
    config = function()
      require("tokyonight").setup({
        style = "night",
        transparent = true,
        terminal_colors = false,
        styles = {
          comments = { italic = true, bold = false },
          keywords = { italic = false, bold = false },
          functions = { bold = false },
          variables = { bold = false },
          sidebars = "dark",
          floats = "dark",
        },
        on_highlights = function(hl, c)
          hl.Normal = { fg = c.fg_dark, bg = c.bg_dark }
          hl.Comment = { fg = c.dark3 }
          hl.String = { fg = c.green1 }
        end,
      })
      vim.cmd[[colorscheme tokyonight]]
    end
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = { options = { theme = "tokyonight", section_separators = "", component_separators = "" } }
  },
  { "lewis6991/gitsigns.nvim", opts = {} },
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      actions = { use_system_clipboard = true },
      -- Copy via '+' so it rides OSC 52 to the Mac clipboard.
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.config.mappings.default_on_attach(bufnr)
        local function map(key, get, desc)
          vim.keymap.set("n", key, function()
            local node = api.tree.get_node_under_cursor()
            if not node then return end
            local value = get(node)
            vim.fn.setreg("+", value)
            vim.notify("Copied: " .. value)
          end, { desc = desc, buffer = bufnr, noremap = true, silent = true, nowait = true })
        end
        map("y",    function(n) return n.absolute_path end,            "Copy path")
        map("<CR>", function(n) return "nvim " .. n.absolute_path end, "Copy nvim cmd")
      end,
    },
  },

  -- Navigation
  { "christoomey/vim-tmux-navigator" },
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" }, opts = {} },
  { "tpope/vim-fugitive" },

  -- Syntax & Parsing (nvim-treesitter `main` branch — Neovim 0.11+ API)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")
      -- Guard: skip when the plugin hasn't been synced to the `main` branch yet
      -- (master has no .install), so startup never hard-errors. Run :Lazy restore.
      if ts.install then ts.install({ "c", "cpp", "lua", "rust", "python", "bash" }) end
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "c", "cpp", "lua", "rust", "python", "sh" },
        callback = function() pcall(vim.treesitter.start) end,
        desc = "Enable treesitter highlighting",
      })
    end
  },
  { "windwp/nvim-autopairs", opts = {} },

  -- LSP & Auto-Completion
  { "williamboman/mason.nvim", opts = {} },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      local servers = { "clangd", "pyright", "lua_ls" }
      require("mason-lspconfig").setup({
        ensure_installed = servers,
        automatic_installation = false,
      })
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
      for _, server_name in ipairs(servers) do
        local config = { capabilities = capabilities }
        if server_name == "lua_ls" then
          config.settings = { Lua = { diagnostics = { globals = { "vim" } } } }
        end
        if vim.fn.has("nvim-0.11") == 1 then
          vim.lsp.config(server_name, config)
          vim.lsp.enable(server_name)
        else
          require("lspconfig")[server_name].setup(config)
        end
      end
    end
  },
  { "neovim/nvim-lspconfig" },
  { "mrcjkb/rustaceanvim", version = "^4", ft = { "rust" } },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer", "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip", "saadparwaiz1/cmp_luasnip"
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        snippet = { expand = function(args) require("luasnip").lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping.select_next_item(),
          ["<S-Tab>"] = cmp.mapping.select_prev_item(),
        }),
        sources = {
          { name = "nvim_lsp" }, { name = "luasnip" }, { name = "buffer" }, { name = "path" },
        },
      })
    end
  },

  -- Debugging & Linting
  {
    "mfussenegger/nvim-dap",
    config = function()
      local dap = require("dap")
      dap.adapters.gdb = { type = 'executable', command = 'gdb', args = { '-i', 'dap' } }
      dap.configurations.c = {{
        name = "Launch", type = "gdb", request = "launch",
        program = function() return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file') end,
        cwd = "${workspaceFolder}",
      }}
      dap.configurations.cpp = dap.configurations.c
    end
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end
    end
  },
  {
    "nvimtools/none-ls.nvim",
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.clang_format,
          null_ls.builtins.diagnostics.cppcheck,
        },
      })
    end
  },
})

-- ── Keymaps ──────────────────────────────────────────────
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostics' })
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })

vim.keymap.set('n', '<leader>d', function() require("dap").continue() end, { desc = 'Debug: Start/Continue' })
vim.keymap.set('n', '<leader>db', function() require("dap").toggle_breakpoint() end, { desc = 'Debug: Toggle Breakpoint' })
vim.keymap.set('n', '<leader>du', function() require("dapui").toggle() end, { desc = 'Debug: Toggle UI' })

vim.keymap.set('n', '<leader>ff', function() require('telescope.builtin').find_files() end, { desc = 'Find Files' })
vim.keymap.set('n', '<leader>fg', function() require('telescope.builtin').live_grep() end, { desc = 'Grep Files' })
vim.keymap.set('n', '<leader>fb', function() require('telescope.builtin').buffers() end, { desc = 'Find Buffers' })
