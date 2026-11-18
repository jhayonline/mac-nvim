-- Roslyn language server settings.
--
-- This lives in after/lsp/ rather than in the plugin spec on purpose. Neovim
-- collects every lsp/<name>.lua on the runtimepath and deep-merges them at the
-- moment the client starts, with after/ merged last -- so this file always wins
-- over roslyn.nvim's own lsp/roslyn.lua, and always applies no matter which
-- order lazy.nvim loaded things in.
--
-- Putting these in the plugin's config() instead does not work: roslyn.nvim's
-- plugin/roslyn.lua calls vim.lsp.enable("roslyn") when the plugin is sourced,
-- which is before config() runs, so the first client of the session starts
-- with none of the settings below.
--
-- The keys are the VS Code C# extension's option names, grouped under the
-- "csharp|<section>" scopes Roslyn expects over LSP.

---@type vim.lsp.Config
return {
	capabilities = (function()
		-- Resolved lazily at client start, by which point cmp-nvim-lsp is
		-- loaded, so completion gets snippet + resolve support rather than the
		-- bare protocol defaults.
		local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
		local capabilities = ok and cmp_nvim_lsp.default_capabilities()
			or vim.lsp.protocol.make_client_capabilities()

		-- Tell the server we will NOT watch files, so it uses its own watcher
		-- (see filewatching = "roslyn" in the plugin spec).
		--
		-- This has to be set here rather than left to roslyn.nvim's option,
		-- which applies it with a vim.lsp.config() call inside setup(). That
		-- call loses a race: the plugin's plugin/roslyn.lua runs
		-- vim.lsp.enable("roslyn") when lazy sources it, which is before lazy
		-- runs setup(), so the session's first client starts with the option
		-- unapplied and Neovim watches the tree anyway. Everything in this
		-- file is immune to that, because Neovim re-reads lsp/*.lua from the
		-- runtimepath every time it resolves the config for a new client.
		capabilities.workspace = capabilities.workspace or {}
		capabilities.workspace.didChangeWatchedFiles = { dynamicRegistration = false }

		return capabilities
	end)(),

	on_attach = function(client, bufnr)
		-- The shared LspAttach handler in engine.plugins.lsp.lspconfig guards
		-- inlay hints behind a misspelled capability key ("inlayhintprovider"),
		-- so it never fires for any server. Enable them here for C#, where they
		-- carry a lot of the value: var types, LINQ chains, EF lambda
		-- parameters and the argument names in long service calls.
		if client:supports_method("textDocument/inlayHint") then
			vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
		end

		-- Code lens: reference counts above each member.
		--
		-- Asking the server for lenses is only half of it -- Neovim renders
		-- nothing until code lens is enabled for the buffer, and nothing in this
		-- config did it, so Roslyn was computing lenses on every edit that were
		-- then dropped on the floor.
		--
		-- These are informational, not clickable. This server advertises an empty
		-- `executeCommandProvider`, and the reference lens carries no command at
		-- all, so there is deliberately no keymap to "run" one -- see the note on
		-- test lenses in the settings below.
		--
		-- Scoped to C# rather than put in the shared LspAttach handler because
		-- Roslyn is the only server here configured to produce lenses.
		--
		-- `enable` goes through the same vim.lsp._capability machinery as
		-- inlay_hint.enable above, so it re-requests on its own as the buffer
		-- changes. (vim.lsp.codelens.refresh() needs hand-written
		-- BufEnter/CursorHold/InsertLeave autocmds, and is deprecated for
		-- removal in 0.13.)
		if client:supports_method("textDocument/codeLens") then
			vim.lsp.codelens.enable(true, { bufnr = bufnr })
		end
	end,

	settings = {
		["csharp|inlay_hints"] = {
			csharp_enable_inlay_hints_for_implicit_object_creation = true,
			csharp_enable_inlay_hints_for_implicit_variable_types = true,
			csharp_enable_inlay_hints_for_lambda_parameter_types = true,
			csharp_enable_inlay_hints_for_types = true,
			dotnet_enable_inlay_hints_for_indexer_parameters = true,
			dotnet_enable_inlay_hints_for_literal_parameters = true,
			dotnet_enable_inlay_hints_for_object_creation_parameters = true,
			dotnet_enable_inlay_hints_for_other_parameters = true,
			dotnet_enable_inlay_hints_for_parameters = true,
			-- Drop the hints that just repeat the argument you already wrote.
			dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
			dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
			dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
		},

		["csharp|code_lens"] = {
			-- Reference counts above members. Informational only, but worth
			-- having: "0 references" over a method you thought was wired up
			-- is the cheapest dead-code check there is.
			dotnet_enable_references_code_lens = true,

			-- Test lenses are OFF, and this is deliberate.
			--
			-- Roslyn emits "Run Test" / "Debug Test" / "Run All Tests" lenses
			-- whose command is `dotnet.test.run` -- a **VS Code** command,
			-- contributed by the C# extension, not an LSP one. Verified on
			-- this machine: the server advertises an empty
			-- executeCommandProvider, roslyn.nvim implements only
			-- fixAllCodeAction / nestedCodeAction / completionComplexEdit, and
			-- nothing else handles `dotnet.test.run`. So with these on you get
			-- four lenses per test file that render, offer themselves in a
			-- picker, and then do nothing at all.
			--
			-- `:DotnetTestHere` (engine.core.dotnet) is the working
			-- equivalent: it runs the test under the cursor through
			-- `dotnet test --filter`, which needs no editor integration.
			dotnet_enable_tests_code_lens = false,
		},

		["csharp|completion"] = {
			-- The one that matters most for ASP.NET work: complete types you
			-- have not imported yet, and let the server add the using for you.
			dotnet_show_completion_items_from_unimported_namespaces = true,
			dotnet_show_name_completion_suggestions = true,
			dotnet_provide_regex_completions = true,
		},

		["csharp|background_analysis"] = {
			-- Compiler errors solution-wide: rename a model property and every
			-- broken view-model, controller and migration lights up at once
			-- instead of only when you open the file.
			dotnet_compiler_diagnostics_scope = "fullSolution",
			-- Analyzers (the IDExxxx / CAxxxx style and quality rules) stay on
			-- open files -- solution-wide analysis is the expensive half. Raise
			-- to "fullSolution" if you want them everywhere and can spare the
			-- extra background work.
			dotnet_analyzer_diagnostics_scope = "openFiles",
		},

		["csharp|symbol_search"] = {
			-- Let "add using" reach into reference assemblies that are not
			-- referenced yet and offer the PackageReference to add.
			dotnet_search_reference_assemblies = true,
		},

		["csharp|formatting"] = {
			dotnet_organize_imports_on_format = true,
		},

		["navigation"] = {
			-- gd into a framework or NuGet type lands in decompiled C# rather
			-- than a metadata stub.
			dotnet_navigate_to_decompiled_sources = true,
		},
	},
}
