return {
	"nvim-telescope/telescope.nvim",
	branch = "0.1.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
		"nvim-tree/nvim-web-devicons",
	},
	config = function()
		local telescope = require("telescope")
		local actions = require("telescope.actions")

		-- Directories that are never worth searching, per stack. These become
		-- anchored Lua patterns below.
		--
		-- The previous list here was { "node_modules", "vendor", "build",
		-- "%.git" } -- bare substrings matched anywhere in the path. Lua's
		-- find() is not anchored, so "vendor" silently swallowed
		-- src/vendorList.ts and "build" swallowed src/buildConfig.ts: you
		-- searched, got nothing, and concluded the code did not exist. Matching
		-- whole path segments is the fix.
		local ignored_dirs = {
			".git",
			"node_modules",
			"vendor", -- composer (Laravel), go
			"target", -- cargo
			-- .NET build output. Spelled out rather than a bare "bin",
			-- because src/bin/ is where a Rust crate keeps its extra
			-- binaries and app/bin/ is real source in plenty of trees.
			"bin/Debug",
			"bin/Release",
			"obj/Debug",
			"obj/Release",
			"dist",
			"build",
			".next",
			".nuxt",
			".svelte-kit",
			".venv",
			"__pycache__",
			".turbo",
			"storage/framework", -- Laravel compiled blade views + caches
		}

		---A path segment, not a substring: matches `foo/<dir>/bar` and
		---`<dir>/bar`, but never `vendorList.ts`.
		local function segment_patterns(dirs)
			local patterns = {}
			for _, dir in ipairs(dirs) do
				local escaped = dir:gsub("([%.%-%+%*%?%[%]%^%$%(%)%%])", "%%%1")
				patterns[#patterns + 1] = "/" .. escaped .. "/"
				patterns[#patterns + 1] = "^" .. escaped .. "/"
			end
			-- Lockfiles and minified bundles: huge, generated, never the answer.
			patterns[#patterns + 1] = "%.min%.js$"
			patterns[#patterns + 1] = "%.min%.css$"
			patterns[#patterns + 1] = "%.lock$"
			patterns[#patterns + 1] = "package%-lock%.json$"
			patterns[#patterns + 1] = "composer%.lock$"
			return patterns
		end

		-- ripgrep respects .gitignore already; --hidden is what it will not do
		-- on its own, and without it you cannot grep .env, .github/workflows,
		-- .eslintrc or any other dotfile -- which is most of a project's
		-- configuration. .git itself still has to be excluded by hand.
		local rg_arguments = {
			"rg",
			"--color=never",
			"--no-heading",
			"--with-filename",
			"--line-number",
			"--column",
			"--smart-case",
			"--hidden",
			"--glob=!**/.git/*",
		}

		telescope.setup({
			defaults = {
				vimgrep_arguments = rg_arguments,
				file_ignore_patterns = segment_patterns(ignored_dirs),
				path_display = { "smart" },
				mappings = {
					i = {
						["<C-k>"] = actions.move_selection_previous,
						["<C-j>"] = actions.move_selection_next,
						["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
						["<C-t>"] = require("trouble.sources.telescope").open,
						-- Step through the query history of this picker type.
						["<C-Up>"] = actions.cycle_history_prev,
						["<C-Down>"] = actions.cycle_history_next,
					},
				},
			},
			pickers = {
				find_files = {
					-- Same reasoning as --hidden above: a config file you cannot
					-- open by name is a config file you edit by `:e` and a
					-- guess.
					hidden = true,
					no_ignore = false,
				},
				live_grep = {
					additional_args = { "--hidden" },
				},
				grep_string = {
					additional_args = { "--hidden" },
				},
				buffers = {
					sort_mru = true,
					ignore_current_buffer = true,
				},
			},
		})

		telescope.load_extension("fzf")

		local keymap = vim.keymap
		keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Fuzzy find recent files" })
		keymap.set("n", "<leader>fw", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
		keymap.set("n", "<leader>fc", "<cmd>Telescope grep_string<cr>", {
			desc = "Find string under cursor in cwd",
		})

		-- Search everything, including the directories ignored above and the
		-- files .gitignore hides. For when you actually do need to read
		-- something inside vendor/ or node_modules/.
		keymap.set("n", "<leader>fW", function()
			require("telescope.builtin").live_grep({
				additional_args = { "--hidden", "--no-ignore" },
				file_ignore_patterns = { "/%.git/" },
			})
		end, { desc = "Live grep everything (incl. ignored dirs)" })

		keymap.set("n", "<leader>fF", function()
			require("telescope.builtin").find_files({
				hidden = true,
				no_ignore = true,
				file_ignore_patterns = { "/%.git/" },
			})
		end, { desc = "Find files everywhere (incl. ignored dirs)" })

		keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Find open buffers" })
		keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Search help" })
		keymap.set("n", "<leader>fk", "<cmd>Telescope keymaps<cr>", { desc = "Search keymaps" })
		keymap.set("n", "<leader>fd", "<cmd>Telescope diagnostics<cr>", { desc = "Workspace diagnostics" })
		keymap.set("n", "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "Document symbols" })
		keymap.set("n", "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", {
			desc = "Workspace symbols",
		})
		-- Reopens the last picker with its query and cursor position intact --
		-- the one you miss most after accidentally hitting <Esc>.
		keymap.set("n", "<leader>fr", "<cmd>Telescope resume<cr>", { desc = "Resume last picker" })
	end,
}
