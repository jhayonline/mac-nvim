-- lua/engine/tools/init.lua
local M = {}

function M.setup()
	local group = vim.api.nvim_create_augroup("SalarIncludeFormatter", { clear = true })

	-- C/C++ include formatter
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = group,
		pattern = { "*.h", "*.hpp", "*.hh", "*.hxx", "*.c", "*.cc", "*.cpp", "*.cxx" },
		callback = function(args)
			local ft = vim.bo[args.buf].filetype
			if ft == "typst" then return end
			require("engine.tools.include_formatter").format(args.buf)
		end,
	})

	-- Typst auto-compile
	local typst_job = nil

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*.typ",
		callback = function(args)
			local file = vim.api.nvim_buf_get_name(args.buf)
			local pdf = file:gsub("%.typ$", ".pdf")

			if typst_job then
				vim.fn.jobstop(typst_job)
			end

			typst_job = vim.fn.jobstart({ "typst", "compile", file, pdf })
		end,
	})

	-- :Skel command
	--
	-- With no argument the template is inferred: from the extension for C/C++
	-- (header vs. translation unit), and from the filename convention for C#
	-- (IFoo -> interface, FooController -> controller, FooDbContext -> EF
	-- context, FooTests -> xunit class, ...). Pass a name to override it --
	-- :Skel record, :Skel apicontroller, :Skel middleware. <Tab> lists the
	-- templates valid for the current buffer.
	vim.api.nvim_create_user_command("Skel", function(cmd)
		require("engine.tools.skeleton").insert(cmd.args ~= "" and cmd.args or nil)
	end, {
		nargs = "?",
		desc = "Replace the buffer with a skeleton for its file type",
		complete = function(arg_lead)
			return vim.tbl_filter(function(kind)
				return kind:find(arg_lead, 1, true) == 1
			end, require("engine.tools.skeleton").completions())
		end,
	})

	-- :TypstPreview command
	vim.api.nvim_create_user_command("TypstPreview", function()
		local file = vim.fn.expand("%")
		local pdf = file:gsub("%.typ$", ".pdf")
		vim.fn.jobstart({ "zathura", pdf })
	end, {})


	require("engine.tools.cpp_extract").setup()
end

return M
