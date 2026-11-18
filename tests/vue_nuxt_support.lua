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

local vue = require("engine.lsp.vue")
local capabilities = { test_capability = true }
local on_attach = function() end
local ts_settings = {
	typescript = { preferences = { importModuleSpecifierPreference = "shortest" } },
	javascript = { preferences = { importModuleSpecifierPreference = "shortest" } },
}

vue.setup({
	capabilities = capabilities,
	on_attach = on_attach,
	ts_settings = ts_settings,
})

local ts_config = vim.lsp.config.ts_ls
assert(ts_config, "ts_ls config was not registered")
for _, filetype in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" }) do
	assert(contains(ts_config.filetypes, filetype), "ts_ls is missing the " .. filetype .. " filetype")
end
assert_equal(ts_config.capabilities, capabilities, "ts_ls capabilities changed")
assert_equal(ts_config.on_attach, on_attach, "ts_ls on_attach changed")
assert_equal(ts_config.settings, ts_settings, "ts_ls settings changed")

local plugins = ts_config.init_options and ts_config.init_options.plugins or {}
assert(#plugins == 1, "ts_ls should register exactly one Vue TypeScript plugin")
assert_equal(plugins[1].name, "@vue/typescript-plugin", "wrong Vue TypeScript plugin")
assert_equal(plugins[1].languages, { "vue" }, "Vue TypeScript plugin should only claim Vue files")
assert_equal(plugins[1].configNamespace, "typescript", "Vue plugin should use the TypeScript namespace")
assert(
	plugins[1].location:match("/mason/packages/vue%-language%-server/node_modules/@vue/language%-server$"),
	"Vue TypeScript plugin should resolve from Mason's vue-language-server package"
)

local vue_config = vim.lsp.config.vue_ls
assert(vue_config, "vue_ls config was not registered")
assert_equal(vue_config.filetypes, { "vue" }, "vue_ls should only claim Vue SFCs")
assert_equal(vue_config.capabilities, capabilities, "vue_ls capabilities changed")
assert_equal(vue_config.on_attach, on_attach, "vue_ls on_attach changed")

local nuxt_roots = vue_config.root_markers[1]
assert(type(nuxt_roots) == "table", "Nuxt root markers should be the highest-priority marker group")
for _, marker in ipairs({ "nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs", "nuxt.config.mts" }) do
	assert(contains(nuxt_roots, marker), "vue_ls is missing Nuxt root marker " .. marker)
end

-- The rest of this test exercises buffer behavior, not server processes.
-- Avoid spawning Mason binaries from the deliberately minimal test runtime.
vim.lsp.enable({ "ts_ls", "vue_ls" }, false)

vim.cmd("filetype plugin on")
local vue_file = vim.fn.tempname() .. ".vue"
vim.cmd.edit(vim.fn.fnameescape(vue_file))

assert_equal(vim.bo.filetype, "vue", ".vue files should use the Vue filetype")
assert(vim.bo.expandtab, "Vue buffers should indent with spaces")
assert_equal(vim.bo.tabstop, 2, "Vue tabstop should match Prettier")
assert_equal(vim.bo.shiftwidth, 2, "Vue shiftwidth should match Prettier")
assert_equal(vim.bo.softtabstop, 2, "Vue softtabstop should match Prettier")
assert_equal(vim.bo.textwidth, 0, "Vue buffers should not hard-wrap code")
assert_equal(vim.wo.foldmethod, "indent", "Vue SFCs should use indent folds")
assert_equal(vim.wo.foldlevel, 99, "Vue SFC folds should start open")

local suffixes = vim.split(vim.bo.suffixesadd, ",", { plain = true, trimempty = true })
for _, suffix in ipairs({ ".vue", ".ts", ".tsx", ".js", ".jsx", ".json" }) do
	assert(contains(suffixes, suffix), "Vue gf support is missing suffix " .. suffix)
end

local conform_spec = dofile(vim.fn.getcwd() .. "/lua/engine/plugins/conform.lua")
local save_format_opts = conform_spec.opts.format_on_save(vim.api.nvim_get_current_buf())
assert_equal(save_format_opts.lsp_format, "never", "Vue save formatting must never fall back to an LSP")

local format_call = nil
package.loaded.conform = {
	setup = function() end,
	format = function(opts)
		format_call = opts
	end,
	list_formatters = function()
		return {}
	end,
}
conform_spec.config(nil, conform_spec.opts)
vim.cmd("Format")
assert(format_call, ":Format did not invoke Conform")
assert_equal(format_call.lsp_format, "never", ":Format must never use an LSP formatter for Vue")

vim.bo.filetype = "typescript"
local typescript_save_opts = conform_spec.opts.format_on_save(vim.api.nvim_get_current_buf())
assert_equal(typescript_save_opts.lsp_format, "fallback", "non-Vue formatting fallback behavior changed")

print("Vue/Nuxt LSP configuration: ok")
print("Vue buffer defaults: ok")
print("Vue formatter ownership: ok")
