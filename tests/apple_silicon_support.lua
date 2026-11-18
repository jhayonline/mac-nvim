vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function contains(values, expected)
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end
	return false
end

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(("%s\nexpected: %s\nactual:   %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local original_home = vim.env.HOME
local original_homebrew_prefix = vim.env.HOMEBREW_PREFIX

vim.env.HOMEBREW_PREFIX = nil
local macos = require("engine.core.macos")

assert_equal(macos.homebrew_prefix(), "/opt/homebrew", "M5 Macs should default to Apple Silicon Homebrew")

vim.env.HOMEBREW_PREFIX = "/custom/brew"
assert_equal(macos.homebrew_prefix(), "/custom/brew", "an explicit Homebrew prefix should win")
assert_equal(
	macos.dotnet_roots()[2],
	"/custom/brew/opt/dotnet/libexec",
	".NET discovery should follow the active Homebrew prefix"
)
assert_equal(
	macos.php_bin_dirs()[1],
	"/custom/brew/opt/php@8.4/bin",
	"PHP discovery should follow the active Homebrew prefix"
)
assert(
	contains(macos.php_bin_dirs(), "/custom/brew/bin"),
	"PHP tooling should include Homebrew's linked bin directory for Composer"
)

vim.env.HOMEBREW_PREFIX = nil
local dotnet_roots = macos.dotnet_roots()
assert(contains(dotnet_roots, original_home .. "/.dotnet"), ".NET discovery should include the user install")
assert(
	contains(dotnet_roots, "/opt/homebrew/opt/dotnet/libexec"),
	".NET discovery should include Apple Silicon Homebrew"
)

local php_dirs = macos.php_bin_dirs()
assert_equal(php_dirs[1], "/opt/homebrew/opt/php@8.4/bin", "PHP 8.4 should prefer Apple Silicon Homebrew")

local java_candidates = macos.java_runtime_candidates()
local java_21_paths
for _, candidate in ipairs(java_candidates) do
	if candidate.name == "JavaSE-21" then
		java_21_paths = candidate.paths
		break
	end
end
assert(java_21_paths, "Java 21 discovery candidates should exist")
assert(
	contains(java_21_paths, original_home .. "/.local/share/mise/installs/java/temurin-21"),
	"Java 21 discovery should include mise"
)
assert(
	contains(java_21_paths, "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"),
	"Java 21 discovery should include Homebrew OpenJDK"
)
assert(
	contains(java_21_paths, "/Library/Java/JavaVirtualMachines/*21*.jdk/Contents/Home"),
	"Java 21 discovery should include standard macOS JDK bundles"
)

local query_drivers = macos.clang_query_drivers()
for _, driver in ipairs({
	"/usr/bin/clang",
	"/usr/bin/clang++",
	"/opt/homebrew/bin/clang",
	"/opt/homebrew/bin/clang++",
	"/opt/homebrew/bin/gcc-*",
	"/opt/homebrew/bin/g++-*",
}) do
	assert(contains(query_drivers, driver), "missing clangd query driver " .. driver)
end

local fake_home = vim.fn.tempname()
local fake_jdk = fake_home .. "/.local/share/mise/installs/java/temurin-21"
vim.fn.mkdir(fake_jdk, "p")
vim.env.HOME = fake_home

local runtimes = macos.java_runtimes()
assert_equal(#runtimes, 1, "missing JDK candidates should be filtered")
assert_equal(runtimes[1].name, "JavaSE-21", "the existing Java 21 runtime should be returned")
assert_equal(runtimes[1].path, fake_jdk, "the real existing JDK path should be returned")
assert_equal(runtimes[1].default, true, "Java 21 should remain the default runtime")

vim.env.HOME = original_home
vim.env.HOMEBREW_PREFIX = original_homebrew_prefix
vim.fn.delete(fake_home, "rf")

print("Apple Silicon path discovery: ok")
