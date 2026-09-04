-- Git.
--
-- Three layers, each doing the job the one below it cannot:
--
--   gitsigns    what changed in THIS buffer, and who wrote each line.
--               Gutter signs, hunk staging/preview/navigation, and the inline
--               blame that GitLens does in VS Code.
--   diffview    what changed across a RANGE -- a branch, a PR, a merge
--               conflict -- as a proper side-by-side review UI.
--   lazygit     everything else git does: staging, committing, rebasing,
--               stashing, branch and remote management. A full TUI, launched
--               in a float via snacks.nvim.
--
-- Everything is under <leader>g, which was entirely unused.

return {
	-- ---------------------------------------------------------------------
	-- gitsigns: per-buffer changes and per-line blame
	-- ---------------------------------------------------------------------
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			signs_staged_enable = true,

			-- This is the GitLens "inline blame" equivalent: virtual text at
			-- the end of the current line saying who last touched it, when,
			-- and why. It follows the cursor.
			current_line_blame = true,
			current_line_blame_opts = {
				virt_text = true,
				virt_text_pos = "eol",
				delay = 300,
				ignore_whitespace = true,
			},
			current_line_blame_formatter = "  <author>, <author_time:%R> · <summary>",
			-- What it shows on a line you have not committed yet.
			current_line_blame_formatter_nc = "  uncommitted",

			preview_config = { border = "rounded" },

			on_attach = function(bufnr)
				local gs = require("gitsigns")

				local function map(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
				end

				-- Navigation. Inside a diff these fall through to plain ]c/[c
				-- so the same keys work in :Gdiff and in merge conflicts.
				map("n", "]h", function()
					if vim.wo.diff then
						vim.cmd.normal({ "]c", bang = true })
					else
						gs.nav_hunk("next")
					end
				end, "Next hunk")

				map("n", "[h", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gs.nav_hunk("prev")
					end
				end, "Previous hunk")

				-- Blame
				map("n", "<leader>gb", gs.blame_line, "Blame line (popup)")
				map("n", "<leader>gB", function()
					gs.blame_line({ full = true })
				end, "Blame line (full, with the diff)")
				map("n", "<leader>gL", gs.blame, "Blame whole file (side pane)")
				map("n", "<leader>gt", gs.toggle_current_line_blame, "Toggle inline blame")

				-- Hunks
				map("n", "<leader>gs", gs.stage_hunk, "Stage hunk")
				map("n", "<leader>gr", gs.reset_hunk, "Reset hunk")
				map("v", "<leader>gs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "Stage selected lines")
				map("v", "<leader>gr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "Reset selected lines")
				map("n", "<leader>gp", gs.preview_hunk_inline, "Preview hunk inline")
				map("n", "<leader>gP", gs.preview_hunk, "Preview hunk (float)")
				map("n", "<leader>gu", gs.undo_stage_hunk, "Undo stage hunk")
				map("n", "<leader>gS", gs.stage_buffer, "Stage whole buffer")
				map("n", "<leader>gR", gs.reset_buffer, "Reset whole buffer")

				-- Diff this file against the index, or against a revision.
				map("n", "<leader>gd", gs.diffthis, "Diff this file")
				map("n", "<leader>gD", function()
					gs.diffthis("~")
				end, "Diff this file against HEAD~")

				-- Send every hunk in the buffer to the quickfix list.
				map("n", "<leader>gq", function()
					gs.setqflist("all")
				end, "All hunks in repo to quickfix")

				-- ih = "in hunk": `dih` deletes a hunk, `vih` selects one.
				map({ "o", "x" }, "ih", gs.select_hunk, "Select hunk")
			end,
		},
	},

	-- ---------------------------------------------------------------------
	-- diffview: reviewing a range of commits, and resolving conflicts
	-- ---------------------------------------------------------------------
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles" },
		opts = {
			enhanced_diff_hl = true,
			view = {
				-- Three-way view on a conflict: OURS | RESULT | THEIRS, which
				-- is the only sane way to resolve a merge in an editor.
				merge_tool = {
					layout = "diff3_mixed",
					disable_diagnostics = true,
				},
			},
			file_panel = {
				listing_style = "tree",
				win_config = { width = 32 },
			},
		},
		keys = {
			{ "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree" },
			{ "<leader>gV", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
			{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "History of this file" },
			{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "History of this branch" },
			{
				"<leader>gh",
				"<Esc><cmd>'<,'>DiffviewFileHistory<cr>",
				mode = "v",
				desc = "History of the selected lines",
			},
			{
				"<leader>gm",
				"<cmd>DiffviewOpen origin/HEAD...HEAD<cr>",
				desc = "Diffview: this branch vs main",
			},
		},
	}
}
