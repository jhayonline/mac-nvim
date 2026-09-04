-- C# / .NET support, built on the Roslyn language server -- the same engine
-- Visual Studio and the VS Code C# extension run on.
--
-- This replaces OmniSharp, which was retired upstream. Roslyn reads .sln,
-- .slnx and .csproj directly, so an ASP.NET Core MVC app, an EF Core data
-- project and a plain console project all resolve without per-project wiring.
-- It also brings Razor/.cshtml support in-process, which is why rzls.nvim is
-- not here: that plugin was discontinued once roslyn.nvim absorbed it.
--
-- The server is a .NET global tool rather than a Mason package:
--
--   dotnet tool install -g roslyn-language-server --prerelease \
--     --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
--
-- Layout of the C# support, since it is spread over a few files by necessity:
--
--   this file                       plugin spec and plugin-level behaviour
--   after/lsp/roslyn.lua            server settings (inlay hints, code lens,
--                                   diagnostics scope) -- see the note there
--                                   for why they cannot live in config()
--   lua/engine/core/dotnet.lua      :Dotnet*/:Ef* commands, format on save
--   lua/engine/tools/skeleton_csharp.lua  the :Skel templates
--   ftplugin/cs.vim, ftplugin/razor.vim   buffer options

return {
	"seblyng/roslyn.nvim",
	ft = { "cs", "razor" },

	-- Loaded first so that after/lsp/roslyn.lua can build cmp's capabilities
	-- when the client starts.
	dependencies = { "hrsh7th/cmp-nvim-lsp" },

	---@module 'roslyn.config'
	---@type RoslynNvimConfig
	opts = {
		-- Hand file watching to the server rather than Neovim's libuv watcher.
		-- Roslyn's own watcher is what the plugin's :checkhealth rates "ok"
		-- (Neovim's only rates "info"), it does not walk bin/ and obj/ from
		-- Lua on a 4-core Haswell, and it avoids the one-off
		-- "watch.watch: ENOENT" notice Neovim emits when Roslyn asks it to
		-- watch a directory the build has not created yet.
		filewatching = "roslyn",

		-- Only look for a solution next to or above the buffer. Set true if you
		-- keep solution files in a directory beside the projects rather than
		-- above them.
		broad_search = false,

		-- Re-evaluate the target when you jump into a file from another
		-- solution, rather than staying pinned to the first one opened.
		lock_target = false,
	},
}
