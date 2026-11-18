vim.cmd("let g:netrw_liststyle = 3")

local opt = vim.opt

opt.relativenumber = true
opt.number = true

-- tabs / indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true
opt.copyindent = true
opt.preserveindent = true

opt.wrap = false

opt.ignorecase = true
opt.smartcase = true

opt.cursorline = true

opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"

opt.backspace = "indent,eol,start"

opt.clipboard:append("unnamedplus")

opt.splitright = true
opt.splitbelow = true

opt.foldmethod = "marker"
opt.foldmarker = "#pragma region,#pragma endregion"

opt.winblend = 100  -- 0 = opaque, 100 = fully transparent
opt.pumblend = 10  -- For popup menus (completion)

vim.api.nvim_create_autocmd("FileType", {
	callback = function(args)
		local bo = vim.bo[args.buf]
		bo.autoindent = true
		bo.smartindent = true
		bo.copyindent = true
		bo.preserveindent = true
	end,
})

vim.filetype.add({
	extension = {
		-- Neovim has no Mojo filetype yet, and Mojo accepts either extension --
		-- the fire emoji is the canonical one upstream. Without this, mojo-lsp
		-- (engine.plugins.lsp.lspconfig) has no filetype to attach to.
		mojo = "mojo",
		["\u{1F525}"] = "mojo",

		gd = "gdscript",
		gdshader = "gdshader",
		gdshaderinc = "gdshaderinc",
		tres = "gdresource",
		tscn = "gdresource",
	},
	filename = {
		["project.godot"] = "godot",
	},
})
