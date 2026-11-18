local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	{ import = "engine.plugins" },
	{ import = "engine.plugins.lsp" },
}, {
	change_detection = {
		notify = false,
	},

	-- Nothing here needs a rock at runtime. oxocarbon is authored in Fennel but
	-- ships compiled Lua in its own lua/ directory, so enabling luarocks would
	-- only add a build-time toolchain and a second source of first-start
	-- failures on a new Mac.
	rocks = { enabled = false },
})

require("engine.core.theme").setup()
