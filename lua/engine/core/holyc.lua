-- HolyC support, built around the hcc compiler (https://holyc-lang.com).
--
-- hcc ships its own language server (`hcc -lsp`), which supplies diagnostics,
-- hover, completion over the full tos.HH stdlib, go-to-definition, references,
-- document highlight and rename. That server is registered in
-- engine.plugins.lsp.lspconfig alongside the other language servers, so it
-- picks up the same cmp capabilities and LspAttach keymaps as everything else.
--
-- This module owns the parts the compiler cannot provide: filetype detection,
-- and commands to drive the JIT / REPL / codegen from inside a buffer.
-- Highlighting lives in syntax/holyc.vim, buffer options in ftplugin/holyc.vim.

local M = {}

-- `.hh` is deliberately absent: it belongs to C++ and is already claimed.
local EXTENSIONS = { HC = "holyc", hc = "holyc", HH = "holyc" }

local function have_hcc()
	if vim.fn.executable("hcc") == 1 then
		return true
	end
	vim.notify("hcc not found on $PATH -- install it from holyc-lang.com", vim.log.levels.ERROR)
	return false
end

-- Run hcc in a terminal split so JIT output, REPL input and compiler errors
-- all stay interactive.
local function run_in_terminal(args, title)
	if not have_hcc() then
		return
	end

	local cmd = { "hcc" }
	vim.list_extend(cmd, args)

	vim.cmd("botright " .. math.floor(vim.o.lines / 3) .. "split")
	vim.cmd.terminal()

	local chan = vim.b.terminal_job_id
	vim.api.nvim_chan_send(chan, table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ") .. "\n")

	vim.bo.bufhidden = "wipe"
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.b.term_title = title
	vim.cmd.startinsert()
end

-- Anything that compiles the current buffer needs it on disk first.
local function current_file()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		vim.notify("buffer has no file name -- save it first", vim.log.levels.WARN)
		return nil
	end
	if vim.bo.modified then
		vim.cmd.write()
	end
	return name
end

-- Compiler output that is inspected rather than interacted with (the AST, the
-- token stream, the transpiled C) goes to a scratch buffer instead.
local function run_to_scratch(args, name, filetype)
	if not have_hcc() then
		return
	end

	local cmd = { "hcc" }
	vim.list_extend(cmd, args)

	local result = vim.system(cmd, { text = true }):wait()
	local output = (result.stdout or "") .. (result.stderr or "")
	if output == "" then
		vim.notify("hcc produced no output", vim.log.levels.WARN)
		return
	end

	vim.cmd("botright vsplit")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n", { trimempty = true }))

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	if filetype then
		vim.bo[buf].filetype = filetype
	end
	pcall(vim.api.nvim_buf_set_name, buf, name)
end

-- hcc's server has no semanticTokensProvider, and a syntax file cannot see a
-- file's own declarations, so class/union tags declared in this buffer are
-- collected here and fed back in as a keyword group. Called by
-- after/syntax/holyc.vim on load and by the autocmd below on write /
-- leaving insert mode. Current buffer only --
-- types pulled in from an #include stay unhighlighted.
function M.refresh_user_types(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "holyc" then
		return
	end

	local names, seen = {}, {}
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local tag = line:match("^%s*%f[%w_]class%f[^%w_]%s+([%a_][%w_]*)")
			or line:match("^%s*%f[%w_]union%f[^%w_]%s+([%a_][%w_]*)")
			or line:match("^%s*public%s+class%s+([%a_][%w_]*)")
			or line:match("^%s*public%s+union%s+([%a_][%w_]*)")
		if tag and not seen[tag] then
			seen[tag] = true
			names[#names + 1] = tag
		end
	end

	vim.api.nvim_buf_call(buf, function()
		-- silent!: the group does not exist until the first tag is found.
		vim.cmd("silent! syntax clear holycUserType")
		if #names > 0 then
			vim.cmd("syntax keyword holycUserType " .. table.concat(names, " "))
		end
	end)
end

local function create_commands(buf)
	local function cmd(name, fn, opts)
		vim.api.nvim_buf_create_user_command(buf, name, fn, opts or {})
	end

	-- :HolyCRun runs main() through the in-process JIT. With ! it adds
	-- -Memsafe, which tracks MAlloc/Free and reports double frees and leaks.
	cmd("HolyCRun", function(o)
		local file = current_file()
		if not file then
			return
		end
		local args = { "-jit" }
		if o.bang then
			table.insert(args, "-Memsafe")
		end
		table.insert(args, file)
		run_in_terminal(args, "hcc -jit")
	end, { bang = true, desc = "HolyC: JIT-run this file (! adds -Memsafe)" })

	cmd("HolyCRepl", function()
		run_in_terminal({ "-repl" }, "hcc -repl")
	end, { desc = "HolyC: open the hcc REPL" })

	-- :HolyCBuild produces a real binary next to the source.
	cmd("HolyCBuild", function()
		local file = current_file()
		if not file then
			return
		end
		local out = vim.fn.fnamemodify(file, ":r")
		run_in_terminal({ "-o", out, file }, "hcc -o")
	end, { desc = "HolyC: compile this file to a binary" })

	cmd("HolyCCheck", function()
		local file = current_file()
		if not file then
			return
		end
		run_to_scratch({ "-ast", file }, "hcc://ast", nil)
	end, { desc = "HolyC: dump the AST" })

	cmd("HolyCTokens", function()
		local file = current_file()
		if not file then
			return
		end
		run_to_scratch({ "-tokens", file }, "hcc://tokens", nil)
	end, { desc = "HolyC: dump the token stream" })

	cmd("HolyCAsm", function()
		local file = current_file()
		if not file then
			return
		end
		run_to_scratch({ "-S", "-o-", file }, "hcc://asm", "asm")
	end, { desc = "HolyC: emit assembly" })

	cmd("HolyCTranspile", function()
		local file = current_file()
		if not file then
			return
		end
		run_to_scratch({ "-transpile", file }, "hcc://transpiled.c", "c")
	end, { desc = "HolyC: transpile to C (best effort)" })
end

function M.setup()
	vim.filetype.add({ extension = EXTENSIONS })

	local group = vim.api.nvim_create_augroup("HolyC", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "holyc",
		callback = function(ev)
			create_commands(ev.buf)

			-- <leader>h is taken by bufferline, so these sit on function keys.
			local opts = { buffer = ev.buf, silent = true }
			vim.keymap.set("n", "<F5>", "<cmd>HolyCRun<cr>", vim.tbl_extend("force", opts, {
				desc = "HolyC: JIT-run this file",
			}))
			vim.keymap.set("n", "<F6>", "<cmd>HolyCRepl<cr>", vim.tbl_extend("force", opts, {
				desc = "HolyC: open the hcc REPL",
			}))
		end,
	})

	vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
		group = group,
		pattern = { "*.HC", "*.hc", "*.HH" },
		callback = function(ev)
			M.refresh_user_types(ev.buf)
		end,
	})
end

return M
