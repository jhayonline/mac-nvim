# Vue 3 / Nuxt 4 + React + TypeScript + Tailwind

Vue 3.5 and Nuxt 4 single-file components get the official Vue language tools
alongside TypeScript. React/TSX keeps the same TypeScript stack, and both sides
share Prettier, ESLint, Tailwind, Emmet, snippets, Treesitter and tag editing.

---

## What runs on a `.vue` file

| Server | Job |
| --- | --- |
| `vue_ls` | SFC structure, templates, styles, component completion and semantic tokens |
| `ts_ls` | TypeScript in `<script>`/templates, auto-imports, navigation, rename and inlay hints |
| `tailwindcss` | Class completion (~23k classes), colour swatches, conflict warnings |
| `eslint` | Lint diagnostics, `:EslintFixAll` |
| `emmet_ls` | `div.flex.gap-2` → template markup expansion |

Plus treesitter for syntax, prettier for formatting and `nvim-ts-autotag` for
closing and renaming template tags. On `.tsx`, `ts_ls`, Tailwind, ESLint,
Emmet and GraphQL cooperate as before.

### Vue Language Tools hybrid mode

Modern Vue Language Tools splits a Vue SFC between two clients. `vue_ls`
handles the SFC/template/style side; `ts_ls` loads `@vue/typescript-plugin`
from Mason's `vue-language-server` package and handles the TypeScript virtual
files. Mason installs `vue_ls` automatically on startup.

Open a `.vue` file and run `:LspInfo`. Both `vue_ls` and `ts_ls` must be
attached. Seeing only `vue_ls` means templates may complete but script and
cross-file types will be incomplete.

### Nuxt 4 generated types

Nuxt owns aliases such as `#imports`, `#build` and `~/…` through generated
TypeScript project references. Generate them after installing dependencies:

```sh
npm install
npx nuxt prepare
```

Keep the standard postinstall script so a fresh clone is editor-ready:

```json
{
  "scripts": {
    "postinstall": "nuxt prepare"
  }
}
```

Nuxt 4 generates separate `.nuxt/tsconfig.{app,node,server,shared}.json`
contexts. Do not copy their aliases into the Neovim config or overwrite the
generated settings in a hand-maintained `tsconfig.json`; extend TypeScript
through `nuxt.config.ts` when the project needs customization.

Nuxt does not type-check during `dev` or `build` by default. Install
`typescript` and `vue-tsc` in the project, then use the framework check:

```sh
npm install --save-dev typescript vue-tsc
npx nuxt typecheck
```

For a plain Vue 3 project, use its normal `vue-tsc --noEmit` script instead.

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

prettier runs on save for `.vue`, `.ts`, `.tsx`, `.js`, `.jsx`, `.css`, `.scss`,
`.html`, `.json`, `.yaml`, `.md` and `.graphql`.

conform resolves `node_modules/.bin/prettier` first and only falls back to a
global install, so a project-pinned formatter wins. Prefer a project-local
Prettier; install a global fallback only if you want formatting for loose files.

Vue never falls back to LSP formatting: both `vue_ls` and `ts_ls` attach to an
SFC, so choosing an LSP formatter would be ambiguous and could differ from CI.
If Prettier is unavailable, `:FormatInfo` reports that and leaves the file
unchanged.

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

`ftplugin/vue.vim`, the TypeScript/JavaScript ftplugins and the CSS family set
**2 spaces**, overriding the global 8-wide hard tabs from `options.lua`. That
is what prettier emits; anything else means the formatter rewrites every line
you touch and your diffs fill with whitespace.

They also set `foldmethod=indent` (the global `#pragma region` foldmarker never
matches an SFC or JSX file) and `suffixesadd` so `gf` follows imports such as
`./Button.vue` and `./Button.tsx`.

---

## Treesitter

This was the blocking issue, and it's now fixed. `treesitter.lua` pinned
`branch = "master"` but called `require("nvim-treesitter").setup{…}` — the
wrong entry point on that branch, which silently discarded `highlight`,
`autotag` and `ensure_installed`. The result: **no parser had ever been
installed and highlighting was off for every language**.

The fix was one line (`require("nvim-treesitter.configs")`). The ensured web
parsers now include `vue`, `tsx`, `typescript`, `javascript`, `jsdoc`, `regex`,
`html`, `css` and `scss`.

Two things you get back:

- Real Vue SFC and JSX/TSX highlighting — components, props, directives and
  attributes are distinct.
- `nvim-ts-autotag` works in Vue templates and JSX, so typing `<div>` closes it
  and renaming a tag renames its pair.

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
lua/engine/lsp/vue.lua                 vue_ls + Vue-aware ts_ls integration
lua/engine/plugins/lsp/lspconfig.lua   TypeScript settings, Tailwind, ESLint, Emmet
lua/engine/plugins/conform.lua         prettier wiring, :Format, :FormatToggle
lua/engine/plugins/treesitter.lua      parser list and the fixed setup call
ftplugin/vue.vim                       Vue SFC indentation, folding, gf
ftplugin/typescript*.vim               2-space indent, folding, gf
ftplugin/javascript*.vim               same
ftplugin/{css,scss,less}.vim           same
```

---

## Troubleshooting

**Vue templates work but TypeScript does not.** Run `:LspInfo` in the `.vue`
file. Both `vue_ls` and `ts_ls` must be attached. In `:Mason`, verify that
`vue-language-server` and `typescript-language-server` are installed, then
restart the buffer's clients with `<leader>rs`.

**Nuxt auto-imports or aliases are unknown.** Run `npm install` and
`npx nuxt prepare`, then restart the LSP. The `.nuxt` directory is generated
state, but its project references are required for editor types.

**A Vue project has editor types but CI does not.** The editor is not a
replacement for type-checking. Run `npx nuxt typecheck` in Nuxt or
`npx vue-tsc --noEmit` in plain Vue and add that command to CI.

**No Tailwind completions.** The server needs `node_modules/tailwindcss` —
run `npm install`. Check it attached with
`:lua =vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({bufnr=0}))`.

**Completions only inside `className="…"`.** You're using a helper the
`classRegex` list doesn't cover. Add your pattern to the `experimental.classRegex`
table in `lspconfig.lua`.

**Auto-imports use long relative paths.** In Nuxt, regenerate `.nuxt` rather
than hand-writing framework aliases. In other TypeScript projects, the
`tsconfig.json` needs the relevant `paths`; `ts_ls` can only shorten what the
project declares.

**prettier isn't running.** `:FormatInfo`. If it says UNAVAILABLE, the project
has no local prettier and the global one isn't on `PATH`.

**ESLint isn't attaching.** It requires an ESLint config file in the project
root. With legacy `.eslintrc.*`, set `useFlatConfig = false` in the `eslint`
block.
