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
--   terminal  -- run, watch, test, ef, new, scaffolding, user-secrets. These
--                are interactive or long lived, so they get a real terminal
--                split you can Ctrl-C.
--
-- On top of that there is an MVC layer -- :MvcCrud, :MvcScaffold and
-- :MvcAlternate -- for the two jobs neither a language server nor the plain
-- `dotnet` CLI does: scaffolding CRUD controllers with their Razor views, and
-- navigating between an action and the view it renders by convention.

local M = {}

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- The SDK lives either under ~/.dotnet (Microsoft's install script) or the
-- Apple Silicon Homebrew prefix. Global tools -- roslyn-language-server,
-- csharpier, dotnet-ef -- always go to ~/.dotnet/tools regardless of which
-- SDK location is selected.
--
-- A shell nvim inherits all of this from the shell rc, but an nvim started
-- from Finder or a GUI launcher does not, so patch it in unconditionally.
--
-- The tools directory is handled separately from DOTNET_ROOT because a
-- Homebrew SDK can coexist with user-installed global tools.
local function bootstrap_path()
	-- No "welcome to .NET" banner or first-run cert dance in tool output.
	vim.env.DOTNET_NOLOGO = "1"
	vim.env.DOTNET_CLI_TELEMETRY_OPTOUT = "1"

	local path = vim.env.PATH or ""
	local function prepend(dir)
		if dir and dir ~= "" and uv.fs_stat(dir) and not (":" .. path .. ":"):find(":" .. dir .. ":", 1, true) then
			path = dir .. ":" .. path
		end
	end

	local root = vim.env.DOTNET_ROOT
	if not root or root == "" then
		for _, candidate in ipairs(require("engine.core.macos").dotnet_roots()) do
			-- ~/.dotnet exists even when it only holds `tools`, so require the
			-- SDK's own `dotnet` binary rather than just the directory.
			if uv.fs_stat(candidate .. "/dotnet") then
				root = candidate
				break
			end
		end
	end

	if root and root ~= "" then
		vim.env.DOTNET_ROOT = root
		prepend(root)
	end

	-- Always, and independent of where the SDK itself lives.
	prepend(vim.fn.expand("~/.dotnet/tools"))

	vim.env.PATH = path
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
-- ASP.NET Core MVC
-- ---------------------------------------------------------------------------

-- Two things an MVC app needs that no language server provides.
--
-- The first is scaffolding. `dotnet aspnet-codegenerator` is the CLI behind
-- Visual Studio's "Add > New Scaffolded Item": given an EF model and a
-- DbContext it writes a CRUD controller plus the five Razor views that go with
-- it (Index, Create, Edit, Details, Delete), wired to the right layout. Doing
-- that by hand is the single most tedious part of MVC work.
--
-- It needs two pieces the SDK does not carry on its own:
--
--   dotnet tool install -g dotnet-aspnet-codegenerator
--   dotnet add package Microsoft.VisualStudio.Web.CodeGeneration.Design
--
-- The package goes in the *web* project, and `:MvcCrud` offers to add it when
-- it is missing rather than letting the generator fail with a design-time
-- build error that does not say what is wrong.
--
-- The second is navigation. A controller action and its view are a pair, but
-- they live in different trees -- Controllers/ProductsController.cs and
-- Views/Products/Index.cshtml -- and nothing links them, so `gd` cannot help:
-- `return View()` names the view by convention, not by reference.
-- `:MvcAlternate` walks that convention in both directions.

---The project MVC scaffolding and navigation operate on: the nearest project
---when it is a web project, otherwise the web project in the solution.
local function web_project()
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

	return nil
end

-- The generator needs three packages, and it surfaces them one at a time --
-- each run tells you about exactly one missing package, so discovering the set
-- by trial costs a slow design-time build per attempt:
--
--   Microsoft.VisualStudio.Web.CodeGeneration.Design  the generator itself
--   Microsoft.EntityFrameworkCore.Tools               the model/DbContext reader
--   Microsoft.EntityFrameworkCore.SqlServer           see below
--
-- SqlServer is required **even when the project uses a different provider**.
-- Verified here against a project referencing only
-- Microsoft.EntityFrameworkCore.Sqlite: the generator still refused with
-- "To scaffold, install the following Entity Framework core packages and try
-- again: Microsoft.EntityFrameworkCore.SqlServer." Its provider check is
-- hard-coded rather than read off the project, so the reference has to be
-- there even though nothing uses it. Harmless, but it is noise in the csproj
-- that is otherwise impossible to explain, hence this comment.
--
-- Worse, every one of those failures **exits 0** and writes no files. So this
-- checks the whole set up front rather than trusting the generator's exit
-- code: there is nothing to trust. (`:MvcCrud` still runs it in a terminal
-- split so you see the real message when it fails for a reason the checks
-- below cannot anticipate.)
local CODEGEN_PACKAGES = {
	"Microsoft.VisualStudio.Web.CodeGeneration.Design",
	"Microsoft.EntityFrameworkCore.Tools",
	"Microsoft.EntityFrameworkCore.SqlServer",
}

---Packages the project is missing out of the pair above.
---@param csproj string
---@return string[]
local function missing_codegen_packages(csproj)
	local ok, lines = pcall(vim.fn.readfile, csproj)
	if not ok then
		return {}
	end

	local text = table.concat(lines, "\n")
	local missing = {}
	for _, package in ipairs(CODEGEN_PACKAGES) do
		if not text:find(package, 1, true) then
			missing[#missing + 1] = package
		end
	end
	return missing
end

-- Pluralise a model name for the controller it gets.
--
-- Visual Studio's scaffolder runs the model name through a real pluralisation
-- library, so Category becomes CategoriesController and Person becomes
-- PeopleController. A bare `name .. "s"` -- which is what this started as --
-- gets CategorysController and Persons, and the controller name is baked into
-- every generated route and redirect, so it is not something you want to go
-- back and fix by hand.
--
-- This is not a pluralisation library, just the English rules that actually
-- come up in a model folder, plus the handful of irregulars that are common as
-- entities. Pass a third argument to `:MvcCrud` when it still gets it wrong.
local IRREGULAR_PLURALS = {
	person = "People",
	child = "Children",
	man = "Men",
	woman = "Women",
	tooth = "Teeth",
	foot = "Feet",
	mouse = "Mice",
	goose = "Geese",
	datum = "Data",
	medium = "Media",
	index = "Indices",
	vertex = "Vertices",
	matrix = "Matrices",
	status = "Statuses",
	-- Unchanged in the plural, which matters: `Series .. "es"` is wrong twice.
	series = "Series",
	species = "Species",
	equipment = "Equipment",
	information = "Information",
	-- Nouns in -o split irregularly: these take -es, while Photo, Video,
	-- Logo, Memo, Studio and Auto take a plain -s. A "consonant + o -> es"
	-- rule gets Potato right and Photo wrong, and Photo-shaped words are far
	-- likelier in a model folder, so the -es ones are listed instead.
	potato = "Potatoes",
	tomato = "Tomatoes",
	hero = "Heroes",
	volcano = "Volcanoes",
	echo = "Echoes",
}

---@param name string a model type name, e.g. "Category"
---@return string
local function pluralise(name)
	if name == "" then
		return name
	end

	local irregular = IRREGULAR_PLURALS[name:lower()]
	if irregular then
		-- Preserve the model's own casing of the first letter.
		return name:sub(1, 1):upper() == name:sub(1, 1) and irregular or irregular:lower()
	end

	local lower = name:lower()

	-- Consonant + y -> ies (Category -> Categories), but vowel + y just takes
	-- an s (Day -> Days, Journey -> Journeys).
	if lower:match("[^aeiou]y$") then
		return name:sub(1, -2) .. "ies"
	end

	-- Sibilants take es, or the plural is unpronounceable: Address ->
	-- Addresses, Box -> Boxes, Branch -> Branches, Dish -> Dishes.
	if lower:match("s$") or lower:match("x$") or lower:match("z$") or lower:match("ch$") or lower:match("sh$") then
		return name .. "es"
	end

	-- Shelf -> Shelves, Life -> Lives.
	if lower:match("fe$") then
		return name:sub(1, -3) .. "ves"
	end
	if lower:match("[^f]f$") then
		return name:sub(1, -2) .. "ves"
	end

	return name .. "s"
end

M.pluralise = pluralise

---Name of the EF DbContext to scaffold against.
---
---Scanning beats asking: a solution has exactly one DbContext the overwhelming
---majority of the time, and typing `ApplicationDbContext` correctly every time
---is its own small tax. Match the declaration rather than the file name, so an
---`AppDb : IdentityDbContext<ApplicationUser>` in Data/AppDb.cs is still found.
---@return string[] names
function M.dbcontexts()
	local root = M.solution() and vim.fs.dirname(M.solution())
		or (M.project() and vim.fs.dirname(M.project()))
		or uv.cwd()

	local names, seen = {}, {}

	local candidates = vim.fs.find(function(name, path)
		-- Generated code and build output never hold the real declaration, and
		-- walking obj/ on a restored solution is thousands of files.
		return name:match("%.cs$") ~= nil
			and not path:match("/obj/")
			and not path:match("/bin/")
			and not name:match("%.g%.cs$")
	end, { path = root, type = "file", limit = 2000 })

	for _, file in ipairs(candidates) do
		local ok, lines = pcall(vim.fn.readfile, file)
		if ok then
			-- `class Foo : DbContext`, `: IdentityDbContext<User>`,
			-- `: DbContext, IUnitOfWork` -- all of them end the base name in
			-- DbContext, which is the convention EF itself documents.
			local name = table.concat(lines, "\n"):match("class%s+([%w_]+)%s*:%s*[%w_%.]*DbContext")
			if name and not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end

	table.sort(names)
	return names
end

-- ---------------------------------------------------------------------------
-- Controller <-> view navigation
-- ---------------------------------------------------------------------------

---The root the Views/ and Controllers/ trees hang off. In an app with areas
---that is Areas/<Area>, not the project directory, so a file in
---Areas/Admin/Controllers pairs with Areas/Admin/Views.
---@param path string
---@param csproj string
---@return string
local function mvc_root(path, csproj)
	local area = path:match("^(.*/Areas/[^/]+)/")
	return area or vim.fs.dirname(csproj)
end

---Name of the nearest enclosing node of `kind`, via treesitter.
---
---Treesitter rather than a backwards search for `public ... (`: a search finds
---the attribute line, the local function, or the property above the member
---about as often as the member itself, and the c_sharp parser is already
---loaded for the buffer by the time anyone runs this.
---@param kind string a c_sharp node type, e.g. "method_declaration"
---@return string|nil
local function enclosing_name(kind)
	local ok, parser = pcall(vim.treesitter.get_parser, 0, "c_sharp")
	if not ok or not parser then
		return nil
	end

	parser:parse(true)

	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local node = parser:named_node_for_range({ row - 1, col, row - 1, col })

	while node do
		if node:type() == kind then
			local name = node:field("name")[1]
			if name then
				return vim.treesitter.get_node_text(name, 0)
			end
		end
		node = node:parent()
	end

	return nil
end

---A `dotnet test --filter` expression for the test under the cursor.
---
---Class.Method when the cursor is inside a test method, Class alone when it is
---elsewhere in the file -- which is the natural "run this file's tests".
---Namespace is left out on purpose: FullyQualifiedName~ is a substring match,
---so Class.Method is specific enough without having to resolve file-scoped
---namespaces, partial classes and generic arity.
---@return string|nil filter
---@return string|nil label
local function test_filter_under_cursor()
	local class = enclosing_name("class_declaration")
	if not class then
		return nil, nil
	end

	local method = enclosing_name("method_declaration")
	if method then
		return class .. "." .. method, class .. "." .. method
	end

	return class, class .. " (whole class)"
end

---The name of the method the cursor sits in, via treesitter.
---
---@return string|nil
local function enclosing_method_name()
	return enclosing_name("method_declaration")
end

---Views an action can resolve to, in the order ASP.NET itself searches them.
---@param root string the MVC root (project dir, or Areas/<Area>)
---@param controller string controller name without the "Controller" suffix
---@param action string
---@return string[]
local function view_candidates(root, controller, action)
	return {
		root .. "/Views/" .. controller .. "/" .. action .. ".cshtml",
		root .. "/Views/Shared/" .. action .. ".cshtml",
	}
end

---Open the view for the action under the cursor in a .cs controller.
local function goto_view()
	local path = vim.api.nvim_buf_get_name(0)
	local controller = vim.fs.basename(path):match("^(.+)Controller%.cs$")
	if not controller then
		vim.notify(
			"not a controller -- expected a file named <Name>Controller.cs",
			vim.log.levels.WARN,
			{ title = "mvc" }
		)
		return
	end

	local csproj = M.project()
	if not csproj then
		vim.notify("no .csproj found above this buffer", vim.log.levels.WARN, { title = "mvc" })
		return
	end

	local root = mvc_root(path, csproj)
	local action = enclosing_method_name()

	if action then
		for _, candidate in ipairs(view_candidates(root, controller, action)) do
			if uv.fs_stat(candidate) then
				vim.cmd.edit(vim.fn.fnameescape(candidate))
				return
			end
		end
	end

	-- No action under the cursor, or it renders a view that is not named after
	-- it (`return View("Confirm")`, or a redirect). Offer the controller's
	-- views instead of guessing -- that is still one keystroke from the file.
	local dir = root .. "/Views/" .. controller
	local views = vim.fn.glob(dir .. "/*.cshtml", false, true)

	if #views == 0 then
		local suggestion = action and (action .. ".cshtml") or "Index.cshtml"
		vim.notify(
			"no views under " .. dir .. "\n" .. "create " .. dir .. "/" .. suggestion .. " to start one",
			vim.log.levels.WARN,
			{ title = "mvc" }
		)
		return
	end

	table.sort(views)
	vim.ui.select(views, {
		prompt = action and ("No " .. action .. ".cshtml -- views for " .. controller .. ":")
			or ("Views for " .. controller .. ":"),
		format_item = vim.fs.basename,
	}, function(choice)
		if choice then
			vim.cmd.edit(vim.fn.fnameescape(choice))
		end
	end)
end

---Open the controller action for the view in the current buffer.
local function goto_action()
	local path = vim.api.nvim_buf_get_name(0)
	local controller, action = path:match("/Views/([^/]+)/([^/]+)%.cshtml$")

	if not controller then
		-- Shared partials and _Layout belong to no single controller, and
		-- neither do _ViewStart/_ViewImports.
		vim.notify(
			"no controller for this view -- it is not under Views/<Controller>/",
			vim.log.levels.WARN,
			{ title = "mvc" }
		)
		return
	end

	local csproj = M.project()
	if not csproj then
		vim.notify("no .csproj found above this buffer", vim.log.levels.WARN, { title = "mvc" })
		return
	end

	local root = mvc_root(path, csproj)
	local target = root .. "/Controllers/" .. controller .. "Controller.cs"

	if not uv.fs_stat(target) then
		-- Controllers do not have to live in Controllers/; MVC discovers them
		-- by the base class, not the folder. Fall back to a search.
		local found = vim.fs.find(controller .. "Controller.cs", {
			path = vim.fs.dirname(csproj),
			type = "file",
			limit = 5,
		})[1]

		if not found then
			vim.notify(controller .. "Controller.cs not found", vim.log.levels.WARN, { title = "mvc" })
			return
		end
		target = found
	end

	vim.cmd.edit(vim.fn.fnameescape(target))

	-- Land on the action rather than line 1. Anchored on the method name
	-- followed by `(` so a mention in a comment or a `nameof` does not win.
	local pattern = [[\C\<]] .. vim.fn.escape(action, [[\]]) .. [[\s*(]]
	local line = vim.fn.search(pattern, "w")
	if line == 0 then
		vim.notify(
			"opened " .. vim.fs.basename(target) .. " -- no " .. action .. " action in it",
			vim.log.levels.INFO,
			{ title = "mvc" }
		)
	else
		vim.cmd("normal! zz")
	end
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

	-- Run just the test under the cursor.
	--
	-- This is the working replacement for Roslyn's "Run Test" code lens, which
	-- is disabled in after/lsp/roslyn.lua: that lens' command is
	-- `dotnet.test.run`, a VS Code command no Neovim plugin implements, so it
	-- rendered and did nothing. `dotnet test --filter` needs no editor
	-- integration at all.
	command("DotnetTestHere", function()
		save_if_modified()
		if not have("dotnet", "install the .NET SDK") then
			return
		end

		if vim.bo.filetype ~= "cs" then
			vim.notify("not a C# buffer", vim.log.levels.WARN, { title = "dotnet" })
			return
		end

		local filter, label = test_filter_under_cursor()
		if not filter then
			vim.notify(
				"no enclosing class -- put the cursor inside a test class or method",
				vim.log.levels.WARN,
				{ title = "dotnet" }
			)
			return
		end

		-- FullyQualifiedName~ is a substring match, which is what makes a bare
		-- Class.Method work regardless of namespace. It also means a method
		-- named Add matches AddTwice; pass an exact filter with :DotnetTest if
		-- that ever bites.
		run_in_terminal(
			dotnet_cmd(with_target({ "test", "--nologo", "--filter", "FullyQualifiedName~" .. filter })),
			{ title = "dotnet test " .. label }
		)
	end, { desc = "Run the test under the cursor (dotnet test --filter)" })

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
		local function sdk_version()
			if vim.fn.executable("dotnet") == 0 then
				return "NOT FOUND"
			end
			local out = vim.system({ "dotnet", "--list-sdks" }, { text = true }):wait()
			local last
			for line in (out.stdout or ""):gmatch("[^\n]+") do
				last = line:match("^(%S+)") or last
			end
			-- An SDK-less install still answers `dotnet --version` with the
			-- host version, which is how this machine looked like it had an
			-- SDK when it only had the runtime. --list-sdks is the honest one.
			return last or "NOT FOUND (runtime only -- install the .NET SDK)"
		end

		local lines = {
			"solution:        " .. (M.solution() or "-"),
			"project:         " .. (M.project() or "-"),
			"web project:     " .. (web_project() or "-"),
			"dbcontext(s):    " .. (
				#M.dbcontexts() > 0 and table.concat(M.dbcontexts(), ", ")
				or "-"
			),
			"ef project:      " .. (ef_project() or "-"),
			"ef startup:      " .. (ef_startup_project() or "-"),
			"roslyn solution: " .. (vim.g.roslyn_nvim_selected_solution or "-"),
			"format on save:  " .. tostring(format_on_save_enabled()),
			"sdk:             " .. sdk_version(),
			"dotnet:          " .. (vim.fn.exepath("dotnet") ~= "" and vim.fn.exepath("dotnet") or "NOT FOUND"),
			"roslyn server:   " .. (
				vim.fn.exepath("roslyn-language-server") ~= "" and vim.fn.exepath("roslyn-language-server")
				or "NOT FOUND"
			),
			"csharpier:       " .. (vim.fn.exepath("csharpier") ~= "" and vim.fn.exepath("csharpier") or "NOT FOUND"),
			"dotnet-ef:       " .. (vim.fn.exepath("dotnet-ef") ~= "" and vim.fn.exepath("dotnet-ef") or "NOT FOUND"),
			"codegenerator:   " .. (
				vim.fn.exepath("dotnet-aspnet-codegenerator") ~= ""
					and vim.fn.exepath("dotnet-aspnet-codegenerator")
				or "NOT FOUND"
			),
			"https trust:     macOS Keychain (:DotnetDevCerts)",
			"netcoredbg:      " .. (
				vim.fn.exepath("netcoredbg") ~= "" and vim.fn.exepath("netcoredbg")
				or vim.fn.stdpath("data") .. "/mason/bin/netcoredbg"
			),
		}
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "dotnet" })
	end, { desc = "Show the resolved .NET context for this buffer" })

	-- -----------------------------------------------------------------------
	-- ASP.NET Core MVC
	-- -----------------------------------------------------------------------

	local function codegen_guard()
		if not have("dotnet", "install the .NET SDK") then
			return nil
		end
		if not have("dotnet-aspnet-codegenerator", "dotnet tool install -g dotnet-aspnet-codegenerator") then
			return nil
		end

		local csproj = web_project()
		if not csproj then
			vim.notify(
				"no ASP.NET Core project found -- scaffolding needs a project using Microsoft.NET.Sdk.Web",
				vim.log.levels.WARN,
				{ title = "mvc" }
			)
			return nil
		end

		local missing = missing_codegen_packages(csproj)
		if #missing > 0 then
			local answer = vim.fn.confirm(
				vim.fs.basename(csproj)
					.. " is missing the scaffolding package(s):\n  "
					.. table.concat(missing, "\n  ")
					.. "\nAdd them now?",
				"&Yes\n&No",
				1
			)
			if answer ~= 1 then
				return nil
			end

			-- Synchronous on purpose: the scaffold that follows needs the
			-- references in place, and `dotnet add package` also restores.
			for _, package in ipairs(missing) do
				vim.notify("adding " .. package .. " ...", vim.log.levels.INFO, { title = "mvc" })
				local added = vim.system({ "dotnet", "add", csproj, "package", package }, { text = true }):wait()
				if added.code ~= 0 then
					vim.notify(
						"dotnet add " .. package .. " failed:\n" .. ((added.stderr or "") .. (added.stdout or "")),
						vim.log.levels.ERROR,
						{ title = "mvc" }
					)
					return nil
				end
			end
		end

		return csproj
	end

	---Run the generator in a terminal split. It is chatty, it runs a
	---design-time build, and it prompts before overwriting a file, so it needs
	---to be interactive rather than batched into the quickfix list.
	local function run_codegen(csproj, args, title)
		local cmd = { "dotnet", "aspnet-codegenerator", "--project", csproj }
		vim.list_extend(cmd, args)
		run_in_terminal(cmd, { title = title, cwd = vim.fs.dirname(csproj) })
	end

	command("MvcCrud", function(cmd)
		save_if_modified()

		local csproj = codegen_guard()
		if not csproj then
			return
		end

		-- The generator boots the app's service provider to get at the
		-- DbContext, so an unregistered context fails with "Unable to resolve
		-- service for type DbContextOptions<Foo>" -- which reads like an EF
		-- bug rather than the missing AddDbContext line it actually is. Warn
		-- before paying for the design-time build.
		local program = vim.fs.dirname(csproj) .. "/Program.cs"
		local program_ok, program_lines = pcall(vim.fn.readfile, program)
		if program_ok and not table.concat(program_lines, "\n"):find("AddDbContext", 1, true) then
			vim.notify(
				"Program.cs has no AddDbContext<...> call.\n"
					.. "The generator builds the service provider to reach your DbContext, so it\n"
					.. "will fail with \"Unable to resolve service for type DbContextOptions<...>\".",
				vim.log.levels.WARN,
				{ title = "mvc" }
			)
		end

		-- Default the model to the type in the current buffer: running this
		-- from Models/Product.cs almost always means "scaffold Product".
		local model = cmd.fargs[1]
		if not model then
			local stem = vim.fn.expand("%:t:r")
			model = vim.fn.input({ prompt = "Model class: ", default = stem ~= "" and stem or "" })
			if model == "" then
				return
			end
		end

		local context = cmd.fargs[2]
		if not context then
			local found = M.dbcontexts()
			if #found == 0 then
				context = vim.fn.input("DbContext class: ")
				if context == "" then
					vim.notify(
						"no DbContext found -- :Skel dbcontext scaffolds one",
						vim.log.levels.WARN,
						{ title = "mvc" }
					)
					return
				end
			elseif #found == 1 then
				context = found[1]
			else
				-- vim.ui.select is async, so the scaffold has to continue in
				-- the callback rather than after the `if`.
				vim.ui.select(found, { prompt = "DbContext for " .. model .. ":" }, function(choice)
					if choice then
						run_codegen(csproj, {
							"controller",
							"--controllerName",
							(cmd.fargs[3] or pluralise(model)) .. "Controller",
							"--model",
							model,
							"--dataContext",
							choice,
							"--relativeFolderPath",
							"Controllers",
							"--useDefaultLayout",
							"--referenceScriptLibraries",
						}, "scaffold " .. model .. " CRUD")
					end
				end)
				return
			end
		end

		run_codegen(csproj, {
			"controller",
			"--controllerName",
			(cmd.fargs[3] or pluralise(model)) .. "Controller",
			"--model",
			model,
			"--dataContext",
			context,
			"--relativeFolderPath",
			"Controllers",
			-- Use _Layout.cshtml, and reference jQuery validation in the
			-- Create/Edit views, which is what the MVC template sets up.
			"--useDefaultLayout",
			"--referenceScriptLibraries",
		}, "scaffold " .. model .. " CRUD")
	end, {
		nargs = "*",
		desc = "Scaffold a CRUD controller and its five views from an EF model",
	})

	command("MvcScaffold", function(cmd)
		save_if_modified()
		local csproj = codegen_guard()
		if not csproj then
			return
		end
		if #cmd.fargs == 0 then
			-- No arguments lists the installed generators, which is what the
			-- bare command does anyway and is a useful reminder.
			run_codegen(csproj, {}, "aspnet-codegenerator")
			return
		end
		run_codegen(csproj, cmd.fargs, "aspnet-codegenerator " .. cmd.fargs[1])
	end, {
		nargs = "*",
		desc = "Run dotnet aspnet-codegenerator against the web project",
		complete = function(arg_lead, line)
			if select(2, line:gsub("%s+", " ")) > 2 then
				return {}
			end
			return vim.tbl_filter(function(generator)
				return generator:find(arg_lead, 1, true) == 1
			end, { "controller", "view", "razorpage", "identity", "minimalapi", "area", "blazor" })
		end,
	})

	command("MvcAlternate", function()
		local ft = vim.bo.filetype
		if ft == "razor" then
			goto_action()
		elseif ft == "cs" then
			goto_view()
		else
			vim.notify(
				"nothing to alternate with from a " .. (ft == "" and "scratch" or ft) .. " buffer",
				vim.log.levels.WARN,
				{ title = "mvc" }
			)
		end
	end, { desc = "Jump between a controller action and its Razor view" })

	-- -----------------------------------------------------------------------
	-- Secrets and the HTTPS development certificate
	-- -----------------------------------------------------------------------

	-- The ASP.NET way to keep a connection string out of git: user secrets
	-- live in ~/.microsoft/usersecrets/<id>/secrets.json, outside the repo,
	-- and the Development configuration reads them ahead of appsettings.json.
	command("DotnetSecrets", function(cmd)
		if not have("dotnet", "install the .NET SDK") then
			return
		end

		local csproj = web_project() or M.project()
		if not csproj then
			vim.notify("no .csproj found above this buffer", vim.log.levels.WARN, { title = "dotnet" })
			return
		end

		local args = { "user-secrets" }
		vim.list_extend(args, #cmd.fargs > 0 and cmd.fargs or { "list" })
		vim.list_extend(args, { "--project", csproj })
		run_in_terminal(dotnet_cmd(args), { title = "dotnet user-secrets", cwd = vim.fs.dirname(csproj) })
	end, {
		nargs = "*",
		desc = "Manage user secrets for the web project (default: list)",
		complete = function(arg_lead, line)
			if select(2, line:gsub("%s+", " ")) > 2 then
				return {}
			end
			return vim.tbl_filter(function(verb)
				return verb:find(arg_lead, 1, true) == 1
			end, { "init", "list", "set", "remove", "clear" })
		end,
	})

	-- Kestrel binds https:// by default, and without a trusted certificate the
	-- first `:DotnetRun` of a new MVC app greets you with a browser warning.
	command("DotnetDevCerts", function()
		if not have("dotnet", "install the .NET SDK") then
			return
		end
		run_in_terminal(dotnet_cmd({ "dev-certs", "https", "--trust" }), { title = "dotnet dev-certs" })
		vim.notify(
			"approve the macOS Keychain trust prompt if it appears",
			vim.log.levels.INFO,
			{ title = "dotnet" }
		)
	end, { desc = "Create and trust the ASP.NET Core HTTPS development certificate" })

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
