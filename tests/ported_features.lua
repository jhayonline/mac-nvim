vim.opt.runtimepath:prepend(vim.fn.getcwd())

if vim.env.MAC_NVIM_TEST_ISOLATED ~= "1" then
	local test_root = vim.fn.tempname()
	vim.fn.mkdir(test_root, "p")
	local env = vim.fn.environ()
	env.MAC_NVIM_TEST_ISOLATED = "1"
	env.XDG_DATA_HOME = test_root .. "/data"
	env.XDG_STATE_HOME = test_root .. "/state"
	env.XDG_CACHE_HOME = test_root .. "/cache"

	local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", debug.getinfo(1, "S").source:sub(2) }, {
		env = env,
		text = true,
	}):wait()
	if result.stdout and result.stdout ~= "" then
		io.stdout:write(result.stdout)
	end
	if result.stderr and result.stderr ~= "" then
		io.stderr:write(result.stderr)
	end
	vim.fn.delete(test_root, "rf")
	assert(result.code == 0, "isolated ported feature test failed with exit code " .. result.code)
	return
end

local function contains(values, expected)
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end
	return false
end

local function assert_contains(values, expected, message)
	assert(contains(values, expected), message .. ": " .. expected)
end

local root = vim.fn.getcwd()

local lockfile = vim.json.decode(table.concat(vim.fn.readfile(root .. "/lazy-lock.json"), "\n"))
local lock_count = vim.tbl_count(lockfile)
assert(lock_count >= 70, "lazy-lock.json should retain the full source lockfile, got " .. lock_count .. " entries")
for _, plugin in ipairs({ "lazy.nvim", "mason.nvim", "nvim-jdtls", "nvim-lspconfig", "roslyn.nvim" }) do
	assert(lockfile[plugin], "lazy-lock.json is missing required pin " .. plugin)
end

local csharp_doc = table.concat(vim.fn.readfile(root .. "/doc/csharp.md"), "\n")
assert(
	csharp_doc:find("netcoredbg%-osx%-amd64"),
	"C# setup must disclose that Mason currently installs the amd64 netcoredbg archive on Apple Silicon"
)
assert(csharp_doc:find("Rosetta 2", 1, true), "C# setup must state the Rosetta requirement for Mason netcoredbg")
assert(
	not csharp_doc:find("Rosetta/x64 binaries are unnecessary", 1, true),
	"C# setup must not claim every debugger path is native arm64"
)

local java_plugin = dofile(root .. "/lua/engine/plugins/java.lua")
assert(java_plugin[1][1] == "mfussenegger/nvim-jdtls", "Java plugin should declare nvim-jdtls")

local java_skeleton = require("engine.tools.skeleton_java")
for _, kind in ipairs({ "class", "interface", "test" }) do
	assert_contains(java_skeleton.kinds, kind, "Java skeleton kind missing")
end

local graphics = require("engine.core.graphics")
graphics.setup()
assert(vim.filetype.match({ filename = "shader.hlsl" }) == "hlsl", "HLSL filetype should be registered")
assert(vim.filetype.match({ filename = "shader.glslv" }) == "glsl", "legacy GLSL filetype should be registered")
assert(vim.api.nvim_get_commands({}).ShaderCheck, ":ShaderCheck should be registered")

local mason_setup
package.loaded.mason = { setup = function() end }
package.loaded["mason-lspconfig"] = {
	setup = function(opts)
		mason_setup = opts
	end,
}
local mason_spec = dofile(root .. "/lua/engine/plugins/lsp/mason.lua")
mason_spec.config()
assert(mason_setup, "Mason LSP setup should run")
for _, server in ipairs({ "vue_ls", "jdtls", "ols", "glsl_analyzer", "wgsl_analyzer", "neocmake" }) do
	assert_contains(mason_setup.ensure_installed, server, "Mason server missing")
end
assert_contains(
	mason_setup.automatic_enable.exclude,
	"rust_analyzer",
	"Mason must not auto-enable the intentionally disabled Rust analyzer"
)

local treesitter_setup
package.loaded["nvim-treesitter.query_predicates"] = {}
package.loaded["nvim-treesitter.configs"] = {
	setup = function(opts)
		treesitter_setup = opts
	end,
}
package.loaded["nvim-ts-autotag"] = { setup = function() end }
local treesitter_spec = dofile(root .. "/lua/engine/plugins/treesitter.lua")
treesitter_spec.config()
assert(treesitter_setup, "Treesitter setup should run")
for _, parser in ipairs({ "vue", "odin", "razor", "glsl", "wgsl", "wgsl_bevy", "cmake", "java" }) do
	assert_contains(treesitter_setup.ensure_installed, parser, "Treesitter parser missing")
end

-- Exercise the Java ftplugin's real jdtls configuration boundary. A fake
-- launcher and a small jdtls facade avoid starting an external server; the
-- assertion is on the configuration the ftplugin produces.
local mason_root = vim.fn.stdpath("data") .. "/mason"
local launcher = mason_root .. "/bin/jdtls"
vim.fn.mkdir(vim.fs.dirname(launcher), "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, launcher)
vim.fn.setfperm(launcher, "rwx------")

local projects_root = vim.fn.tempname()
local project = projects_root .. "/client-a/app"
local second_project = projects_root .. "/client-b/app"
vim.fn.mkdir(project .. "/src", "p")
vim.fn.mkdir(second_project .. "/src", "p")
vim.fn.writefile({}, project .. "/gradlew")
vim.fn.writefile({}, second_project .. "/gradlew")
vim.api.nvim_buf_set_name(0, project .. "/src/Example.java")

local fake_java_home = vim.fn.tempname()
local override_java_home = vim.fn.tempname()
vim.fn.mkdir(fake_java_home .. "/bin", "p")
vim.fn.mkdir(override_java_home .. "/bin", "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, fake_java_home .. "/bin/java")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, override_java_home .. "/bin/java")
vim.fn.setfperm(fake_java_home .. "/bin/java", "rwx------")
vim.fn.setfperm(override_java_home .. "/bin/java", "rwx------")
local expected_runtimes = {
	{ name = "JavaSE-21", path = fake_java_home, default = true },
}
package.loaded.lazy = { load = function() end }
package.loaded["engine.core.macos"] = {
	java_runtimes = function()
		return expected_runtimes
	end,
}

local jdtls_configs = {}
local original_java_home = vim.env.JAVA_HOME
vim.env.JAVA_HOME = nil
package.loaded.jdtls = {
	extendedClientCapabilities = {},
	start_or_attach = function(config)
		jdtls_configs[#jdtls_configs + 1] = config
	end,
}

dofile(root .. "/ftplugin/java.lua")
local jdtls_config = jdtls_configs[1]
assert(jdtls_config, "Java ftplugin should configure jdtls")
assert(
	vim.deep_equal(jdtls_config.settings.java.configuration.runtimes, expected_runtimes),
	"Java ftplugin should consume engine.core.macos.java_runtimes()"
)
assert(jdtls_config.cmd[2] == "--java-executable", "jdtls should receive an explicit discovered Java executable")
assert(jdtls_config.cmd[3] == fake_java_home .. "/bin/java", "jdtls should launch with the discovered JDK")
assert(
	jdtls_config.cmd[5]:match("^" .. vim.pesc(vim.fn.stdpath("cache") .. "/jdtls/")),
	"jdtls workspace should live under the Neovim cache"
)
assert(jdtls_config.cmd[5]:match("%-%x+$"), "jdtls workspace should include a root-derived collision-resistant hash")

vim.cmd.enew()
vim.api.nvim_buf_set_name(0, second_project .. "/src/Example.java")
vim.env.JAVA_HOME = override_java_home
dofile(root .. "/ftplugin/java.lua")
assert(jdtls_configs[2], "Java ftplugin should configure the second same-named project")
assert(jdtls_configs[2].cmd[5] ~= jdtls_config.cmd[5], "same-named Java projects must use different workspaces")
assert(jdtls_configs[2].cmd[3] == override_java_home .. "/bin/java", "a valid JAVA_HOME should override discovery")

vim.fn.delete(projects_root, "rf")
vim.fn.delete(fake_java_home, "rf")
vim.fn.delete(override_java_home, "rf")
vim.env.JAVA_HOME = original_java_home

-- The .NET and PHP modules must consume the shared path helper rather than
-- relying on the implementation host's PATH. Exercise setup with real temp
-- directories and assert the environment users of those modules observe.
local fake_dotnet_root = vim.fn.tempname()
local fake_php_bin = vim.fn.tempname()
vim.fn.mkdir(fake_dotnet_root, "p")
vim.fn.mkdir(fake_php_bin, "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, fake_dotnet_root .. "/dotnet")
vim.fn.setfperm(fake_dotnet_root .. "/dotnet", "rwx------")

package.loaded["engine.core.macos"].dotnet_roots = function()
	return { fake_dotnet_root }
end
package.loaded["engine.core.macos"].php_bin_dirs = function()
	return { fake_php_bin }
end

vim.env.DOTNET_ROOT = nil
vim.env.SSL_CERT_DIR = nil
vim.env.PATH = "/usr/bin"
package.loaded["engine.core.dotnet"] = nil
local dotnet = require("engine.core.dotnet")
dotnet.setup()

assert(vim.env.DOTNET_ROOT == fake_dotnet_root, ".NET should resolve roots through engine.core.macos")
assert(
	(":" .. vim.env.PATH .. ":"):find(":" .. fake_dotnet_root .. ":", 1, true),
	".NET root should be present on PATH"
)
assert(vim.env.SSL_CERT_DIR == nil, "macOS .NET setup should rely on Keychain, not a Linux SSL_CERT_DIR")

local commands = vim.api.nvim_get_commands({})
for _, command in ipairs({ "MvcCrud", "MvcScaffold", "MvcAlternate", "DotnetDevCerts" }) do
	assert(commands[command], "expanded ASP.NET workflow is missing :" .. command)
end

package.loaded["engine.core.php"] = nil
local php = require("engine.core.php")
php.setup()
assert(vim.env.PATH:find(fake_php_bin, 1, true) == 1, "PHP should resolve bins through engine.core.macos")

local netcoredbg = mason_root .. "/bin/netcoredbg"
local lldb_dap = mason_root .. "/bin/lldb-dap"
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, netcoredbg)
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, lldb_dap)
vim.fn.setfperm(netcoredbg, "rwx------")
vim.fn.setfperm(lldb_dap, "rwx------")
local dap = {
	adapters = {},
	configurations = {},
	continue = function() end,
	toggle_breakpoint = function() end,
	step_over = function() end,
	step_into = function() end,
	step_out = function() end,
	restart = function() end,
	terminate = function() end,
}
package.loaded.dap = dap
package.loaded["dap.utils"] = { pick_process = function() end }
local dap_spec = dofile(root .. "/lua/engine/plugins/dap.lua")
dap_spec.config()
assert(dap.configurations.razor == dap.configurations.cs, "Razor should reuse the C# DAP configurations")

vim.fn.delete(fake_dotnet_root, "rf")
vim.fn.delete(fake_php_bin, "rf")

print("Java plugin and runtime discovery: ok")
print("Graphics filetypes and command: ok")
print("Mason and Treesitter feature parity: ok")
print("Apple Silicon .NET/PHP bootstrap and Razor DAP: ok")
