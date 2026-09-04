return {
	"williamboman/mason.nvim",
	dependencies = {
		"williamboman/mason-lspconfig.nvim",
	},
	config = function()
		-- import mason
		local mason = require("mason")

		-- import mason-lspconfig
		local mason_lspconfig = require("mason-lspconfig")

		-- enable mason and configure icons
		mason.setup({
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		})

		local ensure_installed = {
			"ts_ls",
			"html",
			"cssls",
			"tailwindcss",
			"svelte",
			"lua_ls",
			"graphql",
			"emmet_ls",
			"pyright",
			"clangd",
			"rust_analyzer",
			"gopls",
			"jdtls",
			-- C# is served by the Roslyn language server, which is a .NET
			-- global tool rather than a mason package -- see
			-- engine.plugins.lsp.roslyn for the install line. OmniSharp used
			-- to sit here; it was retired upstream.
			"intelephense",
			"marksman",
			"jsonls",
			"taplo",
			"bashls",
			"zls",
		}

		mason_lspconfig.setup({
			-- list of servers for mason to install
			ensure_installed = ensure_installed,

			-- mason-lspconfig v2 calls vim.lsp.enable() for every server it
			-- finds installed, whether or not it is listed above. OmniSharp was
			-- installed here historically, and left to itself it attaches to
			-- .cs buffers alongside the Roslyn server -- two C# servers racing
			-- on the same file, with OmniSharp throwing INVALID_SERVER_MESSAGE.
			-- It has been uninstalled; this keeps it from coming back by
			-- accident.
			automatic_enable = {
				exclude = {
					-- Retired upstream, and it raced the Roslyn server on
					-- every .cs buffer while throwing INVALID_SERVER_MESSAGE.
					"omnisharp",
					-- rust_analyzer is started and configured by rustaceanvim
					-- (engine.plugins.rust). Letting mason enable it too puts
					-- two rust-analyzer clients on every Rust buffer: doubled
					-- memory and CPU on a cargo check, and duplicated
					-- diagnostics.
					"rust_analyzer",
				},
			},
		})
	end,
}
