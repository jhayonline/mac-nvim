-- Rust, via rustaceanvim.
--
-- rustaceanvim owns rust_analyzer end to end: it starts the server itself
-- (so there is deliberately no rust_analyzer block in lspconfig.lua -- two
-- clients on one buffer is the failure mode) and layers the things
-- rust-analyzer exposes over LSP extensions rather than standard methods:
-- runnables, debuggables, macro expansion, HIR/MIR views, `rustc --explain`.
--
-- It is configured through `vim.g.rustaceanvim` rather than a setup() call,
-- and must be set before the plugin loads -- hence `init`, not `config`.
--
-- Cargo.toml gets its own treatment from crates.nvim below.

return {
	{
		"mrcjkb/rustaceanvim",
		version = "^7",
		lazy = false, -- the plugin is a filetype plugin; it lazy-loads itself
		ft = { "rust" },

		init = function()
			local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"

			-- codelldb ships as a VS Code extension: rustaceanvim needs the
			-- adapter binary and the bundled liblldb, not the shim script.
			local extension = mason_bin .. "/../packages/codelldb/extension"
			local codelldb = extension .. "/adapter/codelldb"
			local liblldb = extension .. "/lldb/lib/liblldb.dylib"

			vim.g.rustaceanvim = {
				tools = {
					-- Inline the first error of a line rather than only in the
					-- float, and use Telescope for the LSP pickers so it
					-- matches the rest of the config.
					float_win_config = { border = "rounded" },
					test_executor = "background",
				},

				server = {
					on_attach = function(client, bufnr)
						-- Same story as C# and TypeScript: the shared
						-- LspAttach handler in lspconfig.lua guards inlay
						-- hints behind a misspelled capability key, so opt in
						-- explicitly here.
						if client:supports_method("textDocument/inlayHint") then
							vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
						end

						local map = function(lhs, rhs, desc)
							vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
						end

						-- rust-analyzer's code actions and hover are richer
						-- than the LSP defaults, so route the two keys you
						-- already use through rustaceanvim inside Rust files.
						map("<leader>ca", function()
							vim.cmd.RustLsp("codeAction")
						end, "Rust code actions")
						map("K", function()
							vim.cmd.RustLsp({ "hover", "actions" })
						end, "Rust hover actions")

						map("<leader>rr", function()
							vim.cmd.RustLsp("runnables")
						end, "Rust runnables")
						map("<leader>rd", function()
							vim.cmd.RustLsp("debuggables")
						end, "Rust debuggables")
						map("<leader>rt", function()
							vim.cmd.RustLsp("testables")
						end, "Rust testables")
						map("<leader>rm", function()
							vim.cmd.RustLsp("expandMacro")
						end, "Expand macro")
						map("<leader>rc", function()
							vim.cmd.RustLsp("openCargo")
						end, "Open Cargo.toml")
						map("<leader>re", function()
							vim.cmd.RustLsp("explainError")
						end, "Explain error under cursor")
						map("<leader>rD", function()
							vim.cmd.RustLsp("renderDiagnostic")
						end, "Render full diagnostic")
					end,

					default_settings = {
						["rust-analyzer"] = {
							-- Note the camelCase: the old lspconfig block used
							-- all-lowercase keys ("inlayhints", "typehints"),
							-- which rust-analyzer silently ignored -- none of
							-- those settings were ever in effect.
							cargo = {
								allFeatures = true,
								loadOutDirsFromCheck = true,
								buildScripts = { enable = true },
							},

							-- Clippy instead of plain `cargo check` on save.
							-- This is the single biggest quality win: you get
							-- the lint suggestions, not just type errors.
							checkOnSave = true,
							check = {
								command = "clippy",
								extraArgs = { "--no-deps" },
							},

							procMacro = {
								enable = true,
								ignored = {
									-- These generate code rust-analyzer cannot
									-- follow and which slow the index down.
									["async-trait"] = { "async_trait" },
									["napi-derive"] = { "napi" },
								},
							},

							inlayHints = {
								bindingModeHints = { enable = false },
								chainingHints = { enable = true },
								closingBraceHints = { enable = true, minLines = 25 },
								closureReturnTypeHints = { enable = "never" },
								lifetimeElisionHints = { enable = "never", useParameterNames = false },
								maxLength = 25,
								parameterHints = { enable = true },
								reborrowHints = { enable = "never" },
								renderColons = true,
								typeHints = { enable = true, hideClosureInitialization = false, hideNamedConstructor = false },
							},

							diagnostics = {
								enable = true,
								experimental = { enable = true },
								-- `unlinked-file` fires on every scratch .rs
								-- outside a cargo project and is pure noise.
								disabled = { "unlinked-file" },
							},

							files = {
								excludeDirs = { ".git", "target", "node_modules" },
							},
						},
					},
				},

				dap = {
					adapter = (vim.fn.executable(codelldb) == 1 and vim.fn.filereadable(liblldb) == 1)
							and require("rustaceanvim.config").get_codelldb_adapter(codelldb, liblldb)
						or nil,
				},
			}
		end,
	},

	{
		-- Cargo.toml as a first-class file: latest versions in virtual text,
		-- completion for crate names and versions, and feature lists.
		"saecki/crates.nvim",
		event = { "BufRead Cargo.toml" },
		opts = {
			completion = {
				-- Completion arrives through the in-process language server
				-- below, not through a dedicated nvim-cmp source: the
				-- `completion.cmp` route is deprecated upstream and warns on
				-- every Cargo.toml you open.
				crates = { enabled = true },
			},
			lsp = {
				enabled = true,
				actions = true,
				completion = true,
				hover = true,
			},
		},
		config = function(_, opts)
			require("crates").setup(opts)

			vim.api.nvim_create_autocmd("BufRead", {
				group = vim.api.nvim_create_augroup("EngineCrates", { clear = true }),
				pattern = "Cargo.toml",
				callback = function(args)
					local crates = require("crates")
					local map = function(lhs, rhs, desc)
						vim.keymap.set("n", lhs, rhs, { buffer = args.buf, silent = true, desc = desc })
					end

					map("<leader>rc", crates.show_popup, "Crate details")
					map("<leader>rf", crates.show_features_popup, "Crate features")
					map("<leader>rv", crates.show_versions_popup, "Crate versions")
					map("<leader>ru", crates.update_crate, "Update crate")
					map("<leader>rU", crates.upgrade_crate, "Upgrade crate (allow major)")
					map("<leader>rA", crates.upgrade_all_crates, "Upgrade all crates")
					map("K", crates.show_popup, "Crate details")
				end,
			})
		end,
	},
}
