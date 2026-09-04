-- PHP workflow layer, Laravel and vanilla.
--
-- The counterpart to engine.core.dotnet: intelephense handles code
-- intelligence, this module handles everything around it -- locating the
-- project, driving `php`, `composer` and `artisan` without leaving Neovim, and
-- putting syntax errors and test failures into the quickfix list.
--
-- Laravel is treated as a superset, not as a requirement. There are three
-- levels of project, and every command degrades to the level it finds:
--
--   a Laravel app     has `artisan`     -> :Artisan*, plus everything below
--   a composer project has composer.json -> :Composer, vendor/bin tooling
--   a loose .php file  has neither       -> :Php* still work, pint still
--                                          formats it, intelephense still
--                                          attaches in single-file mode
--
-- Same split as the .NET module, for the same reason:
--
--   quickfix  -- test, composer install/update, pint. You want the failures,
--                not the scrollback.
--   terminal  -- artisan (serve, tinker, migrate, queue:work), which is
--                interactive or long-lived and needs to be Ctrl-C-able.

local M = {}

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- PHP from the shivammathur tap is keg-only, so it is never on $PATH by
-- default, and Composer's global bin (which holds the `laravel` installer) is
-- not either. nvim started from a GUI launcher never reads .zshrc, so patch
-- both in here the way engine.core.dotnet does for the .NET SDK.
local function bootstrap_path()
	local candidates = {
		"/usr/local/opt/php@8.4/bin",
		"/usr/local/opt/php/bin",
		"/opt/homebrew/opt/php@8.4/bin",
		"/opt/homebrew/opt/php/bin",
		vim.fn.expand("~/.composer/vendor/bin"),
		vim.fn.expand("~/.config/composer/vendor/bin"),
	}

	local path = vim.env.PATH or ""
	for _, dir in ipairs(candidates) do
		if uv.fs_stat(dir) and not (":" .. path .. ":"):find(":" .. dir .. ":", 1, true) then
			path = dir .. ":" .. path
		end
	end
	vim.env.PATH = path
end

local function have(binary, hint)
	if vim.fn.executable(binary) == 1 then
		return true
	end
	vim.notify(binary .. " not found on $PATH -- " .. hint, vim.log.levels.ERROR, { title = "laravel" })
	return false
end

-- ---------------------------------------------------------------------------
-- Project discovery
-- ---------------------------------------------------------------------------

local function buffer_dir()
	local name = vim.api.nvim_buf_get_name(0)
	return name ~= "" and vim.fs.dirname(name) or uv.cwd()
end

---Nearest directory containing `marker`, walking up from the buffer.
local function find_root(marker)
	local found = vim.fs.find(marker, { path = buffer_dir(), upward = true, type = "file" })[1]
	return found and vim.fs.dirname(found) or nil
end

---Root of the composer project the buffer belongs to, or nil.
function M.root()
	return find_root("composer.json")
end

---Root of the Laravel app the buffer belongs to (the directory with `artisan`).
function M.laravel_root()
	return find_root("artisan")
end

function M.is_laravel()
	return M.laravel_root() ~= nil
end

---Laravel version from composer.lock, for display in :LaravelInfo.
local function laravel_version(root)
	local lock = root and (root .. "/composer.lock")
	if not lock or not uv.fs_stat(lock) then
		return nil
	end

	local ok, lines = pcall(vim.fn.readfile, lock)
	if not ok then
		return nil
	end

	-- Cheaper and more robust than decoding a multi-megabyte lock file.
	local text = table.concat(lines, "\n")
	return text:match('"name":%s*"laravel/framework".-"version":%s*"([^"]+)"')
end

-- ---------------------------------------------------------------------------
-- Runners
-- ---------------------------------------------------------------------------

local function shell_join(cmd)
	return table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
end

local function run_in_terminal(cmd, opts)
	opts = opts or {}

	vim.cmd("botright " .. math.max(10, math.floor(vim.o.lines / 3)) .. "split")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)

	vim.fn.jobstart(cmd, { term = true, cwd = opts.cwd or M.root() or uv.cwd() })

	vim.bo[buf].bufhidden = "wipe"
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	vim.b[buf].term_title = opts.title or shell_join(cmd)
	vim.cmd.startinsert()
end

-- PHPUnit and Pest both print failures as an indented "at /path/file.php:LINE"
-- line under the failure message, and PHP fatals/warnings as
-- "... in /path/file.php on line N". Nothing else in the output is a location,
-- so %-G everything that does not match.
local PHP_ERRORFORMAT = table.concat({
	"%f:%l",
	"%*[^\"]\"%f\"%*\\D%l: %m",
	"%m in %f on line %l",
	"%.%#at %f:%l",
	"%.%#%f(%l):%m",
	"%-G%.%#",
}, ",")

local function run_to_quickfix(cmd, opts)
	opts = opts or {}
	local title = opts.title or shell_join(cmd)
	local output = {}

	local function collect(_, data)
		for _, line in ipairs(data or {}) do
			if line ~= "" then
				-- Strip ANSI colour, which otherwise defeats every errorformat
				-- pattern; artisan and pest colour their output by default.
				line = line:gsub("\r$", ""):gsub("\27%[[%d;]*m", "")

				-- `php -l` writes each parse error to BOTH streams, and the
				-- stderr copy is spelled differently: "PHP Parse error:  ..."
				-- against stdout's "Parse error: ...". Normalise the two into
				-- one string so the dedupe below actually collapses them.
				line = line:gsub("^PHP ", ""):gsub("([Ee]rror:)%s+", "%1 ")

				output[#output + 1] = line
			end
		end
	end

	vim.notify(title .. " ...", vim.log.levels.INFO, { title = "laravel" })

	vim.fn.jobstart(cmd, {
		cwd = opts.cwd or M.root() or uv.cwd(),
		on_stdout = collect,
		on_stderr = collect,
		on_exit = function(_, code)
			vim.schedule(function()
				local saved = vim.o.errorformat
				vim.o.errorformat = opts.errorformat or PHP_ERRORFORMAT
				vim.fn.setqflist({}, " ", { title = title, lines = output })
				vim.o.errorformat = saved

				-- `php -l` prints the same parse error to stdout and stderr,
				-- and phpunit repeats a failure once per data-provider row, so
				-- the raw list is full of duplicates.
				local seen, items = {}, {}
				for _, item in ipairs(vim.fn.getqflist()) do
					if item.valid == 1 then
						local key = table.concat({ item.bufnr, item.lnum, item.col, item.text }, ":")
						if not seen[key] then
							seen[key] = true
							items[#items + 1] = item
						end
					end
				end
				vim.fn.setqflist({}, "r", { title = title, items = items })

				if code == 0 then
					vim.cmd("cclose")
					vim.notify(title .. " succeeded", vim.log.levels.INFO, { title = "laravel" })
					return
				end

				if #items > 0 then
					vim.cmd("botright copen")
					vim.cmd("wincmd p")
					vim.notify(
						title .. " failed -- " .. #items .. " location(s)",
						vim.log.levels.ERROR,
						{ title = "laravel" }
					)
				else
					vim.notify(
						title .. " failed:\n" .. table.concat(vim.list_slice(output, math.max(1, #output - 20)), "\n"),
						vim.log.levels.ERROR,
						{ title = "laravel" }
					)
				end
			end)
		end,
	})
end

local function save_if_modified()
	if vim.bo.modified and vim.api.nvim_buf_get_name(0) ~= "" then
		vim.cmd.write()
	end
end

-- ---------------------------------------------------------------------------
-- artisan
-- ---------------------------------------------------------------------------

---Command names from `php artisan list`, cached per session -- shelling out on
---every <Tab> would be unusable, and the list only changes when a package is
---added.
local artisan_commands = nil

local function load_artisan_commands()
	if artisan_commands then
		return artisan_commands
	end

	local root = M.laravel_root()
	if not root or vim.fn.executable("php") ~= 1 then
		return {}
	end

	local result = vim.system({ "php", "artisan", "list", "--raw", "--no-ansi" }, {
		cwd = root,
		text = true,
	}):wait(15000)

	artisan_commands = {}
	for line in (result.stdout or ""):gmatch("[^\n]+") do
		local name = line:match("^(%S+)")
		if name then
			artisan_commands[#artisan_commands + 1] = name
		end
	end

	table.sort(artisan_commands)
	return artisan_commands
end

local function artisan_cmd(args)
	local cmd = { "php", "artisan" }
	vim.list_extend(cmd, args)
	return cmd
end

local function artisan_guard()
	if not have("php", "brew install shivammathur/php/php@8.4") then
		return false
	end
	if not M.laravel_root() then
		vim.notify("no artisan found above this buffer -- not a Laravel app", vim.log.levels.WARN, { title = "laravel" })
		return false
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function M.setup()
	bootstrap_path()

	-- Neovim already maps *.blade.php to `blade`; these are the ones it does
	-- not know about in a Laravel tree.
	vim.filetype.add({
		extension = {
			antlers = "html",
		},
		filename = {
			[".env"] = "sh",
			[".env.example"] = "sh",
			[".env.local"] = "sh",
			[".env.testing"] = "sh",
			["artisan"] = "php",
		},
		pattern = {
			["%.env%.[%w_.-]+"] = "sh",
		},
	})

	local function command(name, fn, opts)
		vim.api.nvim_create_user_command(name, fn, opts or {})
	end

	-- -----------------------------------------------------------------------
	-- artisan
	-- -----------------------------------------------------------------------

	command("Artisan", function(cmd)
		if not artisan_guard() then
			return
		end
		if #cmd.fargs == 0 then
			run_in_terminal(artisan_cmd({ "list" }), { title = "artisan list", cwd = M.laravel_root() })
			return
		end
		save_if_modified()
		run_in_terminal(artisan_cmd(cmd.fargs), {
			title = "artisan " .. table.concat(cmd.fargs, " "),
			cwd = M.laravel_root(),
		})
	end, {
		nargs = "*",
		desc = "Run an artisan command (<Tab> completes from `artisan list`)",
		complete = function(arg_lead, line)
			-- Only complete the command name, not its arguments.
			if select(2, line:gsub("%s+", " ")) > 2 then
				return {}
			end
			return vim.tbl_filter(function(name)
				return name:find(arg_lead, 1, true) == 1
			end, load_artisan_commands())
		end,
	})

	command("ArtisanServe", function(cmd)
		if not artisan_guard() then
			return
		end
		local args = { "serve" }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(artisan_cmd(args), { title = "artisan serve", cwd = M.laravel_root() })
	end, { nargs = "*", desc = "Start the development server" })

	command("ArtisanTinker", function()
		if not artisan_guard() then
			return
		end
		run_in_terminal(artisan_cmd({ "tinker" }), { title = "artisan tinker", cwd = M.laravel_root() })
	end, { desc = "Open a Tinker REPL" })

	command("ArtisanMigrate", function(cmd)
		if not artisan_guard() then
			return
		end
		local args = { "migrate" }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(artisan_cmd(args), { title = "artisan migrate", cwd = M.laravel_root() })
	end, {
		nargs = "*",
		desc = "Run migrations (:ArtisanMigrate fresh --seed, :ArtisanMigrate rollback, ...)",
		complete = function(arg_lead)
			return vim.tbl_filter(function(s)
				return s:find(arg_lead, 1, true) == 1
			end, { "fresh", "refresh", "reset", "rollback", "status", "install", "--seed", "--force", "--pretend" })
		end,
	})

	command("ArtisanRoutes", function(cmd)
		if not artisan_guard() then
			return
		end
		local args = { "route:list" }
		vim.list_extend(args, #cmd.fargs > 0 and cmd.fargs or { "--columns=method,uri,name,action" })
		run_in_terminal(artisan_cmd(args), { title = "artisan route:list", cwd = M.laravel_root() })
	end, { nargs = "*", desc = "List routes" })

	command("ArtisanQueue", function(cmd)
		if not artisan_guard() then
			return
		end
		local args = { "queue:work" }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(artisan_cmd(args), { title = "artisan queue:work", cwd = M.laravel_root() })
	end, { nargs = "*", desc = "Start a queue worker" })

	-- `make:` is the one family worth its own command: it is used constantly
	-- and its completions are a fixed, well-known list.
	command("ArtisanMake", function(cmd)
		if not artisan_guard() then
			return
		end
		if #cmd.fargs < 2 then
			vim.notify("usage: :ArtisanMake <type> <Name>", vim.log.levels.WARN, { title = "laravel" })
			return
		end
		local args = { "make:" .. cmd.fargs[1] }
		vim.list_extend(args, vim.list_slice(cmd.fargs, 2))
		run_in_terminal(artisan_cmd(args), {
			title = "artisan make:" .. cmd.fargs[1],
			cwd = M.laravel_root(),
		})
	end, {
		nargs = "*",
		desc = "Scaffold a Laravel class (:ArtisanMake controller PostController)",
		complete = function(arg_lead, line)
			if select(2, line:gsub("%s+", " ")) > 2 then
				return {}
			end
			local types = {
				"controller", "model", "migration", "seeder", "factory", "middleware",
				"request", "resource", "policy", "provider", "event", "listener",
				"job", "mail", "notification", "command", "rule", "cast", "channel",
				"component", "observer", "scope", "test", "enum", "interface", "trait",
			}
			return vim.tbl_filter(function(t)
				return t:find(arg_lead, 1, true) == 1
			end, types)
		end,
	})

	-- -----------------------------------------------------------------------
	-- tests, composer, formatting
	-- -----------------------------------------------------------------------

	command("ArtisanTest", function(cmd)
		if not artisan_guard() then
			return
		end
		save_if_modified()
		local args = { "test" }
		vim.list_extend(args, cmd.fargs)
		run_to_quickfix(artisan_cmd(args), { title = "artisan test", cwd = M.laravel_root() })
	end, { nargs = "*", desc = "Run the test suite, failures to the quickfix list" })

	command("Composer", function(cmd)
		if not have("composer", "see doc/php.md for the installer") then
			return
		end
		local root = M.root()
		if not root then
			vim.notify("no composer.json found above this buffer", vim.log.levels.WARN, { title = "laravel" })
			return
		end
		local args = {}
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(vim.list_extend({ "composer" }, args), {
			title = "composer " .. table.concat(cmd.fargs, " "),
			cwd = root,
		})
	end, {
		nargs = "*",
		desc = "Run a composer command",
		complete = function(arg_lead, line)
			if select(2, line:gsub("%s+", " ")) > 2 then
				return {}
			end
			return vim.tbl_filter(function(s)
				return s:find(arg_lead, 1, true) == 1
			end, {
				"install", "update", "require", "remove", "dump-autoload",
				"show", "outdated", "why", "why-not", "validate", "audit", "run-script",
			})
		end,
	})

	command("Pint", function()
		local root = M.root()
		local local_pint = root and (root .. "/vendor/bin/pint")
		local pint = (local_pint and vim.fn.executable(local_pint) == 1) and local_pint or "pint"

		if vim.fn.executable(pint) ~= 1 then
			vim.notify(
				"pint not found -- composer require --dev laravel/pint",
				vim.log.levels.ERROR,
				{ title = "laravel" }
			)
			return
		end

		run_to_quickfix({ pint }, { title = "pint", cwd = root })
	end, { desc = "Run Laravel Pint over the project" })

	-- -----------------------------------------------------------------------
	-- Vanilla PHP: works with no composer.json and no artisan
	-- -----------------------------------------------------------------------

	---Directory to run a loose script from: the project if there is one, else
	---the file's own directory, so relative require/include paths resolve.
	local function script_cwd()
		return M.root() or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
	end

	command("PhpRun", function(cmd)
		if not have("php", "brew install shivammathur/php/php@8.4") then
			return
		end
		save_if_modified()
		local file = vim.api.nvim_buf_get_name(0)
		if file == "" then
			vim.notify("buffer has no file name -- save it first", vim.log.levels.WARN, { title = "php" })
			return
		end
		local args = { "php", file }
		vim.list_extend(args, cmd.fargs)
		run_in_terminal(args, { title = "php " .. vim.fs.basename(file), cwd = script_cwd() })
	end, { nargs = "*", desc = "Run the current PHP file" })

	command("PhpLint", function()
		if not have("php", "brew install shivammathur/php/php@8.4") then
			return
		end
		save_if_modified()
		local file = vim.api.nvim_buf_get_name(0)
		if file == "" then
			return
		end
		-- `php -l` is a parse-only check. It catches the syntax errors
		-- intelephense reports too, but it is the compiler's own verdict --
		-- useful when the language server and the runtime disagree.
		run_to_quickfix({ "php", "-l", file }, {
			title = "php -l " .. vim.fs.basename(file),
			cwd = script_cwd(),
		})
	end, { desc = "Syntax-check the current file with php -l" })

	command("PhpServe", function(cmd)
		if not have("php", "brew install shivammathur/php/php@8.4") then
			return
		end

		local root = M.laravel_root()
		if root then
			-- A Laravel app has a front controller and a router script; its
			-- own `artisan serve` wires both up correctly.
			run_in_terminal(artisan_cmd({ "serve" }), { title = "artisan serve", cwd = root })
			return
		end

		-- Vanilla: PHP's built-in server, docroot at the project root or the
		-- file's directory, so `php -S` serves the tree you are editing.
		local docroot = script_cwd()
		local addr = cmd.fargs[1] or "localhost:8000"
		run_in_terminal({ "php", "-S", addr, "-t", docroot }, {
			title = "php -S " .. addr,
			cwd = docroot,
		})
	end, { nargs = "?", desc = "Serve this project (artisan serve in Laravel, php -S otherwise)" })

	command("PhpTest", function(cmd)
		save_if_modified()
		local root = M.root()

		-- Laravel wraps the runner so it loads the framework's test bootstrap.
		if M.laravel_root() then
			if not artisan_guard() then
				return
			end
			local args = { "test" }
			vim.list_extend(args, cmd.fargs)
			run_to_quickfix(artisan_cmd(args), { title = "artisan test", cwd = M.laravel_root() })
			return
		end

        -- Vanilla: prefer the project's own runner, then a global one.
		local candidates = {}
		if root then
			candidates[#candidates + 1] = root .. "/vendor/bin/pest"
			candidates[#candidates + 1] = root .. "/vendor/bin/phpunit"
		end

		local runner
		for _, c in ipairs(candidates) do
			if vim.fn.executable(c) == 1 then
				runner = c
				break
			end
		end
		runner = runner or (vim.fn.executable("phpunit") == 1 and "phpunit" or nil)

		if not runner then
			vim.notify(
				"no test runner found -- composer require --dev phpunit/phpunit (or pestphp/pest)",
				vim.log.levels.WARN,
				{ title = "php" }
			)
			return
		end

		local args = { runner }
		vim.list_extend(args, cmd.fargs)
		run_to_quickfix(args, { title = vim.fs.basename(runner), cwd = root or script_cwd() })
	end, { nargs = "*", desc = "Run tests (artisan test in Laravel, phpunit/pest otherwise)" })

	command("PhpRepl", function()
		if not have("php", "brew install shivammathur/php/php@8.4") then
			return
		end
		-- Tinker boots the whole app and is far more useful when there is one;
		-- `php -a` is the bare interactive shell otherwise.
		if M.laravel_root() then
			run_in_terminal(artisan_cmd({ "tinker" }), { title = "artisan tinker", cwd = M.laravel_root() })
		else
			run_in_terminal({ "php", "-a" }, { title = "php -a", cwd = script_cwd() })
		end
	end, { desc = "Interactive PHP shell (Tinker in Laravel, php -a otherwise)" })

	command("PhpInfo", function()
		local root = M.root()
		local laravel = M.laravel_root()
		local local_pint = root and (root .. "/vendor/bin/pint")
		local lines = {
			"kind:           " .. (laravel and "Laravel app" or (root and "composer project" or "loose PHP file")),
			"composer root:  " .. (root or "-"),
			"laravel root:   " .. (laravel or "-"),
			"php:            " .. (vim.fn.exepath("php") ~= "" and vim.fn.exepath("php") or "NOT FOUND"),
			"php version:    " .. (vim.fn.exepath("php") ~= "" and vim.fn.system({ "php", "-r", "echo PHP_VERSION;" }) or "-"),
			"composer:       " .. (vim.fn.exepath("composer") ~= "" and vim.fn.exepath("composer") or "NOT FOUND"),
			"formatter:      " .. (
				(local_pint and vim.fn.executable(local_pint) == 1) and (local_pint .. " (project)")
				or (vim.fn.exepath("pint") ~= "" and (vim.fn.exepath("pint") .. " (global)") or "NOT FOUND")
			),
			"php-cs-fixer:   " .. (vim.fn.exepath("php-cs-fixer") ~= "" and vim.fn.exepath("php-cs-fixer") or "NOT FOUND"),
		}
		if laravel then
			lines[#lines + 1] = "artisan cmds:   " .. #load_artisan_commands() .. " cached"
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "php" })
	end, { desc = "Show the resolved PHP context for this buffer" })

	command("LaravelInfo", function()
		local root = M.laravel_root()
		local lines = {
			"composer root:  " .. (M.root() or "-"),
			"laravel root:   " .. (root or "- (not a Laravel app)"),
			"laravel version:" .. (laravel_version(root) and (" " .. laravel_version(root)) or " -"),
			"php:            " .. (vim.fn.exepath("php") ~= "" and vim.fn.exepath("php") or "NOT FOUND"),
			"composer:       " .. (vim.fn.exepath("composer") ~= "" and vim.fn.exepath("composer") or "NOT FOUND"),
			"laravel cli:    " .. (vim.fn.exepath("laravel") ~= "" and vim.fn.exepath("laravel") or "NOT FOUND"),
			"pint:           " .. (
				(M.root() and vim.fn.executable(M.root() .. "/vendor/bin/pint") == 1)
					and (M.root() .. "/vendor/bin/pint")
				or (vim.fn.exepath("pint") ~= "" and vim.fn.exepath("pint") or "NOT FOUND")
			),
			"artisan cmds:   " .. #load_artisan_commands() .. " cached",
		}
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "laravel" })
	end, { desc = "Show the resolved Laravel context for this buffer" })

	command("ArtisanReload", function()
		artisan_commands = nil
		local n = #load_artisan_commands()
		vim.notify("reloaded " .. n .. " artisan commands", vim.log.levels.INFO, { title = "laravel" })
	end, { desc = "Refresh the cached artisan command list after adding a package" })
end

return M
