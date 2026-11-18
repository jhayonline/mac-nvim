-- Formatting.
--
-- conform runs external formatters; it is not a linter and not an LSP. Every
-- formatter here resolves the *project-local* binary first and only falls back
-- to a global one, so your output matches whatever CI runs:
--
--   prettier         node_modules/.bin/prettier  -> global prettier
--   pint             vendor/bin/pint             -> global pint
--   csharpier        dotnet csharpier (pinned)   -> global csharpier
--   rustfmt          the toolchain's rustfmt, with the edition read from Cargo.toml
--
-- Format-on-save is deliberately split across three places, because they use
-- different mechanisms and have different escape hatches:
--
--   here                       everything conform owns (the list below)
--   engine.core.dotnet         C#, so it can carry a :DotnetFormatToggle
--   engine.plugins.lsp.lspconfig  Typst and C/C++, which format through the
--                              language server rather than a CLI

local function lsp_format_mode(bufnr)
	-- vue_ls and ts_ls both attach to Vue SFCs. Letting Conform fall back to
	-- either one when Prettier is missing makes formatter selection ambiguous
	-- and produces output that can differ from the project's CI formatter.
	return vim.bo[bufnr].filetype == "vue" and "never" or "fallback"
end

return {
	"stevearc/conform.nvim",

	opts = {
		formatters_by_ft = {
			gdscript = { "gdscript-formatter", "gdformat" },

			-- CSharpier is the gofmt of C#: no options to argue over. It
			-- prefers a project-local `dotnet csharpier` when the csproj pins
			-- a version. Triggered on save by engine.core.dotnet.
			cs = { "csharpier" },

			-- ---------------------------------------------------------------
			-- Vue / React / TypeScript
			-- ---------------------------------------------------------------
			-- prettier-plugin-tailwindcss, when the project has it in
			-- devDependencies and lists it in .prettierrc, also sorts Tailwind
			-- classes into the canonical order on every save. That is worth
			-- adding to any Tailwind project -- it ends all class-order
			-- diff noise. Prettier owns the entire Vue SFC so vue_ls and ESLint
			-- remain focused on language intelligence and correctness.
			javascript = { "prettier" },
			javascriptreact = { "prettier" },
			typescript = { "prettier" },
			typescriptreact = { "prettier" },
			svelte = { "prettier" },
			vue = { "prettier" },

			css = { "prettier" },
			scss = { "prettier" },
			less = { "prettier" },
			html = { "prettier" },
			json = { "prettier" },
			jsonc = { "prettier" },
			yaml = { "prettier" },
			markdown = { "prettier" },
			graphql = { "prettier" },

			-- ---------------------------------------------------------------
			-- Rust
			-- ---------------------------------------------------------------
			-- conform's rustfmt reads the edition out of Cargo.toml rather
			-- than defaulting to 2015, which matters: on 2015 rustfmt mangles
			-- async/await and `dyn`.
			rust = { "rustfmt" },

			-- odinfmt ships with Odin and respects a project odinfmt.json.
			odin = { "odinfmt" },

			-- ---------------------------------------------------------------
			-- Graphics: shaders and CMake
			-- ---------------------------------------------------------------
			-- clang-format does not recognise .vert/.frag/.comp, so it falls
			-- back to its C++ rules -- which are the right rules for GLSL and
			-- HLSL, both of which are C-shaped. A project .clang-format is
			-- honoured exactly as it is for C++, so shaders and the C++ that
			-- loads them stay formatted alike.
			--
			-- WGSL is deliberately absent: there is no packaged formatter for
			-- it. wgsl_analyzer offers none either, so the lsp_format fallback
			-- below is a no-op rather than a surprise.
			glsl = { "clang-format" },
			hlsl = { "clang-format" },

			-- gersemi over cmake-format: it is the one that reliably round-trips
			-- generator expressions like $<TARGET_FILE_DIR:triangle> instead of
			-- breaking them across lines. Install `gersemi` with Homebrew or
			-- pipx on macOS.
			-- Falls back to neocmakelsp's own formatter if it is not installed.
			cmake = { "gersemi" },

			-- ---------------------------------------------------------------
			-- PHP / Laravel
			-- ---------------------------------------------------------------
			-- Picked per project rather than fixed, because the two formatters
			-- are not interchangeable:
			--
			--   pint           a PHP-CS-Fixer wrapper with the Laravel preset.
			--                  Ships in every Laravel skeleton at
			--                  vendor/bin/pint, needs no config, and -- this is
			--                  the part that matters for vanilla PHP -- runs
			--                  fine on a loose .php file with no project around
			--                  it. Installed globally as well as per-project.
			--
			--   php-cs-fixer   what you get when a project has committed to its
			--                  own rule set in .php-cs-fixer.php. conform's
			--                  builtin roots it at composer.json, so it cannot
			--                  run outside a project at all -- which is exactly
			--                  why it is not the default.
			--
			-- So: honour an explicit php-cs-fixer config when one exists,
			-- otherwise pint, which works everywhere.
			php = function(bufnr)
				local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
				if dir ~= "" then
					local found = vim.fs.find({
						".php-cs-fixer.php",
						".php-cs-fixer.dist.php",
						".php_cs",
						".php_cs.dist",
					}, { path = dir, upward = true, type = "file" })[1]
					if found then
						return { "php_cs_fixer" }
					end
				end
				return { "pint" }
			end,
			blade = { "blade-formatter" },
		},

		formatters = {
			-- Blade templates are indented like HTML, 4 spaces, and the
			-- formatter otherwise leaves @directives on their own indent level.
			["blade-formatter"] = {
				prepend_args = { "--indent-size", "4", "--wrap-attributes", "preserve-aligned" },
			},
		},

		default_format_opts = {
			-- If no CLI formatter is installed for the buffer, fall back to
			-- whatever the language server offers rather than doing nothing.
			lsp_format = "fallback",
		},

		notify_on_error = true,

		-- Formatters that pay a PHP or Node interpreter start-up cost on every
		-- invocation, measured on this machine: pint ~1500ms, blade-formatter
		-- ~1250ms, and appreciably more on the very first run of a session
		-- when nothing is cached. A 3000ms budget looked generous and was not:
		-- the first save in a project silently exceeded it, conform gave up,
		-- and the file was written unformatted with no visible error.
		--
		-- These get a budget with real headroom instead. Everything else keeps
		-- the shorter one, since a fast formatter that takes 3s is broken.
		format_on_save = function(bufnr)
			-- Handled by their own autocmds, with their own toggles.
			local owned_elsewhere = { cs = true, typst = true, c = true, cpp = true, objc = true, objcpp = true }
			if owned_elsewhere[vim.bo[bufnr].filetype] then
				return nil
			end

			-- Global and per-buffer escape hatches:
			--   :lua vim.g.disable_autoformat = true    (everywhere)
			--   :lua vim.b.disable_autoformat = true    (this buffer)
			if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
				return nil
			end

			local slow = { php = true, blade = true }
			return {
				timeout_ms = slow[vim.bo[bufnr].filetype] and 8000 or 3000,
				lsp_format = lsp_format_mode(bufnr),
			}
		end,
	},

	config = function(_, opts)
		require("conform").setup(opts)

		vim.api.nvim_create_user_command("Format", function(args)
			local range
			if args.count ~= -1 then
				local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
				range = {
					start = { args.line1, 0 },
					["end"] = { args.line2, end_line:len() },
				}
			end
			require("conform").format({ async = true, lsp_format = lsp_format_mode(0), range = range })
		end, { range = true, desc = "Format the buffer or the selected range" })

		vim.api.nvim_create_user_command("FormatToggle", function(args)
			if args.bang then
				vim.b.disable_autoformat = not vim.b.disable_autoformat
				vim.notify("Format on save " .. (vim.b.disable_autoformat and "disabled" or "enabled") .. " for this buffer")
			else
				vim.g.disable_autoformat = not vim.g.disable_autoformat
				vim.notify("Format on save " .. (vim.g.disable_autoformat and "disabled" or "enabled") .. " globally")
			end
		end, { bang = true, desc = "Toggle format on save (! for buffer only)" })

		vim.api.nvim_create_user_command("FormatInfo", function()
			local conform = require("conform")
			local lines = { "filetype: " .. vim.bo.filetype }
			for _, f in ipairs(conform.list_formatters(0)) do
				lines[#lines + 1] = ("  %-16s %s%s"):format(
					f.name,
					f.available and "available" or "UNAVAILABLE",
					f.available and (" (" .. (f.command or "?") .. ")") or (": " .. tostring(f.available_msg))
				)
			end
			if #lines == 1 then
				lines[#lines + 1] = vim.bo.filetype == "vue"
					and "  (Prettier unavailable; Vue LSP formatting is intentionally disabled)"
					or "  (no conform formatter; LSP formatting is used as fallback)"
			end
			vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "conform" })
		end, { desc = "Show which formatters apply to this buffer" })
	end,
}
