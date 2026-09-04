-- snacks.nvim is already a dependency of several plugins here; these are the
-- modules worth turning on explicitly.
--
-- lazygit is the "everything else" layer of the git setup (see
-- engine.plugins.git): staging, committing, rebasing, stashing, branches and
-- remotes, in a full TUI floated over the editor. snacks launches it with the
-- repo of the current buffer as cwd and reloads any buffer it changed on exit,
-- which is the part a bare `:terminal lazygit` gets wrong.

return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,

	opts = {
		lazygit = {
			-- Inherit the editor's colours rather than lazygit's own theme, so
			-- it matches whatever :Theme you are on.
			configure = true,
			win = {
				style = "lazygit",
				width = 0,
				height = 0,
			},
		},

		-- Open the current file, line or selection on github.com in a browser.
		-- Resolves the remote and the current commit, so the link is
		-- permanent rather than a moving branch reference.
		gitbrowse = {},

		-- A read-only pane showing the file as of a given revision.
		git = {},

		-- Notifications routed through snacks so :Dotnet*/:Artisan* output and
		-- LSP progress do not fight over the message area.
		notifier = { enabled = true, timeout = 3000 },

		-- Keeps window layout stable when the last buffer is deleted.
		bufdelete = {},
	},

	keys = {
		{
			"<leader>gg",
			function()
				require("snacks").lazygit()
			end,
			desc = "Lazygit (repo of current file)",
		},
		{
			"<leader>gl",
			function()
				require("snacks").lazygit.log()
			end,
			desc = "Lazygit: repo log",
		},
		{
			"<leader>gf",
			function()
				require("snacks").lazygit.log_file()
			end,
			desc = "Lazygit: log of this file",
		},
		{
			"<leader>gx",
			function()
				require("snacks").gitbrowse()
			end,
			mode = { "n", "v" },
			desc = "Open this line on GitHub",
		},
	},
}
