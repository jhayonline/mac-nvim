-- .NET workflow layer: everything around the language server.
--
-- The Roslyn LSP (engine.plugins.lsp.roslyn) handles code intelligence. This
-- module owns the parts a language server does not do: finding the project or
-- solution the current buffer belongs to, driving `dotnet` and `dotnet ef`
-- without leaving Neovim, routing build errors into the quickfix list, and
-- formatting with CSharpier on save.
--
-- Commands are split in two families by how you consume their output:
--
--   quickfix  -- build, restore, clean, publish, format. You want the errors,
--                not the scrollback, so these run async and populate :copen.
--   terminal  -- run, watch, test, ef, new. These are interactive or long
--                lived, so they get a real terminal split you can Ctrl-C.

local M = {}

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- The SDK lives in ~/.dotnet (Microsoft's dotnet-install.sh, no sudo needed)
-- and global tools -- roslyn-language-server, csharpier, dotnet-ef -- in
-- ~/.dotnet/tools. A shell nvim inherits that from .zshrc, but nvim started
-- from Finder or a GUI launcher does not, so patch it in unconditionally.
local function bootstrap_path()
	local root = vim.env.DOTNET_ROOT
	if not root or root == "" then
		local home = vim.fn.expand("~/.dotnet")
		if uv.fs_stat(home) then
			root = home
			vim.env.DOTNET_ROOT = home
		end
	end

	if not root then
		return
	end

	local wanted = { root, root .. "/tools" }
	local path = vim.env.PATH or ""

	for _, dir in ipairs(wanted) do
		if not (":" .. path .. ":"):find(":" .. dir .. ":", 1, true) then
			path = dir .. ":" .. path
		end
	end

	vim.env.PATH = path
	-- No "welcome to .NET" banner or first-run cert dance in tool output.
	vim.env.DOTNET_NOLOGO = "1"
	vim.env.DOTNET_CLI_TELEMETRY_OPTOUT = "1"
end

local function have(binary, hint)
	if vim.fn.executable(binary) == 1 then
		return true
	end
	vim.notify(binary .. " not found on $PATH -- " .. hint, vim.log.levels.ERROR, { title = "dotnet" })
	return false
end

-- ---------------------------------------------------------------------------
-- Project / solution discovery
-- ---------------------------------------------------------------------------

local function buffer_dir()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return uv.cwd()
	end
	return vim.fs.dirname(name)
end

-- Walk up from the buffer looking for the first file matching any glob. Used
-- for both .csproj (nearest wins -- that is the project you are editing) and
-- .sln (nearest wins too, but it usually sits several levels higher).
local function find_upward(globs, start)
	local dir = start or buffer_dir()

	while dir and dir ~= "" do
		for _, glob in ipairs(globs) do
			local hits = vim.fn.glob(dir .. "/" .. glob, false, true)
			if #hits > 0 then
				table.sort(hits)
				return hits[1]
			end
		end

		local parent = vim.fs.dirname(dir)
		if parent == dir then
			return nil
		end
		dir = parent
	end
end

---The .csproj the current buffer belongs to, or nil.
function M.project()
	return find_upward({ "*.csproj", "*.fsproj", "*.vbproj" })
end

---The .sln/.slnx above the current buffer, or nil.
function M.solution()
	return vim.g.dotnet_solution or find_upward({ "*.sln", "*.slnx" })
end

---Best target for a `dotnet <verb>` invocation: solution if there is one,
---otherwise the nearest project, otherwise nothing (cwd-relative).
function M.target()
	return M.solution() or M.project()
end

---Directory to run `dotnet` from -- the solution or project directory, so
---relative paths in compiler output resolve.
local function target_dir()
	local target = M.target()
	return target and vim.fs.dirname(target) or uv.cwd()
end

---Read a scalar MSBuild property out of a .csproj without a full XML parse.
---Good enough for the handful of flags the skeletons and commands care about.
---@param csproj string
---@param property string
---@return string|nil
function M.msbuild_property(csproj, property)
	if not csproj or not uv.fs_stat(csproj) then
		return nil
	end

	local ok, lines = pcall(vim.fn.readfile, csproj)
	if not ok then
		return nil
	end

	local text = table.concat(lines, "\n")
	return text:match("<" .. property .. ">%s*(.-)%s*</" .. property .. ">")
end

---True when the nearest project uses the ASP.NET Core SDK, i.e. an MVC / Razor
---Pages / Web API app rather than a class library or console app.
---@param csproj? string
function M.is_web_project(csproj)
	csproj = csproj or M.project()
	if not csproj or not uv.fs_stat(csproj) then
		return false
	end

	local ok, lines = pcall(vim.fn.readfile, csproj)
	if not ok then
		return false
	end

	return table.concat(lines, "\n"):match('Sdk%s*=%s*"Microsoft%.NET%.Sdk%.Web"') ~= nil
end

-- ---------------------------------------------------------------------------
-- Runners
-- ---------------------------------------------------------------------------

local function shell_join(cmd)
	return table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
end

---Interactive/long-lived commands: a terminal split at the bottom third.
local function run_in_terminal(cmd, opts)
	opts = opts or {}

	vim.cmd("botright " .. math.max(10, math.floor(vim.o.lines / 3)) .. "split")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)

	vim.fn.jobstart(cmd, {
		term = true,
		cwd = opts.cwd or target_dir(),
	})

	vim.bo[buf].bufhidden = "wipe"
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	vim.b[buf].term_title = opts.title or shell_join(cmd)

	if opts.insert ~= false then
		vim.cmd.startinsert()
	end
end

-- MSBuild writes diagnostics as:
--   /abs/Path/File.cs(12,20): error CS0103: message [/abs/Proj.csproj]
-- The trailing [project] is noise once you have the file, and the %-G rules
-- drop the restore/build chatter so :copen is only real diagnostics.
local BUILD_ERRORFORMAT = table.concat({
	"%f(%l\\,%c): %trror %m",
	"%f(%l\\,%c): %tarning %m",
	"%f(%l\\,%c): %tessage %m",
	"%f(%l): %trror %m",
	"%f(%l): %tarning %m",
	"%-G%.%#",
}, ",")

---Batch commands: run async, stream nothing, land the diagnostics in quickfix.
local function run_to_quickfix(cmd, opts)
	opts = opts or {}
	local title = opts.title or shell_join(cmd)
	local output = {}

	local function collect(_, data)
		for _, line in ipairs(data or {}) do
			if line ~= "" then
				line = line:gsub("\r$", "")
				-- MSBuild suffixes every diagnostic with the project that
				-- produced it: "... [/abs/path/Shop.Web.csproj]". The quickfix
				-- entry already carries the file, so that is pure width.
				line = line:gsub("%s*%[[^%]]*%.[cfv]sproj%]$", "")
				line = line:gsub("%s*%[[^%]]*%.slnx?%]$", "")
				output[#output + 1] = line
			end
		end
	end

	vim.notify(title .. " ...", vim.log.levels.INFO, { title = "dotnet" })

	vim.fn.jobstart(cmd, {
		cwd = opts.cwd or target_dir(),
		stdout_buffered = false,
		on_stdout = collect,
		on_stderr = collect,
		on_exit = function(_, code)
			vim.schedule(function()
				local saved = vim.o.errorformat
				vim.o.errorformat = BUILD_ERRORFORMAT
				vim.fn.setqflist({}, " ", { title = title, lines = output })
				vim.o.errorformat = saved

				-- Duplicate diagnostics are the norm: MSBuild repeats each one
				-- per target framework and per referencing project.
				local seen, unique = {}, {}
				for _, item in ipairs(vim.fn.getqflist()) do
					local key = table.concat({ item.bufnr, item.lnum, item.col, item.text }, ":")
					if not seen[key] then
						seen[key] = true
						unique[#unique + 1] = item
					end
				end
				vim.fn.setqflist({}, "r", { title = title, items = unique })

				if code == 0 then
					vim.cmd("cclose")
					vim.notify(title .. " succeeded", vim.log.levels.INFO, { title = "dotnet" })
					return
				end

				if #unique > 0 then
					vim.cmd("botright copen")
					vim.cmd("wincmd p")
					vim.notify(
						title .. " failed -- " .. #unique .. " diagnostic(s)",
						vim.log.levels.ERROR,
						{ title = "dotnet" }
					)
				else
					-- Failed without anything the errorformat matched (a NuGet
					-- error, a missing SDK). Show the raw output instead.
					vim.notify(
						title .. " failed:\n" .. table.concat(vim.list_slice(output, math.max(1, #output - 15)), "\n"),
						vim.log.levels.ERROR,
						{ title = "dotnet" }
					)
				end
			end)
		end,
	})
end

---Save the buffer first -- every one of these commands compiles from disk.
local function save_if_modified()
	if vim.bo.modified and vim.api.nvim_buf_get_name(0) ~= "" then
		vim.cmd.write()
	end
end

-- ---------------------------------------------------------------------------
-- dotnet CLI commands
-- ---------------------------------------------------------------------------

local function dotnet_cmd(args)
	local cmd = { "dotnet" }
	vim.list_extend(cmd, args)
	return cmd
end

---Append the resolved solution/project so `dotnet build` from a random file in
---the tree still builds the right thing.
local function with_target(args)
	local target = M.target()
	if target then
		args[#args + 1] = target
	end
	return args
end

-- ---------------------------------------------------------------------------
-- Entity Framework Core
-- ---------------------------------------------------------------------------

-- EF splits the project holding the DbContext and migrations (--project) from
-- the one that boots the host and builds the service provider
-- (--startup-project). In a single-project MVC app they are the same file. In a
-- layered solution (Web -> Infrastructure -> Domain) they differ, so both are
-- overridable through :EfProject and :EfStartupProject.
local function ef_project()
	return vim.g.dotnet_ef_project or M.project()
end

local function ef_startup_project()
	-- Default the startup project to the one web project in the solution when
	-- the buffer lives in a class library, which is the common layered layout.
	if vim.g.dotnet_ef_startup_project then
		return vim.g.dotnet_ef_startup_project
	end

	local nearest = M.project()
	if nearest and M.is_web_project(nearest) then
		return nearest
	end

	local solution = M.solution()
	if solution then
		local found = vim.fs.find(function(name)
			return name:match("%.csproj$") ~= nil
		end, { path = vim.fs.dirname(solution), type = "file", limit = 100 })

		for _, csproj in ipairs(found) do
			if M.is_web_project(csproj) then
				return csproj
			end
		end
	end

	return nearest
end

local function ef_cmd(args)
	local cmd = { "dotnet", "ef" }
	vim.list_extend(cmd, args)

	local project = ef_project()
	if project then
		vim.list_extend(cmd, { "--project", project })
	end

	local startup = ef_startup_project()
	if startup and startup ~= project then
		vim.list_extend(cmd, { "--startup-project", startup })
	end

	return cmd
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

-- CSharpier is the C# equivalent of prettier/gofmt: no options worth arguing
-- about. conform.nvim routes cs -> csharpier (see engine.plugins.todo_marker),
-- and prefers a project-local `dotnet csharpier` over the global tool when the
-- csproj pins a version, which keeps you byte-identical with CI.
local function format_on_save_enabled()
	if vim.g.dotnet_format_on_save == nil then
		return true
	end
	return vim.g.dotnet_format_on_save
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function M.setup()
	bootstrap_path()

	-- Neovim ships .cshtml as html, which loses every C# construct in the file
	-- and stops roslyn.nvim from attaching. Razor is its own filetype.
	vim.filetype.add({
		extension = {
			cshtml = "razor",
			razor = "razor",
		},
		filename = {
			["Directory.Build.props"] = "xml",
			["Directory.Build.targets"] = "xml",
			["Directory.Packages.props"] = "xml",
			["nuget.config"] = "xml",
			["NuGet.config"] = "xml",
		},
		pattern = {
			[".*%.csproj"] = "xml",
			[".*%.props"] = "xml",
			[".*%.targets"] = "xml",
			[".*%.slnx"] = "xml",
		},
	})

	local group = vim.api.nvim_create_augroup("EngineDotnet", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePre", {
		group = group,
		pattern = { "*.cs", "*.csx" },
		callback = function(args)
			if not format_on_save_enabled() then
				return
			end

			local ok, conform = pcall(require, "conform")
			if ok then
				-- CSharpier measures ~800ms warm here, but the first run of a
				-- session pays the .NET start-up cost on top. Budget for that
				-- rather than silently skipping the format -- see the note in
				-- engine.plugins.conform.
				conform.format({ bufnr = args.buf, timeout_ms = 8000, lsp_format = "fallback" })
			end
		end,
	})

	-- -----------------------------------------------------------------------
	-- Build pipeline -> quickfix
	-- -----------------------------------------------------------------------

	local function command(name, fn, opts)
		vim.api.nvim_create_user_command(name, fn, opts or {})
	end

	command("DotnetBuild", function(cmd)
		save_if_modified()
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		local args = { "build", "--nologo", "-consoleloggerparameters:NoSummary" }
		vim.list_extend(args, cmd.fargs)
		run_to_quickfix(dotnet_cmd(with_target(args)), { title = "dotnet build" })
	end, { nargs = "*", desc = "Build the solution/project into the quickfix list" })

	command("DotnetRestore", function()
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		run_to_quickfix(dotnet_cmd(with_target({ "restore", "--nologo" })), { title = "dotnet restore" })
	end, { desc = "Restore NuGet packages" })

	command("DotnetClean", function()
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		run_to_quickfix(dotnet_cmd(with_target({ "clean", "--nologo" })), { title = "dotnet clean" })
	end, { desc = "Clean build output" })

	command("DotnetPublish", function(cmd)
		save_if_modified()
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		local args = { "publish", "--nologo", "-c", "Release" }
		vim.list_extend(args, cmd.fargs)
		run_to_quickfix(dotnet_cmd(with_target(args)), { title = "dotnet publish" })
	end, { nargs = "*", desc = "Publish in Release configuration" })

	-- -----------------------------------------------------------------------
	-- Interactive -> terminal split
	-- -----------------------------------------------------------------------

	-- `dotnet run` needs a single project, never a solution: a .sln has no
	-- entry point. Fall back to the web project when the buffer is in a
	-- library, which is what you almost always mean in an MVC solution.
	local function runnable_project()
		local nearest = M.project()
		if nearest and (M.is_web_project(nearest) or M.msbuild_property(nearest, "OutputType") == "Exe") then
			return nearest
		end
		return ef_startup_project() or nearest
	end

	local function run_project_command(verb, extra, title)
		save_if_modified()
		if not have("dotnet", "install the .NET SDK") then
			return
		end

		local project = runnable_project()
		if not project then
			vim.notify("no .csproj found above this buffer", vim.log.levels.WARN, { title = "dotnet" })
			return
		end

		local args = { verb, "--project", project }
		vim.list_extend(args, extra or {})
		run_in_terminal(dotnet_cmd(args), { title = title, cwd = vim.fs.dirname(project) })
	end

	command("DotnetRun", function(cmd)
		run_project_command("run", cmd.fargs, "dotnet run")
	end, { nargs = "*", desc = "Run the current project" })

	command("DotnetWatch", function(cmd)
		-- The ASP.NET inner loop: rebuild + hot reload on every save.
		local extra = { "run" }
		vim.list_extend(extra, cmd.fargs)
		run_project_command("watch", extra, "dotnet watch run")
	end, { nargs = "*", desc = "Run the current project with hot reload" })

	command("DotnetTest", function(cmd)
		save_if_modified()
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		local args = { "test", "--nologo" }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(dotnet_cmd(with_target(args)), { title = "dotnet test" })
	end, { nargs = "*", desc = "Run the test suite" })

	command("DotnetNew", function(cmd)
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		local args = { "new" }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(dotnet_cmd(args), { title = "dotnet new", cwd = uv.cwd() })
	end, {
		nargs = "*",
		desc = "Scaffold from a dotnet template",
		complete = function(arg_lead, line)
			-- Only complete the template name (first argument).
			if select(2, line:gsub("%s+", " ")) > 2 then
				return {}
			end
			local templates = {
				"console",
				"classlib",
				"web",
				"webapp",
				"mvc",
				"webapi",
				"razor",
				"blazor",
				"blazorserver",
				"blazorwasm",
				"worker",
				"xunit",
				"nunit",
				"mstest",
				"sln",
				"gitignore",
				"editorconfig",
				"globaljson",
				"nugetconfig",
				"tool-manifest",
			}
			return vim.tbl_filter(function(t)
				return t:find(arg_lead, 1, true) == 1
			end, templates)
		end,
	})

	command("DotnetAdd", function(cmd)
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		local project = M.project()
		if not project then
			vim.notify("no .csproj found above this buffer", vim.log.levels.WARN, { title = "dotnet" })
			return
		end
		local args = { "add", project, "package" }
		vim.list_extend(args, cmd.fargs)
		run_to_quickfix(dotnet_cmd(args), { title = "dotnet add package" })
	end, { nargs = "+", desc = "Add a NuGet package to the current project" })

	command("DotnetOutdated", function()
		if not have("dotnet-outdated", "dotnet tool install -g dotnet-outdated-tool") then
			return
		end
		local target = M.target()
		run_in_terminal({ "dotnet-outdated", target or "." }, { title = "dotnet outdated" })
	end, { desc = "List outdated NuGet packages" })

	command("DotnetFormat", function()
		if not have("csharpier", "dotnet tool install -g csharpier") then
			return
		end
		run_to_quickfix({ "csharpier", "format", target_dir() }, { title = "csharpier format" })
	end, { desc = "Run CSharpier over the whole project" })

	command("DotnetFormatToggle", function()
		vim.g.dotnet_format_on_save = not format_on_save_enabled()
		vim.notify(
			"C# format on save " .. (format_on_save_enabled() and "enabled" or "disabled"),
			vim.log.levels.INFO,
			{ title = "dotnet" }
		)
	end, { desc = "Toggle CSharpier format on save" })

	command("DotnetInfo", function()
		local lines = {
			"solution:        " .. (M.solution() or "-"),
			"project:         " .. (M.project() or "-"),
			"web project:     " .. tostring(M.is_web_project()),
			"ef project:      " .. (ef_project() or "-"),
			"ef startup:      " .. (ef_startup_project() or "-"),
			"roslyn solution: " .. (vim.g.roslyn_nvim_selected_solution or "-"),
			"format on save:  " .. tostring(format_on_save_enabled()),
			"dotnet:          " .. (vim.fn.exepath("dotnet") ~= "" and vim.fn.exepath("dotnet") or "NOT FOUND"),
			"roslyn server:   " .. (
				vim.fn.exepath("roslyn-language-server") ~= "" and vim.fn.exepath("roslyn-language-server")
				or "NOT FOUND"
			),
			"csharpier:       " .. (vim.fn.exepath("csharpier") ~= "" and vim.fn.exepath("csharpier") or "NOT FOUND"),
			"dotnet-ef:       " .. (vim.fn.exepath("dotnet-ef") ~= "" and vim.fn.exepath("dotnet-ef") or "NOT FOUND"),
			"netcoredbg:      " .. (
				vim.fn.exepath("netcoredbg") ~= "" and vim.fn.exepath("netcoredbg")
				or vim.fn.stdpath("data") .. "/mason/bin/netcoredbg"
			),
		}
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "dotnet" })
	end, { desc = "Show the resolved .NET context for this buffer" })

	-- -----------------------------------------------------------------------
	-- Entity Framework Core
	-- -----------------------------------------------------------------------

	local function ef_guard()
		if not have("dotnet-ef", "dotnet tool install -g dotnet-ef") then
			return false
		end
		if not ef_project() then
			vim.notify("no .csproj found above this buffer", vim.log.levels.WARN, { title = "dotnet ef" })
			return false
		end
		return true
	end

	command("EfAdd", function(cmd)
		save_if_modified()
		if not ef_guard() then
			return
		end
		local name = cmd.args ~= "" and cmd.args or vim.fn.input("Migration name: ")
		if name == "" then
			return
		end
		run_in_terminal(ef_cmd({ "migrations", "add", name }), { title = "ef migrations add " .. name })
	end, { nargs = "?", desc = "Add an EF Core migration" })

	command("EfRemove", function()
		if not ef_guard() then
			return
		end
		run_in_terminal(ef_cmd({ "migrations", "remove" }), { title = "ef migrations remove" })
	end, { desc = "Remove the last EF Core migration" })

	command("EfList", function()
		if not ef_guard() then
			return
		end
		run_in_terminal(ef_cmd({ "migrations", "list" }), { title = "ef migrations list" })
	end, { desc = "List EF Core migrations" })

	command("EfUpdate", function(cmd)
		if not ef_guard() then
			return
		end
		-- With no argument this applies every pending migration; with one it
		-- migrates to that migration, which is also how you roll back
		-- (:EfUpdate 0 reverts the database to empty).
		local args = { "database", "update" }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(ef_cmd(args), { title = "ef database update" })
	end, { nargs = "?", desc = "Apply migrations (optionally to a target migration)" })

	command("EfDrop", function()
		if not ef_guard() then
			return
		end
		if vim.fn.confirm("Drop the database for " .. vim.fs.basename(ef_project()) .. "?", "&Yes\n&No", 2) ~= 1 then
			return
		end
		run_in_terminal(ef_cmd({ "database", "drop", "--force" }), { title = "ef database drop" })
	end, { desc = "Drop the database (asks first)" })

	command("EfScript", function()
		if not ef_guard() then
			return
		end
		run_in_terminal(ef_cmd({ "migrations", "script", "--idempotent" }), { title = "ef migrations script" })
	end, { desc = "Generate an idempotent SQL migration script" })

	command("EfScaffold", function(cmd)
		if not ef_guard() then
			return
		end
		if #cmd.fargs < 1 then
			vim.notify(
				'usage: :EfScaffold "<connection string>" [provider]\n'
					.. "provider defaults to Microsoft.EntityFrameworkCore.SqlServer",
				vim.log.levels.WARN,
				{ title = "dotnet ef" }
			)
			return
		end
		local provider = cmd.fargs[2] or "Microsoft.EntityFrameworkCore.SqlServer"
		run_in_terminal(
			ef_cmd({ "dbcontext", "scaffold", cmd.fargs[1], provider, "--output-dir", "Models" }),
			{ title = "ef dbcontext scaffold" }
		)
	end, { nargs = "*", desc = "Reverse-engineer models from an existing database" })

	command("EfProject", function(cmd)
		vim.g.dotnet_ef_project = cmd.args ~= "" and cmd.args or nil
		vim.notify("ef --project: " .. (ef_project() or "-"), vim.log.levels.INFO, { title = "dotnet ef" })
	end, { nargs = "?", complete = "file", desc = "Pin the EF migrations project (empty to reset)" })

	command("EfStartupProject", function(cmd)
		vim.g.dotnet_ef_startup_project = cmd.args ~= "" and cmd.args or nil
		vim.notify("ef --startup-project: " .. (ef_startup_project() or "-"), vim.log.levels.INFO, { title = "dotnet ef" })
	end, { nargs = "?", complete = "file", desc = "Pin the EF startup project (empty to reset)" })
end

return M
