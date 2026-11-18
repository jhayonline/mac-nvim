-- Apple Silicon tool discovery shared by language-specific modules.
--
-- GUI-launched Neovim does not inherit a login shell's PATH, so the config
-- needs to know the stable locations used by Homebrew and macOS. Keep those
-- decisions here rather than scattering architecture-specific paths through
-- each language setup.

local M = {}

local uv = vim.uv or vim.loop

local function home()
	return vim.env.HOME or uv.os_homedir()
end

function M.homebrew_prefix()
	local configured = vim.env.HOMEBREW_PREFIX
	if configured and configured ~= "" then
		return configured
	end
	return "/opt/homebrew"
end

function M.dotnet_roots()
	return {
		home() .. "/.dotnet",
		M.homebrew_prefix() .. "/opt/dotnet/libexec",
		"/usr/local/opt/dotnet/libexec",
	}
end

function M.php_bin_dirs()
	local prefix = M.homebrew_prefix()
	return {
		prefix .. "/opt/php@8.4/bin",
		prefix .. "/opt/php/bin",
		prefix .. "/bin",
		home() .. "/.composer/vendor/bin",
		home() .. "/.config/composer/vendor/bin",
		"/usr/local/opt/php@8.4/bin",
		"/usr/local/opt/php/bin",
		"/usr/local/bin",
		"/usr/bin",
	}
end

function M.java_runtime_candidates()
	local user_home = home()
	local prefix = M.homebrew_prefix()

	return {
		{
			name = "JavaSE-21",
			default = true,
			paths = {
				user_home .. "/.local/share/mise/installs/java/temurin-21",
				user_home .. "/.local/share/mise/installs/java/21",
				prefix .. "/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
				"/Library/Java/JavaVirtualMachines/*21*.jdk/Contents/Home",
			},
		},
		{
			name = "JavaSE-27",
			paths = {
				user_home .. "/.local/share/mise/installs/java/temurin-27",
				user_home .. "/.local/share/mise/installs/java/27",
				prefix .. "/opt/openjdk@27/libexec/openjdk.jdk/Contents/Home",
				"/Library/Java/JavaVirtualMachines/*27*.jdk/Contents/Home",
			},
		},
	}
end

function M.java_runtimes()
	local runtimes = {}

	for _, candidate in ipairs(M.java_runtime_candidates()) do
		local resolved
		for _, path in ipairs(candidate.paths) do
			local matches = path:find("*", 1, true) and vim.fn.glob(path, false, true) or { path }
			for _, match in ipairs(matches) do
				if uv.fs_stat(match) then
					resolved = match
					break
				end
			end
			if resolved then
				break
			end
		end

		if resolved then
			runtimes[#runtimes + 1] = {
				name = candidate.name,
				path = resolved,
				default = candidate.default or nil,
			}
		end
	end

	return runtimes
end

function M.clang_query_drivers()
	local bin = M.homebrew_prefix() .. "/bin"
	return {
		"/usr/bin/clang",
		"/usr/bin/clang++",
		bin .. "/clang",
		bin .. "/clang++",
		bin .. "/gcc-*",
		bin .. "/g++-*",
		"/usr/local/bin/clang",
		"/usr/local/bin/clang++",
		"/usr/local/bin/gcc-*",
		"/usr/local/bin/g++-*",
	}
end

return M
