# Modern Vue and Nuxt Support Design

## Intent

Make this Neovim configuration a first-class editor for Vue 3.5.45, Nuxt
4.6.4, and TypeScript while preserving the existing React/TypeScript stack.
The result should provide correct SFC types, template intelligence, project
navigation, completion, diagnostics, formatting, linting, Tailwind support,
Emmet, snippets, tag editing, and syntax highlighting.

## Goals

- Run the official Vue language server on `.vue` files.
- Give `ts_ls` TypeScript awareness inside Vue SFCs through the official Vue
  TypeScript plugin.
- Prefer Nuxt application roots in monorepos and rely on Nuxt's generated
  `.nuxt/tsconfig.json` for framework types and aliases.
- Install the required language server and Treesitter parser automatically.
- Match the existing two-space Prettier-based web editing conventions.
- Document project-side prerequisites and useful verification commands.

## Non-goals

- Vue 2 or Nuxt 2 compatibility.
- Replacing `ts_ls` with `vtsls` or another TypeScript client.
- Installing project dependencies or changing a Vue/Nuxt application.
- Inventing Nuxt aliases in Neovim; Nuxt owns them through generated types.

## Constraints

- Target Vue 3.5.45 and Nuxt 4.6.4.
- Keep the current Neovim 0.12 native `vim.lsp.config` API.
- Preserve all pre-existing uncommitted work and avoid unrelated cleanup.
- Prefer project-local TypeScript, ESLint, and Prettier behavior where the
  existing tooling already supports it.

## Approaches

1. **`vue_ls` plus the Vue plugin in the existing `ts_ls` (selected).** This
   is the official Vue Language Tools hybrid-mode setup. It retains the
   current TypeScript configuration and adds complete SFC support with the
   smallest change.
2. **Replace `ts_ls` with `vtsls`.** This also supports the Vue plugin, but it
   would replace a working TypeScript stack and broaden the migration without
   improving the requested Vue/Nuxt outcome.
3. **Run `vue_ls` alone.** This handles template and style regions, but modern
   Vue Language Tools delegates TypeScript work to a TypeScript server, so
   script blocks and cross-file types would be incomplete.

## Design

Add a focused Vue LSP helper outside Lazy's auto-imported plugin-spec namespace
that extends the existing `ts_ls` configuration
with the official `@vue/typescript-plugin` path from Mason, adds `vue` to its
filetypes, and configures `vue_ls` with Nuxt/Vite/package root markers. Keep
ESLint, Tailwind, Emmet, and Prettier on the existing shared frontend path.

Add the Vue Treesitter parser and a `ftplugin/vue.vim` matching the existing
TypeScript two-space, no-text-width, import-friendly buffer conventions.
Update the frontend guide and README to describe the combined Vue/Nuxt and
React/TypeScript stack. The guide will make `nuxt prepare` explicit because
that command generates the framework types and aliases the language servers
consume.

## Verification

- A headless Neovim test inspects the real native LSP configurations and
  confirms both servers, the Vue TypeScript plugin, filetypes, and Nuxt roots.
- Headless filetype tests confirm `.vue` detection and local buffer options.
- Lua and Vimscript syntax checks cover every edited configuration file.
- A normal headless startup confirms the full configuration still loads.
