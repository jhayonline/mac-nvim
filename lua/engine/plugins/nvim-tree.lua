return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local nvimtree = require("nvim-tree")

    local hide_root_files = false

    nvimtree.setup({
      sync_root_with_cwd = true,
      respect_buf_cwd = false,
      update_focused_file = {
        enable = true,
        update_root = false,
      },
      view = {
        side = "left",
        width = 35,
        preserve_window_proportions = true,
      },
      actions = {
        open_file = {
          quit_on_open = false,
          resize_window = true,
        },
      },
      renderer = {
        highlight_opened_files = "all",
      },
      -- Git status in the tree: a colour and a badge per file, and the
      -- parent folders of anything modified. This was off, which meant the
      -- tree gave no hint that a file had uncommitted work in it.
      git = {
        enable = true,
        show_on_dirs = true,
        show_on_open_dirs = false,
        timeout = 500,
      },
      modified = {
        enable = true,
        show_on_dirs = true,
      },
      tab = {
        sync = {
          open = false,
          close = false,
          ignore = {},
        },
      },
    })

    local keymap = vim.keymap

    keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle file explorer" })
    keymap.set("n", "<C-n>", "<cmd>NvimTreeFocus<CR>", { desc = "Focus file explorer" })
  end,
}
