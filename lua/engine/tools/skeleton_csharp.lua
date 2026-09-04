-- C# half of :Skel.
--
-- The C++ side (engine.tools.skeleton) has to work out which header a source
-- file belongs to. C# has no headers, but it does have a namespace that must
-- track the folder layout, so the equivalent problem here is: given a path,
-- what namespace does this file live in, and what kind of type does its name
-- imply?
--
-- Namespace resolution follows the same rule the SDK uses for its own
-- templates: <RootNamespace> from the nearest .csproj (defaulting to the
-- project file name), plus the directory path from that .csproj down to the
-- file, joined with dots.
--
--   src/Shop.Web/Shop.Web.csproj          RootNamespace = Shop.Web
--   src/Shop.Web/Controllers/HomeController.cs  ->  namespace Shop.Web.Controllers;
--
-- Kind resolution is by filename convention, so `:Skel` with no argument does
-- the right thing for the naming you already use. Pass a kind to override it:
-- `:Skel record`, `:Skel apicontroller`, `:Skel dbcontext`, ...

local M = {}

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- Project context
-- ---------------------------------------------------------------------------

local function dotnet()
	return require("engine.core.dotnet")
end

---A .NET identifier: letters, digits and underscores, not starting with a digit.
local function sanitize_identifier(part)
	local id = part:gsub("[^%w_]", "_")
	if id:match("^%d") then
		id = "_" .. id
	end
	return id
end

---Namespace for the file being edited.
---@param path string absolute path of the buffer
---@return string namespace
---@return string|nil csproj the project file it was derived from
local function namespace_for(path)
	local csproj = dotnet().project()

	if not csproj then
		-- No project: fall back to the repo/directory name so the file is at
		-- least in a plausible namespace rather than the global one.
		local root = vim.fs.root(path, { ".git" }) or vim.fs.dirname(path)
		return sanitize_identifier(vim.fs.basename(root)), nil
	end

	local root_namespace = dotnet().msbuild_property(csproj, "RootNamespace")
		or vim.fn.fnamemodify(csproj, ":t:r")

	local parts = {}
	for _, part in ipairs(vim.split(root_namespace, ".", { plain = true })) do
		if part ~= "" then
			parts[#parts + 1] = sanitize_identifier(part)
		end
	end

	-- Directories between the .csproj and the file become namespace segments.
	local rel = vim.fs.relpath(vim.fs.dirname(csproj), vim.fs.dirname(path))
	if rel and rel ~= "." and rel ~= "" then
		for _, part in ipairs(vim.split(rel, "/", { plain = true })) do
			-- `obj`, `bin` and Properties are never part of a namespace, and a
			-- leading ".." means the file is outside the project entirely.
			if part ~= "" and part ~= "." and part ~= ".." then
				parts[#parts + 1] = sanitize_identifier(part)
			end
		end
	end

	return table.concat(parts, "."), csproj
end

---Modern SDK projects turn these on by default, and the templates below read
---very differently depending on them: with ImplicitUsings there is no `using
---System;` banner to write, and with Nullable the reference-type members need
---initialisers or `?`.
local function project_features(csproj)
	local implicit_usings = true
	local nullable = true

	if csproj then
		local iu = dotnet().msbuild_property(csproj, "ImplicitUsings")
		if iu then
			implicit_usings = iu:lower() == "enable" or iu:lower() == "true"
		end

		local nl = dotnet().msbuild_property(csproj, "Nullable")
		if nl then
			nullable = nl:lower() == "enable" or nl:lower() == "annotations"
		end
	end

	return { implicit_usings = implicit_usings, nullable = nullable }
end

-- ---------------------------------------------------------------------------
-- Kind detection
-- ---------------------------------------------------------------------------

---Guess what the file is meant to hold from its name and folder.
---@param stem string filename without extension
---@param path string absolute path
---@return string kind
local function detect_kind(stem, path)
	local dir = vim.fs.dirname(path)

	if stem == "Program" then
		return "program"
	end
	if stem == "Startup" then
		return "startup"
	end

	-- IFoo, but not Identity or Invoice: the character after I must be upper
	-- case and the one after that must not start a new word on its own.
	if stem:match("^I%u") then
		return "interface"
	end

	if stem:match("DbContext$") or stem:match("^%u.*Context$") and dir:match("Data$") then
		return "dbcontext"
	end
	if stem:match("Controller$") then
		-- Web API controllers live under an Api folder or in a project with no
		-- Views directory; MVC controllers return views.
		local project = dotnet().project()
		local project_dir = project and vim.fs.dirname(project)
		local has_views = project_dir and uv.fs_stat(project_dir .. "/Views") ~= nil
		if dir:match("[Aa]pi$") or not has_views then
			return "apicontroller"
		end
		return "controller"
	end
	if stem:match("Middleware$") then
		return "middleware"
	end
	if stem:match("Attribute$") then
		return "attribute"
	end
	if stem:match("Exception$") then
		return "exception"
	end
	if stem:match("Tests?$") or stem:match("^Test%u") then
		return "test"
	end
	if stem:match("Repository$") or stem:match("Service$") then
		return "service"
	end
	if stem:match("ViewModel$") or stem:match("Dto$") or stem:match("Request$") or stem:match("Response$") then
		return "record"
	end
	if stem:match("Options$") or stem:match("Settings$") or stem:match("Config$") then
		return "options"
	end
	if stem:match("Extensions$") then
		return "static"
	end
	if stem:match("Enum$") or dir:match("Enums$") then
		return "enum"
	end

	return "class"
end

-- ---------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------

---Each template returns { usings = {...}, body = {...} }. Usings are only
---emitted when the project has ImplicitUsings off, or when the namespace is
---not one of the implicit ones.
---@type table<string, fun(ctx: table): table>
local templates = {}

-- Namespaces the SDK already imports for you under <ImplicitUsings>enable</>.
-- Anything outside these lists still needs an explicit using.
local IMPLICIT_CONSOLE = {
	["System"] = true,
	["System.Collections.Generic"] = true,
	["System.IO"] = true,
	["System.Linq"] = true,
	["System.Net.Http"] = true,
	["System.Threading"] = true,
	["System.Threading.Tasks"] = true,
}

local IMPLICIT_WEB = {
	["Microsoft.AspNetCore.Builder"] = true,
	["Microsoft.AspNetCore.Hosting"] = true,
	["Microsoft.AspNetCore.Http"] = true,
	["Microsoft.AspNetCore.Routing"] = true,
	["Microsoft.Extensions.Configuration"] = true,
	["Microsoft.Extensions.DependencyInjection"] = true,
	["Microsoft.Extensions.Hosting"] = true,
	["Microsoft.Extensions.Logging"] = true,
}

templates.class = function(ctx)
	return {
		body = {
			"public class " .. ctx.name,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.static = function(ctx)
	return {
		body = {
			"public static class " .. ctx.name,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.abstract = function(ctx)
	return {
		body = {
			"public abstract class " .. ctx.name,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.sealed = function(ctx)
	return {
		body = {
			"public sealed class " .. ctx.name,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.interface = function(ctx)
	return {
		body = {
			"public interface " .. ctx.name,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.record = function(ctx)
	return {
		body = {
			"public record " .. ctx.name .. "(",
			"\t",
			");",
		},
		cursor = 2,
	}
end

templates.struct = function(ctx)
	return {
		body = {
			"public readonly record struct " .. ctx.name .. "(",
			"\t",
			");",
		},
		cursor = 2,
	}
end

templates.enum = function(ctx)
	return {
		body = {
			"public enum " .. ctx.name,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.exception = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. " : Exception",
			"{",
			"\tpublic " .. ctx.name .. "() { }",
			"",
			"\tpublic " .. ctx.name .. "(string message) : base(message) { }",
			"",
			"\tpublic " .. ctx.name .. "(string message, Exception inner) : base(message, inner) { }",
			"}",
		},
		usings = { "System" },
		cursor = 3,
	}
end

templates.attribute = function(ctx)
	return {
		body = {
			"[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]",
			"public sealed class " .. ctx.name .. " : Attribute",
			"{",
			"\t",
			"}",
		},
		usings = { "System" },
		cursor = 4,
	}
end

templates.options = function(ctx)
	-- Bound with builder.Services.Configure<T>(builder.Configuration.GetSection(T.SectionName)).
	local section = ctx.name:gsub("Options$", ""):gsub("Settings$", ""):gsub("Config$", "")
	return {
		body = {
			"public class " .. ctx.name,
			"{",
			'\tpublic const string SectionName = "' .. section .. '";',
			"",
			"\t",
			"}",
		},
		cursor = 5,
	}
end

-- A service/repository plus the interface it implements, in one file. Split
-- them apart once the interface earns its own file.
templates.service = function(ctx)
	local iface = "I" .. ctx.name
	return {
		body = {
			"public interface " .. iface,
			"{",
			"\t",
			"}",
			"",
			"public class " .. ctx.name .. " : " .. iface,
			"{",
			"\t",
			"}",
		},
		cursor = 3,
	}
end

templates.controller = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. " : Controller",
			"{",
			"\tpublic IActionResult Index()",
			"\t{",
			"\t\treturn View();",
			"\t}",
			"}",
		},
		usings = { "Microsoft.AspNetCore.Mvc" },
		cursor = 5,
	}
end

templates.apicontroller = function(ctx)
	return {
		body = {
			"[ApiController]",
			'[Route("api/[controller]")]',
			"public class " .. ctx.name .. " : ControllerBase",
			"{",
			"\t[HttpGet]",
			"\tpublic IActionResult Get()",
			"\t{",
			"\t\treturn Ok();",
			"\t}",
			"}",
		},
		usings = { "Microsoft.AspNetCore.Mvc" },
		cursor = 8,
	}
end

templates.dbcontext = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. "(DbContextOptions<" .. ctx.name .. "> options) : DbContext(options)",
			"{",
			"\t// public DbSet<Entity> Entities => Set<Entity>();",
			"",
			"\tprotected override void OnModelCreating(ModelBuilder modelBuilder)",
			"\t{",
			"\t\tbase.OnModelCreating(modelBuilder);",
			"\t}",
			"}",
		},
		usings = { "Microsoft.EntityFrameworkCore" },
		cursor = 3,
	}
end

templates.middleware = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. "(RequestDelegate next)",
			"{",
			"\tpublic async Task InvokeAsync(HttpContext context)",
			"\t{",
			"\t\tawait next(context);",
			"\t}",
			"}",
			"",
			"public static class " .. ctx.name .. "Extensions",
			"{",
			"\tpublic static IApplicationBuilder Use"
				.. ctx.name:gsub("Middleware$", "")
				.. "(this IApplicationBuilder app)",
			"\t{",
			"\t\treturn app.UseMiddleware<" .. ctx.name .. ">();",
			"\t}",
			"}",
		},
		usings = { "Microsoft.AspNetCore.Builder", "Microsoft.AspNetCore.Http" },
		cursor = 5,
	}
end

templates.test = function(ctx)
	return {
		body = {
			"public class " .. ctx.name,
			"{",
			"\t[Fact]",
			"\tpublic void " .. ctx.name:gsub("Tests?$", "") .. "_Does_Something()",
			"\t{",
			"\t\t",
			"\t}",
			"}",
		},
		usings = { "Xunit" },
		cursor = 6,
	}
end

-- Program.cs has no namespace: it is the top-level statements file.
templates.program = function(ctx)
	if ctx.web then
		return {
			raw = {
				"var builder = WebApplication.CreateBuilder(args);",
				"",
				"builder.Services.AddControllersWithViews();",
				"",
				"var app = builder.Build();",
				"",
				"if (!app.Environment.IsDevelopment())",
				"{",
				'\tapp.UseExceptionHandler("/Home/Error");',
				"\tapp.UseHsts();",
				"}",
				"",
				"app.UseHttpsRedirection();",
				"app.UseStaticFiles();",
				"app.UseRouting();",
				"app.UseAuthorization();",
				"",
				"app.MapControllerRoute(",
				'\tname: "default",',
				'\tpattern: "{controller=Home}/{action=Index}/{id?}");',
				"",
				"app.Run();",
			},
			cursor = 3,
		}
	end

	return {
		raw = {
			'Console.WriteLine("Hello, world!");',
		},
		cursor = 1,
	}
end

templates.minimalapi = function()
	return {
		raw = {
			"var builder = WebApplication.CreateBuilder(args);",
			"",
			"var app = builder.Build();",
			"",
			'app.MapGet("/", () => "Hello, world!");',
			"",
			"app.Run();",
		},
		cursor = 5,
	}
end

-- Startup.cs is pre-.NET 6 hosting; kept because plenty of MVC codebases and
-- tutorials still use it.
templates.startup = function()
	return {
		body = {
			"public class Startup(IConfiguration configuration)",
			"{",
			"\tpublic IConfiguration Configuration { get; } = configuration;",
			"",
			"\tpublic void ConfigureServices(IServiceCollection services)",
			"\t{",
			"\t\tservices.AddControllersWithViews();",
			"\t}",
			"",
			"\tpublic void Configure(IApplicationBuilder app, IWebHostEnvironment env)",
			"\t{",
			"\t\tapp.UseRouting();",
			"\t\tapp.UseEndpoints(endpoints => endpoints.MapDefaultControllerRoute());",
			"\t}",
			"}",
		},
		usings = {
			"Microsoft.AspNetCore.Builder",
			"Microsoft.AspNetCore.Hosting",
			"Microsoft.Extensions.Configuration",
			"Microsoft.Extensions.DependencyInjection",
		},
		cursor = 7,
	}
end

M.kinds = vim.tbl_keys(templates)
table.sort(M.kinds)

-- ---------------------------------------------------------------------------
-- Assembly
-- ---------------------------------------------------------------------------

---Templates are written with tabs so they read as one indent level each.
---ftplugin/cs.vim sets 'expandtab' with 'shiftwidth' 4 to match .NET
---convention and CSharpier, so expand them to whatever the buffer actually
---wants rather than leaving a tab/space mix for the formatter to clean up.
local function reindent(lines)
	if not vim.bo.expandtab then
		return lines
	end

	local width = vim.bo.shiftwidth
	if width == 0 then
		width = vim.bo.tabstop
	end
	local unit = string.rep(" ", width)

	return vim.tbl_map(function(line)
		local indent, rest = line:match("^(\t*)(.*)$")
		return indent:gsub("\t", unit) .. rest
	end, lines)
end

---@param kind string|nil explicit kind, or nil to detect from the filename
---@return string[]|nil lines
---@return integer|nil cursor_line
function M.build(kind)
	local path = vim.fn.expand("%:p")
	local stem = vim.fn.expand("%:t:r")

	if stem == "" then
		vim.notify("Skel: name the buffer first", vim.log.levels.WARN)
		return nil
	end

	kind = kind or detect_kind(stem, path)

	local template = templates[kind]
	if not template then
		vim.notify(
			"Skel: unknown C# kind '" .. kind .. "' -- try one of: " .. table.concat(M.kinds, ", "),
			vim.log.levels.WARN
		)
		return nil
	end

	local namespace, csproj = namespace_for(path)
	local features = project_features(csproj)
	local web = require("engine.core.dotnet").is_web_project(csproj)

	local result = template({ name = stem, namespace = namespace, web = web, features = features })

	-- Top-level-statement files (Program.cs, minimal API) are emitted verbatim:
	-- no namespace, no usings block.
	if result.raw then
		return reindent(result.raw), result.cursor
	end

	local lines = {}

	-- Usings the template asked for, minus whatever the SDK already imports.
	local usings = {}
	for _, ns in ipairs(result.usings or {}) do
		local implicit = features.implicit_usings
			and (IMPLICIT_CONSOLE[ns] or (web and IMPLICIT_WEB[ns]))
		if not implicit then
			usings[#usings + 1] = ns
		end
	end

	if #usings > 0 then
		table.sort(usings)
		for _, ns in ipairs(usings) do
			lines[#lines + 1] = "using " .. ns .. ";"
		end
		lines[#lines + 1] = ""
	end

	-- File-scoped namespace (C# 10+). Set g:skel_csharp_block_namespace = true
	-- if you are stuck on an older language version.
	local indented = false
	if namespace ~= "" then
		if vim.g.skel_csharp_block_namespace then
			lines[#lines + 1] = "namespace " .. namespace
			lines[#lines + 1] = "{"
			indented = true
		else
			lines[#lines + 1] = "namespace " .. namespace .. ";"
			lines[#lines + 1] = ""
		end
	end

	local body_offset = #lines
	for _, line in ipairs(result.body) do
		lines[#lines + 1] = indented and (line ~= "" and "\t" .. line or "") or line
	end

	if indented then
		lines[#lines + 1] = "}"
	end

	return reindent(lines), result.cursor and (body_offset + result.cursor) or nil
end

return M
