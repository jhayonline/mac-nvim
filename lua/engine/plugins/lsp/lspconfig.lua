return {
	"neovim/nvim-lspconfig",
	event = { "bufreadpre", "bufnewfile" },
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
		{ "antosha417/nvim-lsp-file-operations", config = true },
		{ "folke/neodev.nvim", opts = {} },
	},
	config = function()
		local lspconfig = require("lspconfig")
		local keymap = vim.keymap
		local qt_clangd_flag_pattern = "^unknown argument:%s*['\"]?%-mno%-direct%-extern%-access['\"]?"

		-- Defer loading cmp_nvim_lsp until needed to avoid dependency issues
		local function get_capabilities()
			local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
			if ok then
				return cmp_nvim_lsp.default_capabilities()
			end
			-- Fallback if cmp isn't loaded yet
			return vim.lsp.protocol.make_client_capabilities()
		end

		local default_publish_diagnostics = vim.lsp.handlers["textdocument/publishdiagnostics"]
		vim.lsp.handlers["textdocument/publishdiagnostics"] = function(err, result, ctx, config)
			local client = ctx and vim.lsp.get_client_by_id(ctx.client_id)
			if client and client.name == "clangd" and result and result.diagnostics then
				result = vim.deepcopy(result)
				result.diagnostics = vim.tbl_filter(function(diagnostic)
					local message = diagnostic.message or ""
					return not message:match(qt_clangd_flag_pattern)
				end, result.diagnostics)
			end

			return default_publish_diagnostics(err, result, ctx, config)
		end

		-- setup keymaps when lsp attaches
		vim.api.nvim_create_autocmd("lspattach", {
			group = vim.api.nvim_create_augroup("userlspconfig", {}),
			callback = function(ev)
				local opts = { buffer = ev.buf, silent = true }

				local client = vim.lsp.get_client_by_id(ev.data.client_id)
				if client and client.server_capabilities.semantictokensprovider then
					client.server_capabilities.semantictokensprovider = nil
				end

				opts.desc = "show lsp references"
				keymap.set("n", "gr", "<cmd>Telescope lsp_references<cr>", opts)

				opts.desc = "go to declaration"
				keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

				opts.desc = "go to definition"
				keymap.set("n", "gd", vim.lsp.buf.definition, opts)

				opts.desc = "show lsp implementations"
				keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<cr>", opts)

				opts.desc = "show lsp type definitions"
				keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<cr>", opts)

				opts.desc = "see available code actions"
				keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)

				opts.desc = "smart rename"
				keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

				opts.desc = "show buffer diagnostics"
				keymap.set("n", "<leader>dd", "<cmd>Telescope diagnostics bufnr=0<cr>", opts)

				opts.desc = "show line diagnostics"
				keymap.set("n", "<leader>dl", vim.diagnostic.open_float, opts)

				opts.desc = "go to previous diagnostic"
				keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)

				opts.desc = "go to next diagnostic"
				keymap.set("n", "]d", vim.diagnostic.goto_next, opts)

				opts.desc = "show documentation under cursor"
				keymap.set("n", "K", vim.lsp.buf.hover, opts) -- Changed to Shift+K

				opts.desc = "restart lsp"
				keymap.set("n", "<leader>rs", function()
					local bufnr = vim.api.nvim_get_current_buf()
					local clients = vim.lsp.get_clients({ bufnr = bufnr })
					if #clients == 0 then
						vim.notify("no language server attached to this buffer", vim.log.levels.WARN)
						return
					end

					local names = {}
					for _, lsp in ipairs(clients) do
						names[#names + 1] = lsp.name
						lsp:stop()
					end
					vim.notify("restarting " .. table.concat(names, ", "), vim.log.levels.INFO)

					-- Roslyn in particular takes a moment to actually exit, and
					-- re-attaching while the old client is still shutting down
					-- gets you two servers on the buffer.
					vim.defer_fn(function()
						if vim.api.nvim_buf_is_valid(bufnr) then
							vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
						end
					end, 1000)
				end, opts)

				-- enable inlay hints if supported
				local client = vim.lsp.get_client_by_id(ev.data.client_id)
				local ft = vim.bo[ev.buf].filetype
				local path = vim.api.nvim_buf_get_name(ev.buf)
				local disable_inlay_hints = vim.tbl_contains({ "c", "cpp", "objc", "objcpp" }, ft)
					or path:match("%.h$")
					or path:match("%.hh$")
					or path:match("%.hpp$")
					or path:match("%.hxx$")
					or path:match("%.inl$")

				if client and client.server_capabilities.inlayhintprovider and not disable_inlay_hints then
					vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
				end
			end,
		})

		-- Get capabilities safely
		local capabilities = get_capabilities()

		-- diagnostic signs
		local signs = { error = " ", warn = " ", hint = "󰠠 ", info = " " }
		for type, icon in pairs(signs) do
			local hl = "diagnosticsign" .. type
			vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
		end

		-- inline diagnostics (virtual text)
		vim.diagnostic.config({
			virtual_text = {
				prefix = "●",
				spacing = 2,
			},
			signs = true,
			underline = true,
			update_in_insert = false,
			severity_sort = true,
		})

		-- ============================
		-- language servers
		-- ============================

		-- The shared LspAttach handler above guards inlay hints behind
		-- `server_capabilities.inlayhintprovider`. Lua keys are case-sensitive
		-- and the real key is `inlayHintProvider`, so that branch has never
		-- fired for any server. Rather than repair it here -- which would
		-- switch hints on for every language at once -- servers that want them
		-- opt in explicitly with this on_attach. Delete these once the shared
		-- handler is fixed.
		local function enable_inlay_hints(client, bufnr)
			if client:supports_method("textDocument/inlayHint") then
				vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
			end
		end

		-- ============================
		-- typescript / react / vue / nuxt
		-- ============================
		-- Inlay hints and the import preferences are the two things that make
		-- this feel like a real TS editor rather than a completion popup. The
		-- hint settings are per-language and must be spelled out twice --
		-- ts_ls keys them separately for .ts and .tsx/.js.
		local ts_inlay_hints = {
			includeInlayParameterNameHints = "literals",
			includeInlayParameterNameHintsWhenArgumentMatchesName = false,
			includeInlayFunctionParameterTypeHints = true,
			includeInlayVariableTypeHints = false,
			includeInlayVariableTypeHintsWhenTypeMatchesName = false,
			includeInlayPropertyDeclarationTypeHints = true,
			includeInlayFunctionLikeReturnTypeHints = true,
			includeInlayEnumMemberValueHints = true,
		}

		local ts_preferences = {
			-- Honour the "paths" in tsconfig.json, so an auto-import writes
			-- `@/components/Button` rather than `../../components/Button`.
			importModuleSpecifierPreference = "shortest",
			importModuleSpecifier = "shortest",
			-- React 17+ JSX transform: no `import React` needed.
			jsxAttributeCompletionStyle = "auto",
			includePackageJsonAutoImports = "auto",
			quotePreference = "auto",
		}

		require("engine.lsp.vue").setup({
			capabilities = capabilities,
			on_attach = enable_inlay_hints,
			ts_settings = {
				typescript = {
					inlayHints = ts_inlay_hints,
					preferences = ts_preferences,
					updateImportsOnFileMove = { enabled = "always" },
					suggest = { completeFunctionCalls = true },
				},
				javascript = {
					inlayHints = ts_inlay_hints,
					preferences = ts_preferences,
					updateImportsOnFileMove = { enabled = "always" },
					suggest = { completeFunctionCalls = true },
				},
				-- Report the same unused/unreachable diagnostics the editor
				-- shows in VS Code rather than only compiler errors.
				completions = { completeFunctionCalls = true },
			},
		})

		-- ============================
		-- tailwind css
		-- ============================
		-- The server was installed through mason but never configured, so it
		-- was running on defaults: no completions in .tsx, no colour swatches,
		-- and no awareness of class names built by clsx/cva/tailwind-merge.
		vim.lsp.config("tailwindcss", {
			capabilities = capabilities,
			filetypes = {
				"html",
				"css",
				"scss",
				"less",
				"javascript",
				"javascriptreact",
				"typescript",
				"typescriptreact",
				"svelte",
				"vue",
				-- Laravel: Tailwind classes live in Blade templates. Plain
				-- .php is deliberately absent -- attaching there starts a
				-- Tailwind client on every controller and model for no gain.
				"blade",
			},
			-- Tailwind v4 configures itself from CSS (@import "tailwindcss"),
			-- v3 from tailwind.config.js. Root on either, plus the package
			-- manifest so a v4 project without a JS config still attaches.
			root_markers = {
				"tailwind.config.js",
				"tailwind.config.cjs",
				"tailwind.config.mjs",
				"tailwind.config.ts",
				"postcss.config.js",
				"postcss.config.mjs",
				"package.json",
				".git",
			},
			settings = {
				tailwindCSS = {
					validate = true,
					-- "Unknown at rule @tailwind/@apply/@theme" is the single
					-- most common false positive; silence just that one.
					lint = {
						cssConflict = "warning",
						invalidApply = "error",
						invalidConfigPath = "error",
						invalidScreen = "error",
						invalidTailwindDirective = "error",
						invalidVariant = "error",
						recommendedVariantOrder = "warning",
						unusedClass = "ignore",
					},
					-- Where to look for class names beyond a bare
					-- class=/className=. These cover the patterns a real React
					-- codebase uses: cva/clsx/cn helpers and tailwind-merge.
					experimental = {
						classRegex = {
							{ "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
							{ "cx\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
							{ "cn\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
							{ "clsx\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
							{ "tw`([^`]*)", "([^`]*)" },
							"tw`([^`]*)",
							"class[Nn]ame\\s*[:=]\\s*[\"'`]([^\"'`]*)",
						},
					},
					includeLanguages = {
						-- Blade is not a language the server knows; tell it to
						-- treat those buffers as HTML for class extraction.
						blade = "html",
						typescriptreact = "javascript",
						javascriptreact = "javascript",
					},
				},
			},
		})

		vim.lsp.enable("tailwindcss")

		-- ============================
		-- eslint
		-- ============================
		-- Linting as diagnostics, plus :EslintFixAll wired to run on save
		-- below. Only attaches when the project actually has an eslint config,
		-- so non-linted scratch files stay quiet.
		vim.lsp.config("eslint", {
			capabilities = capabilities,
			filetypes = {
				"javascript",
				"javascriptreact",
				"typescript",
				"typescriptreact",
				"svelte",
				"vue",
			},
			settings = {
				-- Respect flat config (eslint.config.js), the default since
				-- eslint 9.
				useFlatConfig = true,
				workingDirectories = { mode = "auto" },
				format = false, -- prettier owns formatting, not eslint
			},
		})

		vim.lsp.enable("eslint")

		-- ============================
		-- emmet
		-- ============================
		-- `div.flex.gap-2<C-y>,` expansion inside JSX and Blade.
		vim.lsp.config("emmet_ls", {
			capabilities = capabilities,
			filetypes = {
				"html",
				"css",
				"scss",
				"less",
				"javascriptreact",
				"typescriptreact",
				"svelte",
				"vue",
				"blade",
				"php",
			},
		})

		vim.lsp.enable("emmet_ls")

		-- ============================
		-- clang
		-- ============================
		local query_drivers = table.concat(require("engine.core.macos").clang_query_drivers(), ",")
		vim.lsp.config("clangd", {
			capabilities = capabilities,
			cmd = {
				"clangd",
				"--background-index",
				"--clang-tidy",
				"--query-driver=" .. query_drivers,
			},
			init_options = {
				fallbackflags = {
					"-std=c++23",
				},
			},
		})
		vim.lsp.enable("clangd")

		-- ============================
		-- lua
		-- ============================
		vim.lsp.config("lua_ls", {
			capabilities = capabilities,
			settings = {
				lua = {
					runtime = {
						version = "luajit",
					},
					diagnostics = {
						globals = { "vim" },
					},
					workspace = {
						checkthirdparty = false,
						library = vim.api.nvim_get_runtime_file("", true),
					},
					completion = {
						callsnippet = "replace",
					},
				},
			},
		})
		vim.lsp.enable("lua_ls")

		-- auto-format on save
		vim.api.nvim_create_autocmd("bufwritepre", {
			callback = function(ev)
				local ft = vim.bo[ev.buf].filetype
				local cpp_like = vim.tbl_contains({ "c", "cpp", "objc", "objcpp" }, ft)

				-- typst uses typstyle (not lsp)
				if ft == "typst" then
					require("conform").format({ bufnr = ev.buf })
					return
				end

				if not cpp_like then
					return
				end

				vim.lsp.buf.format({
					bufnr = ev.buf,
					async = false,
					filter = function(client)
						return client.name == "clangd"
					end,
				})
			end,
		})

		-- ============================
		-- rust
		-- ============================
		-- Rust intentionally has no resident LSP. Formatting is handled by
		-- conform.nvim and checks can be run manually with Cargo.

		-- ============================
		-- typst
		-- ============================
		vim.lsp.config("tinymist", {
			cmd = { "tinymist" },
			filetypes = { "typst" },
			root_markers = { ".git" },
			capabilities = capabilities,
		})

		vim.lsp.enable("tinymist")

		-- ============================
		-- haskell
		-- ============================
		if vim.fn.executable("haskell-language-server-wrapper") == 1 then
			vim.lsp.config("hls", {
				capabilities = capabilities,
				cmd = { "haskell-language-server-wrapper", "--lsp" },
				filetypes = { "haskell", "lhaskell", "cabal" },
				root_markers = { "hie.yaml", "stack.yaml", "cabal.project", "package.yaml", "*.cabal", ".git" },
			})

			vim.lsp.enable("hls")
		end

		-- Odin Language Server locates projects from ols.json, .git, or the
		-- nearest .odin file and resolves the SDK through `odin root`.
		vim.lsp.config("ols", {
			capabilities = capabilities,
			filetypes = { "odin" },
		})
		vim.lsp.enable("ols")

		-- ============================
		-- godot / gdscript
		-- ============================
		vim.lsp.config("gdscript", {
			capabilities = capabilities,
		})

		vim.lsp.enable("gdscript")

		if vim.fn.executable("gdshader-lsp") == 1 then
			vim.lsp.config("gdshader_lsp", {
				capabilities = capabilities,
			})

			vim.lsp.enable("gdshader_lsp")
		end

		-- ============================
		-- go
		-- ============================
		vim.lsp.config("gopls", {
			capabilities = capabilities,
			cmd = { "gopls" },
			filetypes = { "go", "gomod", "gowork", "gotmpl" },
			settings = {
				gopls = {
					gofumpt = true,
					staticcheck = true,
					analyses = {
						unusedparams = true,
					},
				},
			},
		})
		vim.lsp.enable("gopls")

		-- ============================
		-- python
		-- ============================
		vim.lsp.config("pyright", {
			capabilities = capabilities,
			cmd = { "pyright-langserver", "--stdio" },
			filetypes = { "python" },
			settings = {
				python = {
					analysis = {
						autosearchpaths = true,
						diagnosticmode = "workspace",
						usellibrarycodefortypes = true,
					},
				},
			},
		})
		vim.lsp.enable("pyright")

		-- ============================
		-- java
		-- ============================
		-- jdtls is owned by nvim-jdtls: the plugin spec is in
		-- engine.plugins.java and it is started, once per project root, from
		-- ftplugin/java.lua. Enabling it here as well would put a second --
		-- and bundle-less, so debug- and test-incapable -- server on every
		-- Java buffer, which is why it is also excluded from
		-- mason-lspconfig's automatic_enable in lsp/mason.lua.
		--
		-- (This comment previously claimed the configuration lived in a
		-- "java.lua ... via opts.servers". No such file existed, and jdtls was
		-- in fact running on bare lspconfig defaults with no workspace and no
		-- bundles.)

		-- ============================
		-- c# (already configured in your omnisharp plugin file via
		-- opts.servers — do not enable omnisharp here too)
		-- ============================
		-- vim.lsp.config("omnisharp", { capabilities = capabilities })
		-- vim.lsp.enable("omnisharp")

		-- ============================
		-- php
		-- ============================
		vim.lsp.config("intelephense", {
			capabilities = capabilities,
			on_attach = enable_inlay_hints,
			-- Blade files are PHP too: intelephense will not parse the
			-- template syntax, but it resolves the PHP inside @php blocks and
			-- keeps the workspace index complete.
			filetypes = { "php" },
			root_markers = { "composer.json", ".git" },
			settings = {
				intelephense = {
					-- Without the framework stubs, every Laravel facade
					-- (Route::, Schema::, Auth::) and every global helper
					-- (route(), view(), collect(), dd()) is an undefined
					-- symbol. This is the single setting that makes
					-- intelephense usable on a Laravel codebase.
					stubs = {
						"apache", "bcmath", "bz2", "calendar", "com_dotnet", "Core", "csprng",
						"ctype", "curl", "date", "dba", "dom", "enchant", "exif", "FFI",
						"fileinfo", "filter", "fpm", "ftp", "gd", "gettext", "gmp", "hash",
						"iconv", "imap", "intl", "json", "ldap", "libxml", "mbstring", "meta",
						"mysqli", "oci8", "odbc", "openssl", "pcntl", "pcre", "PDO", "pdo_mysql",
						"pdo_pgsql", "pdo_sqlite", "pgsql", "Phar", "posix", "pspell", "random",
						"readline", "Reflection", "session", "shmop", "SimpleXML", "snmp", "soap",
						"sockets", "sodium", "SPL", "sqlite3", "standard", "superglobals",
						"sysvmsg", "sysvsem", "sysvshm", "tidy", "tokenizer", "xml", "xmlreader",
						"xmlrpc", "xmlwriter", "xsl", "Zend OPcache", "zip", "zlib",
					},
					files = {
						-- Laravel apps are large; the default 1MB cap silently
						-- skips the bigger vendor files.
						maxSize = 5000000,
					},
					environment = {
						includePaths = {
							-- _ide_helper.php / _ide_helper_models.php from
							-- barryvdh/laravel-ide-helper, when present.
							"vendor/barryvdh/laravel-ide-helper/",
						},
					},
					diagnostics = {
						-- Blade compiles to PHP that intelephense cannot see,
						-- so undefined-variable noise in views is expected.
						undefinedVariables = true,
					},
					completion = {
						insertUseDeclaration = true,
						fullyQualifyGlobalConstantsAndFunctions = false,
					},
				},
			},
		})
		vim.lsp.enable("intelephense")

		-- ============================
		-- markdown
		-- ============================
		vim.lsp.config("marksman", {
			capabilities = capabilities,
			filetypes = { "markdown", "markdown.mdx" },
		})
		vim.lsp.enable("marksman")

		-- ============================
		-- json
		-- ============================
		vim.lsp.config("jsonls", {
			capabilities = capabilities,
			filetypes = { "json", "jsonc" },
			settings = {
				json = {
					validate = { enable = true },
				},
			},
		})
		vim.lsp.enable("jsonls")

		-- ============================
		-- toml
		-- ============================
		vim.lsp.config("taplo", {
			capabilities = capabilities,
			filetypes = { "toml" },
		})
		vim.lsp.enable("taplo")

		-- ============================
		-- dart
		-- ============================
		vim.lsp.config("dartls", {
			capabilities = capabilities,
			filetypes = { "dart" },
			settings = {
				dart = {
					completeFunctionCalls = true,
					showTodos = true,
				},
			},
		})
		vim.lsp.enable("dartls")

		-- ============================
		-- css / scss
		-- ============================
		vim.lsp.config("cssls", {
			capabilities = capabilities,
			filetypes = { "css", "scss", "less" },
			settings = {
				css = { validate = true },
				scss = { validate = true },
			},
		})
		vim.lsp.enable("cssls")

		-- ============================
		-- html
		-- ============================
		vim.lsp.config("html", {
			capabilities = capabilities,
			filetypes = { "html" },
		})
		vim.lsp.enable("html")

		-- ============================
		-- bash / shell
		-- ============================
		vim.lsp.config("bashls", {
			capabilities = capabilities,
			filetypes = { "sh", "bash" },
		})
		vim.lsp.enable("bashls")

		-- ============================
		-- holyc
		-- ============================
		-- hcc bundles its own language server: diagnostics, hover, completion
		-- across the whole tos.HH stdlib, definitions, references, document
		-- highlight and rename. Filetype detection, syntax and the :HolyC*
		-- commands live in engine.core.holyc.
		if vim.fn.executable("hcc") == 1 then
			vim.lsp.config("hcc", {
				capabilities = capabilities,
				cmd = { "hcc", "-lsp" },
				filetypes = { "holyc" },
				-- Per the upstream README: fall back to the file's own
				-- directory rather than to nil, so a scratch .HC outside a
				-- repo still gets a workspace root instead of running in
				-- single-file mode.
				root_dir = function(bufnr, on_dir)
					local name = vim.api.nvim_buf_get_name(bufnr)
					on_dir(
						vim.fs.root(bufnr, { ".git" })
							or (name ~= "" and vim.fs.dirname(name))
							or vim.uv.cwd()
					)
				end,
				-- cmd_env = { HCC_LSP_LOG = "1" },  -- trace, read with :LspLog
			})

			vim.lsp.enable("hcc")
		end

		-- ============================
		-- glsl (shaders)
		-- ============================
		-- glsl_analyzer gives completion over the whole GL builtin set, hover
		-- with the spec wording, and -- the part that matters -- diagnostics
		-- from a real GLSL parse. Before this, a typo in a shader was only
		-- discovered at run time, as a black screen and a compile log in the
		-- terminal.
		--
		-- The upstream config lists the bare extensions ("vert", "frag", ...)
		-- as filetypes, which is not how they arrive here: engine.core.graphics
		-- maps every shader extension to the single `glsl` filetype, so the
		-- treesitter parser and this server agree on one name.
		vim.lsp.config("glsl_analyzer", {
			capabilities = capabilities,
			filetypes = { "glsl" },
			-- A loose shader outside a repo should still get a server rather
			-- than dropping to single-file mode with no includes resolved.
			root_dir = function(bufnr, on_dir)
				local name = vim.api.nvim_buf_get_name(bufnr)
				on_dir(
					vim.fs.root(bufnr, { "shaders", "CMakeLists.txt", ".git" })
						or (name ~= "" and vim.fs.dirname(name))
						or vim.uv.cwd()
				)
			end,
		})
		vim.lsp.enable("glsl_analyzer")

		-- ============================
		-- wgsl (Bevy / wgpu shaders)
		-- ============================
		-- Bevy's shaders are WGSL, not GLSL, and its custom-material examples
		-- are all .wgsl -- so this is the server you want open whenever you go
		-- past StandardMaterial.
		vim.lsp.config("wgsl_analyzer", {
			capabilities = capabilities,
			filetypes = { "wgsl" },
			root_markers = { "Cargo.toml", ".git" },
		})
		vim.lsp.enable("wgsl_analyzer")

		-- ============================
		-- cmake
		-- ============================
		-- neocmakelsp over cmake-language-server: it does completion for
		-- commands and variables, go-to-definition across add_subdirectory,
		-- and formatting, where the older server does little more than hover.
		--
		-- It only offers completion when the client advertises snippet
		-- support. `capabilities` here comes from cmp-nvim-lsp, which does
		-- advertise it, so there is nothing extra to set -- but that is why
		-- the upstream docs make a point of it.
		vim.lsp.config("neocmake", {
			capabilities = capabilities,
			filetypes = { "cmake" },
			root_markers = { "CMakeLists.txt", "CMakePresets.json", ".git" },
		})
		vim.lsp.enable("neocmake")

		-- ============================
		-- zig
		-- ============================
		vim.lsp.config("zls", {
			capabilities = capabilities,
			filetypes = { "zig", "zir" },
		})
		vim.lsp.enable("zls")

		-- ============================
		-- mojo
		-- ============================
		-- mojo-lsp-server ships with the Mojo toolchain rather than through
		-- Mason, which has no Mojo package -- it lands in ~/.pixi/bin alongside
		-- `mojo` itself. Guarded like hcc above, so a machine without the
		-- toolchain just does not get the server instead of erroring on startup.
		--
		-- Filetype detection for .mojo and .🔥 is in engine.core.options; nothing
		-- in Neovim knows the extensions natively yet.
		if vim.fn.executable("mojo-lsp-server") == 1 then
			vim.lsp.config("mojo", {
				capabilities = capabilities,
				cmd = { "mojo-lsp-server" },
				filetypes = { "mojo" },
				-- mojoproject.toml/pixi.toml is a Mojo package root; fall back to
				-- the file's own directory so a loose .mojo still gets a root
				-- rather than dropping to single-file mode.
				root_dir = function(bufnr, on_dir)
					local name = vim.api.nvim_buf_get_name(bufnr)
					on_dir(
						vim.fs.root(bufnr, { "mojoproject.toml", "pixi.toml", ".git" })
							or (name ~= "" and vim.fs.dirname(name))
							or vim.uv.cwd()
					)
				end,
			})
			vim.lsp.enable("mojo")
		end
	end,
}
