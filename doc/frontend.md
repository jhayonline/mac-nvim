# React + TypeScript + Tailwind

Five language servers cooperate on a `.tsx` buffer, prettier formats on save
with Tailwind classes sorted, and treesitter finally highlights JSX properly.

---

## What runs on a `.tsx` file

| Server | Job |
| --- | --- |
| `ts_ls` | Types, completion, auto-imports, rename, inlay hints |
| `tailwindcss` | Class completion (~23k classes), colour swatches, conflict warnings |
| `eslint` | Lint diagnostics, `:EslintFixAll` |
| `emmet_ls` | `div.flex.gap-2` → markup expansion |
| `graphql` | `gql` tagged templates — see *Trimming* below if you don't use GraphQL |

Plus treesitter for syntax, prettier for formatting and `nvim-ts-autotag` for
JSX tag auto-closing.

### The Tailwind server was installed but never configured

`tailwindcss-language-server` was already in your Mason list, but nothing in
`lspconfig.lua` ever called `vim.lsp.config`/`vim.lsp.enable` for it — so it was
running on bare defaults with no `.tsx` in its filetype list. It now has:

- **Filetypes** covering the whole JS/TS family, CSS, Svelte, Vue and Blade.
- **Root markers** for both Tailwind v3 (`tailwind.config.{js,ts,cjs,mjs}`) and
  v4, which has no JS config at all — it configures itself from CSS
  (`@import "tailwindcss"`), so `package.json` is also a root marker.
- **`classRegex`** for the patterns a real codebase uses: `cva()`, `clsx()`,
  `cn()`, `cx()` and `tw` tagged templates. Without these you get completion
  inside `className="…"` and nowhere else.
- **`includeLanguages`** mapping Blade → HTML so Laravel templates get the same
  completions.

> The server needs `node_modules/tailwindcss` to exist. In a fresh Laravel app
> that means running `npm install` first — Composer doesn't do it for you.

### TypeScript

`ts_ls` gained inlay hints and import preferences. The hint settings have to be
spelled out twice because the server keys them separately under `typescript`
and `javascript`.

Worth knowing:

- `importModuleSpecifierPreference = "shortest"` makes auto-imports respect the
  `paths` in `tsconfig.json`, so you get `@/components/Button` instead of
  `../../components/Button`.
- `updateImportsOnFileMove` rewrites imports when you rename a file through the
  LSP file-operations integration.
- `completeFunctionCalls` fills in parameters when you accept a function
  completion.

---

## Formatting

prettier runs on save for `.ts`, `.tsx`, `.js`, `.jsx`, `.css`, `.scss`,
`.html`, `.json`, `.yaml`, `.md` and `.graphql`.

conform resolves `node_modules/.bin/prettier` first and only falls back to the
global install, so your output always matches what CI runs. A global prettier
3.9.6 is installed as that fallback.

### Sort your Tailwind classes

If the project has `prettier-plugin-tailwindcss` in `devDependencies` and lists
it in `.prettierrc`, prettier also sorts Tailwind classes into canonical order
on every save:

```jsonc
// .prettierrc
{ "plugins": ["prettier-plugin-tailwindcss"] }
```

```
p-4 flex text-sm gap-2 items-center   ->   flex items-center gap-2 p-4 text-sm
```

This is worth adding to every Tailwind project — it ends class-order diff noise
permanently. Add it with `npm i -D prettier-plugin-tailwindcss`.

### Escape hatches

| Command | Effect |
| --- | --- |
| `:Format` | Format now (works on a visual range too) |
| `:FormatToggle` | Toggle format-on-save globally |
| `:FormatToggle!` | Toggle it for the current buffer only |
| `:FormatInfo` | Show which formatters apply here and whether they were found |

`:FormatInfo` is the first thing to run when a file doesn't format.

---

## ESLint

The `eslint` server only attaches when the project actually has an ESLint
config, so scratch files stay quiet. It's configured for flat config
(`eslint.config.js`), the default since ESLint 9.

`format = false` is set deliberately: prettier owns formatting, ESLint owns
correctness. Running both as formatters is how you get fights on save.

Run `:EslintFixAll` to apply every auto-fixable rule in the buffer.

---

## Indentation

`ftplugin/{typescript,typescriptreact,javascript,javascriptreact}.vim` and the
CSS family set **2 spaces**, overriding the global 8-wide hard tabs from
`options.lua`. That is what prettier emits; anything else means the formatter
rewrites every line you touch and your diffs fill with whitespace.

They also set `foldmethod=indent` (the global `#pragma region` foldmarker never
matches a JSX file) and `suffixesadd` so `gf` follows an import to
`./Button.tsx`.

---

## Treesitter

This was the blocking issue, and it's now fixed. `treesitter.lua` pinned
`branch = "master"` but called `require("nvim-treesitter").setup{…}` — the
wrong entry point on that branch, which silently discarded `highlight`,
`autotag` and `ensure_installed`. The result: **no parser had ever been
installed and highlighting was off for every language**.

The fix was one line (`require("nvim-treesitter.configs")`), and 31 parsers are
now compiled, including `tsx`, `typescript`, `jsdoc`, `regex`, `scss`, `rust`,
`php`, `phpdoc`, `blade` and `c_sharp`.

Two things you get back:

- Real JSX/TSX highlighting — components, props and attributes are distinct.
- `nvim-ts-autotag` works, so typing `<div>` closes it and renaming a tag
  renames its pair. It reads its config from the treesitter setup table, which
  is why it was inert too.

Reinstall or add parsers with `:TSInstall <lang>`; update with `:TSUpdate`.

---

## Trimming

`graphql-language-service-cli` attaches to every `.tsx` buffer because its
default filetypes include `typescriptreact` (for `gql` tagged templates). If
you don't write GraphQL, that's a wasted client per buffer. Remove it from
`ensure_installed` in `lua/engine/plugins/lsp/mason.lua`, then:

```vim
:MasonUninstall graphql-language-service-cli
```

Mason's `automatic_enable` starts every *installed* server, so uninstalling is
what actually stops it — removing it from `ensure_installed` alone won't.

---

## Where things live

```
lua/engine/plugins/lsp/lspconfig.lua   ts_ls, tailwindcss, eslint, emmet_ls
lua/engine/plugins/conform.lua         prettier wiring, :Format, :FormatToggle
lua/engine/plugins/treesitter.lua      parser list and the fixed setup call
ftplugin/typescript*.vim               2-space indent, folding, gf
ftplugin/javascript*.vim               same
ftplugin/{css,scss,less}.vim           same
```

---

## Troubleshooting

**No Tailwind completions.** The server needs `node_modules/tailwindcss` —
run `npm install`. Check it attached with
`:lua =vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({bufnr=0}))`.

**Completions only inside `className="…"`.** You're using a helper the
`classRegex` list doesn't cover. Add your pattern to the `experimental.classRegex`
table in `lspconfig.lua`.

**Auto-imports use long relative paths.** Your `tsconfig.json` needs `baseUrl`
and `paths`; `ts_ls` can only shorten what the config declares.

**prettier isn't running.** `:FormatInfo`. If it says UNAVAILABLE, the project
has no local prettier and the global one isn't on `PATH`.

**ESLint isn't attaching.** It requires an ESLint config file in the project
root. With legacy `.eslintrc.*`, set `useFlatConfig = false` in the `eslint`
block.
