-- jdtls start-up, once per Java buffer.
--
-- This is the nvim-jdtls design: rather than a single server for the editor,
-- each project root gets its own eclipse.jdt.ls with its own on-disk
-- workspace. Running it from an ftplugin is what makes that per-project
-- rooting work -- `vim.lsp.config` has no equivalent.
--
-- The plugin spec is in engine.plugins.java; the Mason packages it needs
-- (jdtls, java-debug-adapter, java-test) are in engine.plugins.lsp.mason.

-- Load nvim-jdtls before anything below touches it. lazy.nvim's `ft = "java"`
-- handler and Neovim's ftplugin sourcing both run on FileType with no
-- guaranteed order, so the first Java file opened in a session can otherwise
-- reach this line with the module not yet on the runtimepath.
pcall(function()
	require("lazy").load({ plugins = { "nvim-jdtls" } })
end)

local ok, jdtls = pcall(require, "jdtls")
if not ok then
	vim.notify("nvim-jdtls is not installed -- run :Lazy sync", vim.log.levels.ERROR)
	return
end

local mason = vim.fn.stdpath("data") .. "/mason"

local launcher = mason .. "/bin/jdtls"
if vim.fn.executable(launcher) ~= 1 then
	vim.notify("jdtls not found -- run :MasonInstall jdtls", vim.log.levels.ERROR)
	return
end

-- ---------------------------------------------------------------------------
-- Project root
-- ---------------------------------------------------------------------------
-- Ordered most specific first. The Gradle markers come before .git because a
-- monorepo's .git is usually above the actual Java project, and rooting jdtls
-- too high makes it index everything and resolve nothing.
local root_markers = {
	"gradlew",
	"mvnw",
	"settings.gradle",
	"settings.gradle.kts",
	"build.gradle",
	"build.gradle.kts",
	"pom.xml",
	".git",
}

local root_dir = vim.fs.root(0, root_markers)
if not root_dir then
	-- A loose .java file with no project around it. jdtls can still serve it in
	-- single-file mode, but it has no classpath, so completion is limited to
	-- the JDK -- worth saying out loud rather than looking broken.
	root_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
	vim.notify_once(
		"No Gradle/Maven/git root found -- jdtls is running in single-file mode",
		vim.log.levels.WARN
	)
end

-- ---------------------------------------------------------------------------
-- Per-project workspace
-- ---------------------------------------------------------------------------
-- jdtls writes an index, build output and settings here. It must be unique per
-- project: point two projects at one workspace and you get stale classpaths and
-- phantom errors that survive a restart. Kept under stdpath("cache") so it is
-- throwaway -- delete the directory to force a clean re-index.
local normalized_root = vim.fs.normalize(root_dir)
local workspace_name = vim.fs.basename(normalized_root) .. "-" .. vim.fn.sha256(normalized_root):sub(1, 12)
local workspace = vim.fn.stdpath("cache") .. "/jdtls/" .. workspace_name

-- ---------------------------------------------------------------------------
-- Bundles: debugging and test running
-- ---------------------------------------------------------------------------
-- These are OSGi bundles loaded into the server, not separate processes.
-- Without java-debug-adapter there is no `java` DAP adapter at all; without
-- java-test the test-runner commands do not exist.
local bundles = {}

vim.list_extend(
	bundles,
	vim.fn.glob(mason .. "/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true)
)

-- java-test ships ~32 jars, but two of them must NOT be passed as bundles:
--
--   com.microsoft.java.test.runner-jar-with-dependencies.jar
--   jacocoagent.jar
--
-- Both are plain fat jars with no OSGi metadata. jdtls accepts them into the
-- bundle list and then blocks forever inside synchronizeBundles() waiting on a
-- client command that never resolves -- the server attaches, reports a minimal
-- capability set, and never registers definition/hover/formatting. It looks
-- exactly like "jdtls is just slow", which is why this is worth spelling out.
local test_bundle_excludes = {
	"com.microsoft.java.test.runner-jar-with-dependencies.jar",
	"jacocoagent.jar",
}

for _, jar in ipairs(vim.fn.glob(mason .. "/packages/java-test/extension/server/*.jar", true, true)) do
	local name = vim.fs.basename(jar)
	if not vim.tbl_contains(test_bundle_excludes, name) then
		bundles[#bundles + 1] = jar
	end
end

-- ---------------------------------------------------------------------------
-- JDKs known to the server
-- ---------------------------------------------------------------------------
-- jdtls must be told which JDKs exist, or "Java 21" in a Gradle toolchain is
-- unresolvable and every file reports errors. The macOS helper checks mise,
-- Apple Silicon Homebrew, and standard /Library JDK bundles in that order.
--
-- `default = true` picks the one used when a project states no preference.
-- 21 is default because that is what the game project targets.
local runtimes = require("engine.core.macos").java_runtimes()

-- Homebrew's versioned OpenJDK formulae are keg-only, so a GUI-launched
-- Neovim commonly has no `java` on PATH even though discovery found the JDK.
-- jdtls must be able to launch before its `configuration.runtimes` settings
-- can take effect. Respect a valid explicit JAVA_HOME first, then use the
-- discovered default (or first available) runtime.
local function java_executable()
	if vim.env.JAVA_HOME and vim.fn.executable(vim.env.JAVA_HOME .. "/bin/java") == 1 then
		return vim.env.JAVA_HOME .. "/bin/java"
	end

	local fallback
	for _, runtime in ipairs(runtimes) do
		local executable = runtime.path .. "/bin/java"
		if vim.fn.executable(executable) == 1 then
			if runtime.default then
				return executable
			end
			fallback = fallback or executable
		end
	end
	return fallback
end

local cmd = { launcher }
local discovered_java = java_executable()
if discovered_java then
	vim.list_extend(cmd, { "--java-executable", discovered_java })
end
vim.list_extend(cmd, { "-data", workspace })

-- ---------------------------------------------------------------------------
-- Capabilities: reuse this config's completion engine
-- ---------------------------------------------------------------------------
-- nvim-cmp, not blink -- matching engine.plugins.nvim-cmp. Without this jdtls
-- advertises no snippet support and every method completion inserts the name
-- only, with no parameter placeholders.
local capabilities = vim.lsp.protocol.make_client_capabilities()
local cmp_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if cmp_ok then
	capabilities = cmp_nvim_lsp.default_capabilities()
end

-- Tells jdtls this client understands its non-standard extensions: the
-- progress reports, the "class file contents" scheme that makes go-to-definition
-- work into a dependency jar, and the refactoring actions.
local extendedClientCapabilities = jdtls.extendedClientCapabilities
extendedClientCapabilities.resolveAdditionalTextEditsSupport = true

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------
-- Buffer-local, and deliberately only for things the generic LSP maps in
-- lspconfig.lua cannot do. gd/gr/K/<leader>ca/<leader>rn keep working there
-- and are not redefined here.
local function on_attach(_, bufnr)
	local map = function(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
	end

	-- Imports. The single most-used Java editor operation, and there is no
	-- standard LSP request for it.
	map("n", "<leader>jo", jdtls.organize_imports, "Java: organize imports")

	-- Refactors. jdtls exposes these as code actions with a selection, which
	-- the generic <leader>ca cannot supply from visual mode correctly.
	map("n", "<leader>jv", jdtls.extract_variable, "Java: extract variable")
	map("v", "<leader>jv", function()
		jdtls.extract_variable({ visual = true })
	end, "Java: extract variable")
	map("n", "<leader>jc", jdtls.extract_constant, "Java: extract constant")
	map("v", "<leader>jc", function()
		jdtls.extract_constant({ visual = true })
	end, "Java: extract constant")
	map("v", "<leader>jm", function()
		jdtls.extract_method({ visual = true })
	end, "Java: extract method")

	-- Tests, via the java-test bundle.
	map("n", "<leader>jt", jdtls.test_nearest_method, "Java: test method under cursor")
	map("n", "<leader>jT", jdtls.test_class, "Java: test this class")

	-- Debugging. setup_dap_main_class_configs scans the project for classes
	-- with a main method and registers a dap configuration per class, so
	-- <leader>dc has something to launch without a hand-written launch.json.
	local dap_ok, jdtls_dap = pcall(require, "jdtls.dap")
	if dap_ok then
		jdtls_dap.setup_dap({ hotcodereplace = "auto" })
		-- Deferred: it needs the server's project model, which is not ready at
		-- attach time. Failing quietly here is fine -- it just means no
		-- main-class configs until the next Java buffer.
		pcall(jdtls_dap.setup_dap_main_class_configs)
	end

	map("n", "<leader>jR", function()
		pcall(require("jdtls.dap").setup_dap_main_class_configs)
		vim.notify("Rescanned for main classes", vim.log.levels.INFO)
	end, "Java: refresh DAP main-class configs")

	-- Inlay hints. The shared LspAttach handler in lspconfig.lua guards these
	-- behind a misspelled capability key that never matches, so opt in here --
	-- the same workaround rustaceanvim and intelephense use in this config.
	vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
end

-- ---------------------------------------------------------------------------
-- Start (or attach to an already-running server for this root)
-- ---------------------------------------------------------------------------
jdtls.start_or_attach({
	cmd = cmd,
	root_dir = root_dir,
	capabilities = capabilities,
	on_attach = on_attach,

	init_options = {
		bundles = bundles,
		extendedClientCapabilities = extendedClientCapabilities,
	},

	settings = {
		java = {
			configuration = {
				runtimes = runtimes,
				-- Respect .classpath/.project if a project has them, rather
				-- than re-deriving and fighting the build tool.
				updateBuildConfiguration = "interactive",
			},

			-- Gradle. The wrapper is authoritative: using it means jdtls
			-- resolves the same dependency versions as `./gradlew build`,
			-- which is the whole point of having a wrapper.
			import = {
				gradle = {
					enabled = true,
					wrapper = { enabled = true },
				},
				maven = { enabled = true },
			},

			-- Show the actual compile errors from the build, not just the
			-- parser's view.
			errors = { incompleteClasspath = { severity = "warning" } },

			-- Completion quality-of-life. The favorites are static-import
			-- candidates offered without typing the class name first --
			-- assertEquals, assertThat and the JUnit/Mockito entry points.
			completion = {
				favoriteStaticMembers = {
					"org.junit.jupiter.api.Assertions.*",
					"org.junit.Assert.*",
					"org.mockito.Mockito.*",
					"org.hamcrest.MatcherAssert.assertThat",
					"org.hamcrest.Matchers.*",
					-- LWJGL is static-import heavy: the tutorial writes
					-- glfwInit(), glClear(), GL_COLOR_BUFFER_BIT unqualified.
					"org.lwjgl.glfw.GLFW.*",
					"org.lwjgl.opengl.GL11.*",
					"org.lwjgl.opengl.GL20.*",
					"org.lwjgl.opengl.GL30.*",
					"org.lwjgl.system.MemoryUtil.*",
				},
				importOrder = { "java", "javax", "com", "org" },
			},

			sources = {
				organizeImports = {
					-- Collapse to a wildcard only at 99 -- effectively never.
					-- Explicit imports are easier to follow along a video with.
					starThreshold = 99,
					staticStarThreshold = 99,
				},
			},

			-- Generated code: getters/setters/equals/hashCode/toString.
			codeGeneration = {
				toString = {
					template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
				},
				useBlocks = true,
				hashCodeEquals = { useJava7Objects = true },
			},

			-- Formatting is jdtls's own Eclipse formatter. conform.nvim has no
			-- Java entry, and its default_format_opts sets lsp_format =
			-- "fallback", so :Format and format-on-save route here. That keeps
			-- one formatter rather than adding google-java-format's opinions.
			format = { enabled = true },

			inlayHints = {
				parameterNames = { enabled = "literals" },
			},

			-- Off: it indexes every jar on the classpath to offer types you
			-- have not imported. On a project with LWJGL's natives that is a
			-- lot of scanning for little gain.
			maven = { downloadSources = true },
			references = { includeDecompiledSources = true },
			signatureHelp = { enabled = true },
			contentProvider = { preferred = "fernflower" },
		},
	},
})
