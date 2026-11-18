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
			-- Vue Language Tools 3: vue_ls handles SFC template/style regions
			-- and ships the @vue/typescript-plugin loaded by ts_ls.
			"vue_ls",
			"html",
			"cssls",
			"tailwindcss",
			"svelte",
			"lua_ls",
			"graphql",
			"emmet_ls",
			"pyright",
			"clangd",
			"gopls",
			-- jdtls. Started by ftplugin/java.lua via nvim-jdtls, not by
			-- mason (see the automatic_enable exclusion below).
			--
			-- Java debugging and test running need two further Mason packages
			-- that are NOT language servers, so mason-lspconfig's
			-- ensure_installed cannot carry them:
			--
			--     :MasonInstall java-debug-adapter java-test
			--
			-- ftplugin/java.lua globs their jars and passes them to jdtls as
			-- OSGi bundles; without java-debug-adapter there is no `java` DAP
			-- adapter at all.
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
			"ols",
			-- Graphics / game development. glsl_analyzer serves the GLSL in
			-- opengl-cpp/shaders and anything else with a .vert/.frag/.comp
			-- extension; wgsl_analyzer serves the WGSL that Bevy and wgpu use.
			-- neocmake handles CMakeLists.txt for the C/C++ projects.
			"glsl_analyzer",
			"wgsl_analyzer",
			"neocmake",
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
					-- Same story for jdtls, which is started by
					-- ftplugin/java.lua through nvim-jdtls. That is not
					-- optional for Java: eclipse.jdt.ls needs a per-project
					-- `-data` workspace and the java-debug/java-test bundles
					-- passed at start-up, none of which a plain
					-- vim.lsp.enable() provides. Left to itself mason would
					-- start a second, bundle-less server on every Java buffer.
					"jdtls",
					-- rustaceanvim is intentionally disabled in this config. Mason
					-- must not start a resident rust-analyzer behind its back merely
					-- because the package remains installed from an earlier setup.
					"rust_analyzer",
				},
			},
		})
	end,
}
