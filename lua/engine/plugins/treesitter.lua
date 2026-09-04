return {
	"nvim-treesitter/nvim-treesitter",
	branch = "master",
	event = { "BufReadPre", "BufNewFile" },
	build = ":TSUpdate",
	dependencies = {
		"windwp/nvim-ts-autotag",
	},
	config = function()
		local disable_markdown = vim.fn.has("nvim-0.12") == 1

		-- nvim-treesitter ships a Haskell parser, but not separate parsers for
		-- literate Haskell or Cabal files.
		vim.treesitter.language.register("haskell", "lhaskell")

		-- Neovim core calls `vim.treesitter.start()` directly on the LSP hover
		-- popup (markdown filetype), bypassing nvim-treesitter's own
		-- enable/disable config above. nvim-treesitter's markdown injection
		-- query then crashes in `set-lang-from-info-string!`: it assumes
		-- `match[capture_id]` is a bare TSNode (via a now-defunct `all=false`
		-- compat opt), but this Neovim's query engine always hands directives
		-- `table<integer, TSNode[]>` (a list per capture, per core's own
		-- `offset!` handler). Re-register a version that unwraps the list
		-- instead of calling `:range()` on it, so a fenced code block in
		-- hover docs can't take down the UI.
		do
			local non_filetype_match_injection_language_aliases = {
				ex = "elixir",
				pl = "perl",
				sh = "bash",
				uxn = "uxntal",
				ts = "typescript",
			}

			require("nvim-treesitter.query_predicates")

			vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
				local captured = match[pred[2]]
				local node = type(captured) == "table" and captured[#captured] or captured
				if type(node) ~= "userdata" then
					return
				end

				local ok, text = pcall(vim.treesitter.get_node_text, node, bufnr)
				if not ok then
					return
				end

				local injection_alias = text:lower()
				local filetype = vim.filetype.match({ filename = "a." .. injection_alias })
				metadata["injection.language"] = filetype
					or non_filetype_match_injection_language_aliases[injection_alias]
					or injection_alias
			end, { force = true })
		end

		-- The module that owns highlight/indent/autotag/ensure_installed on the
		-- master branch. `require("nvim-treesitter")` also has a setup(), but it
		-- is a different, internal one that silently ignores every option below
		-- -- which is why no parser was ever installed and highlighting was off
		-- for every language except the handful Neovim bundles.
		local treesitter = require("nvim-treesitter.configs")

		treesitter.setup({
			-- enable syntax highlighting
			highlight = {
				enable = true,
				disable = disable_markdown and { "markdown", "markdown_inline" } or {},
			},
			-- Treesitter indent can override normal `o`/`O` newline indent behavior.
			indent = { enable = false },
			-- NOTE: autotag is NOT configured here. nvim-ts-autotag dropped its
			-- nvim-treesitter module integration, so an `autotag` key in this
			-- table is silently ignored -- it never registered the insert-mode
			-- `>` and `/` maps that close a tag. It is set up below instead.
			-- ensure these language parsers are installed
			ensure_installed = {
				"json",
				"javascript",
				"typescript",
				"tsx",
				"yaml",
				"html",
				"css",
				"prisma",
				"markdown",
				"markdown_inline",
				"svelte",
				"graphql",
				"bash",
				"lua",
				"vim",
				"dockerfile",
				"gitignore",
				"query",
				"vimdoc",
				"c",
				"cpp",
				"haskell",
				"gdscript",
				"gdshader",
				"godot_resource",
				-- C# / .NET: c_sharp for sources, xml for .csproj/.props/.slnx,
				-- sql for the scripts EF migrations generate.
				"c_sharp",
				"xml",
				"sql",
				-- React / TypeScript. tsx covers .tsx and .jsx; typescript
				-- covers .ts. jsdoc and regex are injected into both, and
				-- scss/styled cover the CSS side of a component tree.
				"jsdoc",
				"regex",
				"scss",
				-- Rust, plus the toml that Cargo.toml and rustfmt.toml are.
				"rust",
				"toml",
				-- PHP / Laravel. phpdoc is injected into php docblocks; the
				-- blade parser is registered separately below because
				-- nvim-treesitter does not ship one.
				"php",
				"phpdoc",
			},
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<C-space>",
					node_incremental = "<C-space>",
					scope_incremental = false,
					node_decremental = "<bs>",
				},
			},
		})

		-- Auto-close and auto-rename HTML/JSX tags. Typing `<div>` writes the
		-- closing `</div>`; editing either half renames the other. Note this is
		-- NOT configurable via nvim-treesitter's `autotag` key any more -- the
		-- plugin dropped that integration, so it needs its own setup() call.
		require("nvim-ts-autotag").setup({
			opts = {
				enable_close = true,
				enable_rename = true,
				-- Off by default upstream: typing `/` anywhere would try to
				-- close a tag, which misfires in attribute values and URLs.
				enable_close_on_slash = false,
			},
			-- html, xml, jsx/tsx, svelte, php, blade and markdown are built in
			-- and need no aliases. Razor (.cshtml) is deliberately absent: the
			-- plugin drives every edit off a treesitter parse, and nvim-treesitter
			-- ships no razor parser, so an alias registers but never fires.
		})
	end,
}
