-- Graphics and game development: shaders, and the two things Neovim does not
-- get right on its own.
--
-- Deliberately small. Neovim 0.12 already maps .vert/.frag/.comp/.geom/.tesc/
-- .tese/.glsl and the ray-tracing stages (.rgen/.rchit/.rmiss/.rahit/.rint/
-- .rcall) to `glsl`, and .wgsl to `wgsl`, so none of that is repeated here.
--
-- What is left:
--
--   1. the handful of extensions it misses (HLSL, and the .glslv/.glslf pair)
--   2. pointing the `wgsl` filetype at the wgsl_bevy grammar, because a Bevy
--      shader is not valid WGSL
--   3. :ShaderCheck, to compile the shader under the cursor
--
-- The language servers themselves are in engine.plugins.lsp.lspconfig
-- (glsl_analyzer, wgsl_analyzer) and the parsers in engine.plugins.treesitter.

local M = {}

local function setup_filetypes()
	vim.filetype.add({
		extension = {
			-- HLSL. Not a filetype Neovim knows, but the treesitter parser
			-- exists and a lot of shader code published online is HLSL, so
			-- reading it highlighted beats reading it plain.
			hlsl = "hlsl",
			fx = "hlsl",
			fxh = "hlsl",
			hlsli = "hlsl",

			-- The older glslv/glslf convention, still used by some engines.
			-- Note .vs and .fs are deliberately absent: .fs is F# to Neovim,
			-- and claiming it here would break F# files for a shader
			-- convention almost nothing uses any more.
			glslv = "glsl",
			glslf = "glsl",
			glslc = "glsl",
		},
	})
end

-- Bevy's shaders are WGSL run through Bevy's own preprocessor: #import,
-- #ifdef/#else/#endif and friends. None of that is valid WGSL, and the strict
-- `wgsl` parser gives up at the first directive -- which in a Bevy material
-- shader is line 1, so the entire file ends up unhighlighted.
--
-- nvim-treesitter ships a separate `wgsl_bevy` grammar for this. Measured on
-- the two parsers here:
--
--                   wgsl        wgsl_bevy
--   plain WGSL       clean       clean
--   Bevy WGSL        ERROR       clean
--
-- So wgsl_bevy is a superset in practice, and the right move is to point the
-- whole `wgsl` filetype at it rather than sniffing each buffer for a Bevy
-- dependency: a plain wgpu project loses nothing, and a Bevy one stops being
-- a wall of error highlights.
local function setup_wgsl_parser()
	vim.treesitter.language.register("wgsl_bevy", "wgsl")

	-- If wgsl_bevy is ever missing (:TSUninstall, or a fresh machine before
	-- :TSUpdate has run), the registration above leaves .wgsl with no working
	-- parser and nvim-treesitter fails silently. Fall back to the strict
	-- grammar rather than showing an unhighlighted buffer with no explanation.
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("EngineGraphicsWgsl", { clear = true }),
		pattern = "wgsl",
		callback = function(args)
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(args.buf) then
					return
				end
				if vim.treesitter.highlighter.active[args.buf] then
					return
				end
				if pcall(vim.treesitter.start, args.buf, "wgsl") then
					vim.notify_once(
						"wgsl_bevy parser missing -- using the strict wgsl grammar. "
							.. "Run :TSInstall wgsl_bevy for Bevy shader support.",
						vim.log.levels.WARN
					)
				end
			end)
		end,
	})
end

-- glslangValidator is the reference GLSL compiler. glsl_analyzer gives you a
-- parse and the builtin symbol table, but it is not a compiler: it will not
-- tell you that a `varying` count exceeds the limit, that a uniform block
-- layout is illegal, or that the stage interface does not match. This will.
local function shader_compiler()
	for _, candidate in ipairs({ "glslangValidator", "glslang" }) do
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end
	return nil
end

local function shader_check(bufnr)
	local compiler = shader_compiler()
	if not compiler then
		vim.notify(
			"glslangValidator not found -- install the `glslang` package",
			vim.log.levels.ERROR,
			{ title = "ShaderCheck" }
		)
		return
	end

	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" then
		vim.notify("ShaderCheck needs a saved file", vim.log.levels.WARN)
		return
	end

	-- glslangValidator infers the stage from the extension, which is the whole
	-- reason the .vert/.frag/.comp naming convention is worth keeping to.
	local result = vim.system({ compiler, file }, { text = true }):wait()
	local output = (result.stdout or "") .. (result.stderr or "")

	-- glslangValidator's diagnostic format is
	--
	--   ERROR: 0:6: 'undeclared_thing' : undeclared identifier
	--          ^ ^
	--          | +-- line number
	--          +---- *string index*, not a file name
	--
	-- The leading number identifies which input string the error came from,
	-- which is 0 for a single file. Reading it as a path -- the obvious
	-- mistake -- gives every quickfix entry the filename "0", and jumping to
	-- an error opens an empty buffer called 0 instead of the shader.
	--
	-- Some builds and some flag combinations print a real path there instead,
	-- so both shapes are accepted: an all-digit field means "the file we
	-- passed in".
	local items = {}
	for line in output:gmatch("[^\r\n]+") do
		local severity, source, lnum, message = line:match("^(%u+):%s*(.-):(%d+):%s*(.*)$")
		if severity and tonumber(lnum) then
			items[#items + 1] = {
				filename = source:match("^%d+$") and file or source,
				lnum = tonumber(lnum),
				col = 1,
				text = vim.trim(message),
				type = severity == "ERROR" and "E" or "W",
			}
		end
	end

	if #items == 0 then
		if result.code == 0 then
			vim.notify(vim.fs.basename(file) .. " compiles", vim.log.levels.INFO, { title = "ShaderCheck" })
		else
			-- Non-zero exit with nothing parseable: show it raw rather than
			-- claiming success.
			vim.notify(vim.trim(output), vim.log.levels.ERROR, { title = "ShaderCheck" })
		end
		vim.fn.setqflist({}, "r")
		return
	end

	vim.fn.setqflist({}, "r", { title = "ShaderCheck: " .. vim.fs.basename(file), items = items })
	vim.cmd.copen()
end

function M.setup()
	setup_filetypes()
	setup_wgsl_parser()

	vim.api.nvim_create_user_command("ShaderCheck", function()
		shader_check(vim.api.nvim_get_current_buf())
	end, { desc = "Compile the current shader with glslangValidator into the quickfix list" })
end

return M
