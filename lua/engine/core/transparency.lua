-- Clears background colours so the terminal's own background (and its
-- opacity/blur, e.g. Ghostty's background-opacity) shows through.
local M = {}

local state_file = vim.fn.stdpath("state") .. "/transparency.txt"

M.enabled = true

local groups = {
	"Normal",
	"NormalNC",
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
	"SignColumn",
	"FoldColumn",
	"LineNr",
	"CursorLineNr",
	"EndOfBuffer",
	"MsgArea",
	"StatusLine",
	"StatusLineNC",
	"TabLine",
	"TabLineFill",
	"WinBar",
	"WinBarNC",
	"WinSeparator",
	"VertSplit",
	-- Plugins
	"NvimTreeNormal",
	"NvimTreeNormalNC",
	"NvimTreeEndOfBuffer",
	"NvimTreeWinSeparator",
	"TelescopeNormal",
	"TelescopeBorder",
	"TelescopePromptNormal",
	"TelescopePromptBorder",
	"TelescopeResultsNormal",
	"TelescopeResultsBorder",
	"TelescopePreviewNormal",
	"TelescopePreviewBorder",
	"WhichKeyNormal",
	"WhichKeyFloat",
	"TroubleNormal",
	"TroubleNormalNC",
	"BufferLineFill",
	"AlphaNormal",
	"LazyNormal",
	"MasonNormal",
	"NotifyBackground",
}

local function clear()
	for _, name in ipairs(groups) do
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
		if ok and hl then
			hl.bg = nil
			hl.ctermbg = nil
			hl.force = true
			pcall(vim.api.nvim_set_hl, 0, name, hl)
		end
	end
end

function M.apply()
	if M.enabled then
		clear()
	end
end

local function persist()
	local dir = vim.fn.fnamemodify(state_file, ":h")
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({ M.enabled and "1" or "0" }, state_file)
end

function M.toggle()
	M.enabled = not M.enabled
	persist()
	-- Reload the colorscheme to restore (or clear) backgrounds.
	if vim.g.colors_name then
		pcall(vim.cmd.colorscheme, vim.g.colors_name)
	end
	vim.notify(("Transparency: %s"):format(M.enabled and "on" or "off"))
end

function M.setup()
	if vim.fn.filereadable(state_file) == 1 then
		M.enabled = vim.fn.readfile(state_file)[1] ~= "0"
	end

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("EngineTransparency", { clear = true }),
		callback = M.apply,
	})

	vim.api.nvim_create_user_command("TransparencyToggle", M.toggle, {
		desc = "Toggle transparent background",
	})
end

return M
