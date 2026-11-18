-- Java half of :Skel.
--
-- Same shape as the C# half (engine.tools.skeleton_csharp): work out where the
-- file sits, guess what kind of type its name implies, and emit a skeleton.
--
-- The difference is that Java's version of "where does this file sit" is not a
-- convention the tooling is free to reinterpret -- javac requires the package
-- to match the directory path below the source root, so the package is read
-- straight off the path:
--
--   src/main/java/dev/salar/game/Window.java   ->  package dev.salar.game;
--   src/test/java/dev/salar/game/WindowTest.java  ->  package dev.salar.game;
--
-- Kind resolution is by filename convention, so `:Skel` with no argument does
-- the right thing for the naming you already use. Pass a kind to override it:
-- `:Skel record`, `:Skel utility`, `:Skel annotation`, ...
--
-- The Spring-flavoured templates (controller, service, repository, entity,
-- config, component) are only *detected* when the build file actually mentions
-- Spring; in a plain project a FooController is just a class. They stay
-- available by name either way.

local M = {}

local uv = vim.uv or vim.loop

-- Ordered most specific first, matching ftplugin/java.lua: a monorepo's .git
-- usually sits above the Java project, so build files win.
local ROOT_MARKERS = {
	"pom.xml",
	"build.gradle",
	"build.gradle.kts",
	"settings.gradle",
	"settings.gradle.kts",
	"gradlew",
	"mvnw",
	".git",
}

local function normalize(path)
	return (path or ""):gsub("\\", "/")
end

local function is_file(path)
	local stat = path and uv.fs_stat(path)
	return (stat and stat.type == "file") or false
end

---A Java identifier: letters, digits and underscores, not starting with a digit.
local function sanitize_identifier(part)
	local id = part:gsub("[^%w_]", "_")
	if id:match("^%d") then
		id = "_" .. id
	end
	return id
end

-- ---------------------------------------------------------------------------
-- Project context
-- ---------------------------------------------------------------------------

---The package the file belongs to, derived from its path.
---@param path string absolute path of the buffer
---@return string package dotted package name ("" for the default package)
local function package_for(path)
	local dir = normalize(vim.fn.fnamemodify(path, ":h"))
	local rest

	-- Maven/Gradle layout. The `[^/]+` is the source set, so this covers
	-- src/main/java, src/test/java and src/integrationTest/java alike.
	for _, pattern in ipairs({ "^.*/src/[^/]+/java/?(.*)$", "^.*/src/java/?(.*)$" }) do
		rest = dir:match(pattern)
		if rest then
			break
		end
	end

	if not rest then
		-- No recognisable source set: measure from the build root instead, so a
		-- loose file in a scratch project still gets a package matching its
		-- folders rather than landing in the default package.
		local root = vim.fs.root(path, ROOT_MARKERS) or dir
		local rel = vim.fs.relpath(root, dir)
		if not rel or rel == "." or rel:match("^%.%.") then
			return ""
		end
		rest = normalize(rel):gsub("^src/", "")
	end

	local parts = {}
	for _, part in ipairs(vim.split(rest, "/", { plain = true })) do
		if part ~= "" and part ~= "." then
			parts[#parts + 1] = sanitize_identifier(part)
		end
	end

	return table.concat(parts, ".")
end

-- Build files are read once per root per session. Adding a dependency and
-- expecting :Skel to notice means restarting Neovim -- a fair trade for not
-- re-reading a pom.xml on every invocation.
local manifest_cache = {}

local function build_manifest(root)
	if manifest_cache[root] then
		return manifest_cache[root]
	end

	local chunks = {}
	for _, name in ipairs({ "pom.xml", "build.gradle", "build.gradle.kts", "gradle/libs.versions.toml" }) do
		local file = root .. "/" .. name
		if is_file(file) then
			local ok, lines = pcall(vim.fn.readfile, file)
			if ok then
				chunks[#chunks + 1] = table.concat(lines, "\n")
			end
		end
	end

	manifest_cache[root] = table.concat(chunks, "\n")
	return manifest_cache[root]
end

---What the templates need to know about the surrounding project.
local function project_context(path)
	local root = vim.fs.root(path, ROOT_MARKERS) or vim.fn.fnamemodify(path, ":h")
	local manifest = build_manifest(root)

	local function has(needle)
		return manifest:find(needle, 1, true) ~= nil
	end

	-- JUnit 5 unless the build file only knows about JUnit 4. A project with no
	-- test dependency at all gets 5, which is the right default for new code.
	local junit5 = true
	if not has("junit-jupiter") and (has("junit:junit") or has("junit</artifactId>")) then
		junit5 = false
	end

	return {
		root = root,
		spring = has("springframework") or has("spring-boot"),
		jpa = has("persistence") or has("data-jpa") or has("hibernate"),
		-- Spring Boot 3 moved the EE annotations from javax to jakarta. Only a
		-- build file that still names javax gets the old package.
		ee = (has("javax.persistence") and not has("jakarta")) and "javax" or "jakarta",
		junit5 = junit5,
	}
end

-- ---------------------------------------------------------------------------
-- Kind detection
-- ---------------------------------------------------------------------------

---Guess what the file is meant to hold from its name and folder.
---@param stem string filename without extension
---@param path string absolute path
---@param ctx table project context
---@return string kind
local function detect_kind(stem, path, ctx)
	local dir = normalize(vim.fn.fnamemodify(path, ":h"))

	-- The two files whose names javac gives meaning to.
	if stem == "package-info" then
		return "packageinfo"
	end
	if stem == "module-info" then
		return "moduleinfo"
	end

	if ctx.spring and stem:match("Application$") then
		return "springboot"
	end
	if stem == "Main" or stem == "App" or stem == "Launcher" then
		return "main"
	end

	-- Anything under a test source set is a test, whatever it is called. The
	-- `[^/]*[Tt]est[^/]*` catches src/integrationTest/java too.
	if dir:match("/src/[^/]*[Tt]est[^/]*/java") or stem:match("Tests?$") or stem:match("IT$") then
		return "test"
	end

	if stem:match("Exception$") then
		return "exception"
	end
	if stem:match("Impl$") then
		return "impl"
	end
	if stem:match("Controller$") then
		return ctx.spring and "controller" or "class"
	end
	if stem:match("Repository$") or stem:match("Dao$") then
		-- Spring Data generates the implementation; elsewhere a repository is
		-- an interface with a hand-written Impl beside it.
		return ctx.spring and "repository" or "interface"
	end
	if stem:match("Service$") then
		return ctx.spring and "service" or "interface"
	end
	if stem:match("Config$") or stem:match("Configuration$") then
		return ctx.spring and "config" or "class"
	end
	if ctx.jpa and (stem:match("Entity$") or dir:match("/entit[^/]*$") or dir:match("/models?$")) then
		return "entity"
	end
	if stem:match("Dto$") or stem:match("Request$") or stem:match("Response$") then
		return "record"
	end
	if stem:match("Utils?$") or stem:match("Helper$") then
		return "utility"
	end
	if dir:match("/enums?$") then
		return "enum"
	end
	if ctx.spring and (stem:match("Component$") or stem:match("Listener$")) then
		return "component"
	end

	return "class"
end

-- ---------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------

---Each template returns { body = {...}, imports = {...}, cursor = n }, or
---{ raw = {...} } for the files that must not get a package/import banner.
---@type table<string, fun(ctx: table): table>
local templates = {}

templates.class = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. " {",
			"\t",
			"}",
		},
		cursor = 2,
	}
end

templates.abstract = function(ctx)
	return {
		body = {
			"public abstract class " .. ctx.name .. " {",
			"\t",
			"}",
		},
		cursor = 2,
	}
end

templates.final = function(ctx)
	return {
		body = {
			"public final class " .. ctx.name .. " {",
			"\t",
			"}",
		},
		cursor = 2,
	}
end

templates.interface = function(ctx)
	return {
		body = {
			"public interface " .. ctx.name .. " {",
			"\t",
			"}",
		},
		cursor = 2,
	}
end

-- FooServiceImpl implements FooService. Falls back to a plain class when the
-- kind is forced on a file whose name does not end in Impl.
templates.impl = function(ctx)
	local iface = ctx.name:match("^(.+)Impl$")
	if not iface then
		return templates.class(ctx)
	end

	return {
		body = {
			"public class " .. ctx.name .. " implements " .. iface .. " {",
			"\t",
			"}",
		},
		cursor = 2,
	}
end

templates.record = function(ctx)
	return {
		body = {
			"public record " .. ctx.name .. "(",
			"\t",
			") {",
			"}",
		},
		cursor = 2,
	}
end

templates.enum = function(ctx)
	return {
		body = {
			"public enum " .. ctx.name .. " {",
			"\t",
			"}",
		},
		cursor = 2,
	}
end

templates.annotation = function(ctx)
	return {
		body = {
			"@Retention(RetentionPolicy.RUNTIME)",
			"@Target({ ElementType.TYPE, ElementType.METHOD })",
			"public @interface " .. ctx.name .. " {",
			"\t",
			"}",
		},
		imports = {
			"java.lang.annotation.ElementType",
			"java.lang.annotation.Retention",
			"java.lang.annotation.RetentionPolicy",
			"java.lang.annotation.Target",
		},
		cursor = 4,
	}
end

-- Unchecked by default: a checked exception forces every caller to handle it,
-- which is rarely what a new exception type wants. `:Skel exception` then edit
-- `extends` if you do want one.
templates.exception = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. " extends RuntimeException {",
			"\tpublic " .. ctx.name .. "(String message) {",
			"\t\tsuper(message);",
			"\t}",
			"",
			"\tpublic " .. ctx.name .. "(String message, Throwable cause) {",
			"\t\tsuper(message, cause);",
			"\t}",
			"}",
		},
		cursor = 3,
	}
end

-- Static holder: final so it cannot be extended, private constructor so it
-- cannot be instantiated.
templates.utility = function(ctx)
	return {
		body = {
			"public final class " .. ctx.name .. " {",
			"\tprivate " .. ctx.name .. "() {",
			"\t}",
			"",
			"\t",
			"}",
		},
		cursor = 5,
	}
end

templates.main = function(ctx)
	return {
		body = {
			"public class " .. ctx.name .. " {",
			"\tpublic static void main(String[] args) {",
			'\t\tSystem.out.println("Hello, world!");',
			"\t}",
			"}",
		},
		cursor = 3,
	}
end

templates.test = function(ctx)
	local subject = ctx.name:gsub("Tests?$", ""):gsub("IT$", "")

	if not ctx.junit5 then
		return {
			body = {
				"public class " .. ctx.name .. " {",
				"\t@Test",
				"\tpublic void " .. subject:lower() .. "DoesSomething() {",
				"\t\t",
				"\t}",
				"}",
			},
			imports = { "org.junit.Test" },
			cursor = 4,
		}
	end

	-- JUnit 5 does not require public: the engine uses reflection, and the
	-- convention is package-private test classes and methods.
	return {
		body = {
			"class " .. ctx.name .. " {",
			"\t@Test",
			"\tvoid " .. subject:lower() .. "DoesSomething() {",
			"\t\t",
			"\t}",
			"}",
		},
		imports = { "org.junit.jupiter.api.Test" },
		cursor = 4,
	}
end

templates.springboot = function(ctx)
	return {
		body = {
			"@SpringBootApplication",
			"public class " .. ctx.name .. " {",
			"\tpublic static void main(String[] args) {",
			"\t\tSpringApplication.run(" .. ctx.name .. ".class, args);",
			"\t}",
			"}",
		},
		imports = {
			"org.springframework.boot.SpringApplication",
			"org.springframework.boot.autoconfigure.SpringBootApplication",
		},
		cursor = 4,
	}
end

templates.controller = function(ctx)
	local resource = ctx.name:gsub("Controller$", ""):lower()
	return {
		body = {
			"@RestController",
			'@RequestMapping("/api/' .. resource .. 's")',
			"public class " .. ctx.name .. " {",
			"\t@GetMapping",
			"\tpublic ResponseEntity<?> list() {",
			"\t\treturn ResponseEntity.ok().build();",
			"\t}",
			"}",
		},
		imports = {
			"org.springframework.http.ResponseEntity",
			"org.springframework.web.bind.annotation.GetMapping",
			"org.springframework.web.bind.annotation.RequestMapping",
			"org.springframework.web.bind.annotation.RestController",
		},
		cursor = 6,
	}
end

templates.service = function(ctx)
	return {
		body = {
			"@Service",
			"public class " .. ctx.name .. " {",
			"\t",
			"}",
		},
		imports = { "org.springframework.stereotype.Service" },
		cursor = 3,
	}
end

templates.component = function(ctx)
	return {
		body = {
			"@Component",
			"public class " .. ctx.name .. " {",
			"\t",
			"}",
		},
		imports = { "org.springframework.stereotype.Component" },
		cursor = 3,
	}
end

templates.config = function(ctx)
	return {
		body = {
			"@Configuration",
			"public class " .. ctx.name .. " {",
			"\t",
			"}",
		},
		imports = { "org.springframework.context.annotation.Configuration" },
		cursor = 3,
	}
end

templates.repository = function(ctx)
	-- Spring Data derives the implementation from the interface, so the entity
	-- and its id type are the only things to fill in.
	local entity = ctx.name:gsub("Repository$", ""):gsub("Dao$", "")
	return {
		body = {
			"@Repository",
			"public interface " .. ctx.name .. " extends JpaRepository<" .. entity .. ", Long> {",
			"\t",
			"}",
		},
		imports = {
			"org.springframework.data.jpa.repository.JpaRepository",
			"org.springframework.stereotype.Repository",
		},
		cursor = 3,
	}
end

templates.entity = function(ctx)
	local table_name = ctx.name:gsub("Entity$", ""):lower() .. "s"
	return {
		body = {
			"@Entity",
			'@Table(name = "' .. table_name .. '")',
			"public class " .. ctx.name .. " {",
			"\t@Id",
			"\t@GeneratedValue(strategy = GenerationType.IDENTITY)",
			"\tprivate Long id;",
			"",
			"\t",
			"}",
		},
		imports = {
			ctx.ee .. ".persistence.Entity",
			ctx.ee .. ".persistence.GeneratedValue",
			ctx.ee .. ".persistence.GenerationType",
			ctx.ee .. ".persistence.Id",
			ctx.ee .. ".persistence.Table",
		},
		cursor = 8,
	}
end

-- package-info.java holds the package declaration and nothing else: its whole
-- job is to carry the package javadoc and package-level annotations.
templates.packageinfo = function(ctx)
	if ctx.package == "" then
		vim.notify("Skel: package-info.java needs to live inside a package", vim.log.levels.WARN)
		return { raw = { "// package-info.java belongs in a package directory" }, cursor = 1 }
	end

	return {
		raw = {
			"/**",
			" * ",
			" */",
			"package " .. ctx.package .. ";",
		},
		cursor = 2,
	}
end

-- module-info.java sits at the source root, so it has no package of its own.
templates.moduleinfo = function(ctx)
	local module = ctx.package ~= "" and ctx.package or sanitize_identifier(vim.fs.basename(ctx.root))
	return {
		raw = {
			"module " .. module .. " {",
			"\trequires java.base;",
			"",
			"\texports " .. module .. ";",
			"}",
		},
		cursor = 2,
	}
end

M.kinds = vim.tbl_keys(templates)
table.sort(M.kinds)

-- ---------------------------------------------------------------------------
-- Assembly
-- ---------------------------------------------------------------------------

---Import groups, in the order ftplugin/java.lua gives jdtls's organize-imports
---(java, javax, com, org, then everything else) so a later <leader>jo does not
---reshuffle what :Skel just wrote.
local IMPORT_GROUPS = { "java", "javax", "com", "org" }

local function import_group(name)
	local head = name:match("^([^.]+)")
	for i, prefix in ipairs(IMPORT_GROUPS) do
		if head == prefix then
			return i
		end
	end
	return #IMPORT_GROUPS + 1
end

---Templates are written with tabs so each one reads as a single indent level.
---Java buffers here take the global 'expandtab'/'shiftwidth', so expand them to
---whatever the buffer actually wants rather than leaving a tab/space mix for
---jdtls's formatter to clean up on the next save.
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

	local ctx = project_context(path)
	ctx.name = sanitize_identifier(stem)
	ctx.package = package_for(path)

	kind = kind or detect_kind(stem, path, ctx)

	local template = templates[kind]
	if not template then
		vim.notify(
			"Skel: unknown Java kind '" .. kind .. "' -- try one of: " .. table.concat(M.kinds, ", "),
			vim.log.levels.WARN
		)
		return nil
	end

	local result = template(ctx)

	-- package-info/module-info write their own first line.
	if result.raw then
		return reindent(result.raw), result.cursor
	end

	local lines = {}

	if ctx.package ~= "" then
		lines[#lines + 1] = "package " .. ctx.package .. ";"
		lines[#lines + 1] = ""
	end

	local imports = vim.deepcopy(result.imports or {})
	if #imports > 0 then
		table.sort(imports, function(a, b)
			local ga, gb = import_group(a), import_group(b)
			if ga ~= gb then
				return ga < gb
			end
			return a < b
		end)

		local previous
		for _, import in ipairs(imports) do
			-- Blank line between groups, the way organize-imports leaves them.
			if previous and import_group(import) ~= import_group(previous) then
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = "import " .. import .. ";"
			previous = import
		end
		lines[#lines + 1] = ""
	end

	local body_offset = #lines
	for _, line in ipairs(result.body) do
		lines[#lines + 1] = line
	end

	return reindent(lines), result.cursor and (body_offset + result.cursor) or nil
end

return M
