return {
  {
    "barrett-ruth/live-server.nvim",
    cmd = { "LiveServerStart", "LiveServerStop", "LiveServerToggle" },
    keys = {
      { "<leader>p", "<cmd>LiveServer<CR>", desc = "Toggle live server (preview)" },
      { "<leader>P", "<cmd>LiveServer stop<CR>", desc = "Stop live server" },
    },
    init = function()
      -- v0.2.0 dropped setup(); config lives here and must be set before load.
      vim.g.live_server = {
        port = 5500,
        browser = true,
        css_inject = true,
      }

      -- Defined at startup so `:LiveServer` exists before the plugin is loaded;
      -- dispatching to LiveServer{Start,Stop,Toggle} trips lazy's cmd stub.
      local actions = {
        start = "LiveServerStart",
        stop = "LiveServerStop",
        toggle = "LiveServerToggle",
      }

      vim.api.nvim_create_user_command("LiveServer", function(opts)
        local action = opts.args ~= "" and opts.args or "toggle"
        local cmd = actions[action]
        if not cmd then
          vim.notify("LiveServer: unknown action '" .. action .. "'", vim.log.levels.ERROR)
          return
        end
        vim.cmd(cmd)
      end, {
        nargs = "?",
        desc = "Live server: toggle (default), start, or stop",
        complete = function(lead)
          return vim.tbl_filter(function(a)
            return a:find(lead, 1, true) == 1
          end, vim.tbl_keys(actions))
        end,
      })
    end,
  },
}
