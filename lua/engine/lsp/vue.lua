-- Vue 3 / Nuxt 4 language intelligence.
--
-- Vue Language Tools 3 runs in hybrid mode: vue_ls owns the template, style,
-- and SFC structure while a TypeScript server owns <script> and the virtual
-- TypeScript files generated from the template. Both clients must attach to a
-- .vue buffer, and ts_ls must load @vue/typescript-plugin so it understands
-- those virtual files.

local M = {}

local typescript_filetypes = {
	"javascript",
	"javascriptreact",
	"typescript",
	"typescriptreact",
	"vue",
}

local nuxt_root_markers = {
	"nuxt.config.ts",
	"nuxt.config.js",
	"nuxt.config.mjs",
	"nuxt.config.mts",
}

function M.setup(opts)
	opts = opts or {}

	local vue_language_server_path = vim.fn.stdpath("data")
		.. "/mason/packages/vue-language-server/node_modules/@vue/language-server"

	local vue_typescript_plugin = {
		name = "@vue/typescript-plugin",
		location = vue_language_server_path,
		languages = { "vue" },
		configNamespace = "typescript",
	}

	vim.lsp.config("ts_ls", {
		capabilities = opts.capabilities,
		on_attach = opts.on_attach,
		filetypes = typescript_filetypes,
		init_options = {
			plugins = { vue_typescript_plugin },
		},
		settings = opts.ts_settings,
	})

	vim.lsp.config("vue_ls", {
		capabilities = opts.capabilities,
		on_attach = opts.on_attach,
		filetypes = { "vue" },
		-- Nested lists are priority groups. A Nuxt application inside a
		-- monorepo must root at its own nuxt.config.* before a package.json or
		-- the outer .git directory is considered.
		root_markers = {
			nuxt_root_markers,
			{
				"vite.config.ts",
				"vite.config.js",
				"vite.config.mjs",
				"vite.config.mts",
				"vite.config.cjs",
				"vite.config.cts",
			},
			{ "package.json", "tsconfig.json", "jsconfig.json" },
			{ ".git" },
		},
	})

	vim.lsp.enable("ts_ls")
	vim.lsp.enable("vue_ls")
end

return M
