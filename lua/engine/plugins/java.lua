-- Java, via nvim-jdtls.
--
-- Same division of labour as Rust: nvim-jdtls owns the language server end to
-- end, so there is deliberately no jdtls block in lspconfig.lua and jdtls is
-- excluded from mason-lspconfig's automatic_enable (see lsp/mason.lua) -- two
-- clients on one buffer is the failure mode.
--
-- The reason jdtls needs a dedicated plugin rather than a vim.lsp.config entry
-- is that eclipse.jdt.ls is not a plain language server:
--
--   * it keeps a persistent per-project workspace on disk and must be told
--     where, or projects silently share one and confuse each other
--   * it loads extra *bundles* (java-debug-adapter, java-test) as OSGi plugins
--     to provide debugging and test running at all
--   * the useful operations -- organize imports, extract variable/method,
--     generate constructors, the test runner -- are custom LSP extensions with
--     no standard equivalent
--
-- The actual start-up lives in ftplugin/java.lua, which is how nvim-jdtls is
-- designed to be driven: once per Java buffer, so each project gets its own
-- server rooted correctly. This file only declares the dependency.

return {
	{
		"mfussenegger/nvim-jdtls",
		-- Loaded on demand by ftplugin/java.lua, which calls lazy's loader
		-- explicitly rather than relying on this `ft` alone: lazy.nvim's
		-- FileType handler and runtime ftplugin sourcing both fire on the same
		-- event, and the order between them is not guaranteed. Without the
		-- explicit load, opening the very first Java file of a session can
		-- find the module missing and quietly start no server at all.
		ft = "java",
		dependencies = {
			-- Reused, not installed: both are already in this config.
			"mfussenegger/nvim-dap", -- engine.plugins.dap
			"hrsh7th/cmp-nvim-lsp",  -- engine.plugins.nvim-cmp
		},
	},
}
