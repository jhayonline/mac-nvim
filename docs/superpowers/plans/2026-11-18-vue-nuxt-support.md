# Modern Vue and Nuxt Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class Vue 3.5.45, Nuxt 4.6.4, and TypeScript editing support without regressing the existing frontend stack.

**Architecture:** Extend the current native `ts_ls` setup with Vue's official TypeScript plugin, run `vue_ls` beside it for SFC template/style intelligence, and reuse the existing ESLint, Tailwind, Emmet, Prettier, completion, and autotag integrations. Add only the missing Vue parser, filetype defaults, and Nuxt-specific documentation.

**Tech Stack:** Neovim 0.12 native LSP, nvim-lspconfig, Mason, Vue Language Tools, TypeScript Language Server, nvim-treesitter, conform.nvim, Vim ftplugins

**Spec:** `docs/superpowers/specs/2026-11-18-vue-nuxt-support-design.md`

## Global Constraints

- Target Vue 3.5.45 and Nuxt 4.6.4.
- Keep `ts_ls`; do not migrate the TypeScript stack to `vtsls`.
- Use `vue_ls`, not the retired `volar` server name.
- Preserve all pre-existing uncommitted changes and do not commit without an explicit user request.
- Do not add Vue 2 or Nuxt 2 compatibility paths.

## Review Focus

- A `.vue` buffer must attach both `ts_ls` and `vue_ls`, with the TypeScript plugin available before either needs to forward Vue requests.
- A Nuxt app nested in a monorepo must root at its `nuxt.config.*`, not an unrelated outer package.
- Existing `.ts`, `.tsx`, `.js`, and `.jsx` behavior must retain its settings and filetypes.
- A missing-yet-to-be-installed Mason Vue package must not make Neovim startup fail.
- Vue formatting must stay owned by project-local Prettier and must not race ESLint or the language server.

---

### Task 1: Vue and TypeScript language intelligence

**Files:**
- Create: `lua/engine/lsp/vue.lua`
- Create: `tests/vue_nuxt_support.lua`
- Modify: `lua/engine/plugins/lsp/lspconfig.lua`
- Modify: `lua/engine/plugins/lsp/mason.lua`

**Interfaces:**
- Consumes: the existing `ts_ls` capabilities, on-attach handler, settings, and native `vim.lsp.config` API.
- Produces: `require("engine.lsp.vue").setup(opts)`, registered `ts_ls` and `vue_ls` configs, and automatic Mason installation of `vue_ls`.

- [ ] **Step 1: Write the failing headless LSP configuration test**

Create a test that loads the real helper into native Neovim LSP config and asserts that `ts_ls` retains JavaScript/TypeScript filetypes, adds `vue`, loads `@vue/typescript-plugin` from Mason's Vue package, and that `vue_ls` has Nuxt-prioritized root markers.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --clean --headless -u NONE -l tests/vue_nuxt_support.lua`

Expected: FAIL because `engine.plugins.lsp.vue` does not exist.

- [ ] **Step 3: Implement the Vue LSP helper and wire it into the existing setup**

Implement `setup(opts)` with the official Vue TypeScript plugin shape, Mason v2 path, Vue-inclusive TypeScript filetypes, and `vue_ls` Nuxt/Vite/package roots. Replace the inline `ts_ls` registration with this helper and add `vue_ls` to Mason's `ensure_installed` list.

- [ ] **Step 4: Run the test to verify it passes**

Run the command from Step 2.

Expected: PASS with a zero exit status.

- [ ] **Step 5: Run Lua syntax checks**

Run: `luac -p lua/engine/lsp/vue.lua lua/engine/plugins/lsp/lspconfig.lua lua/engine/plugins/lsp/mason.lua tests/vue_nuxt_support.lua`

Expected: exit 0 with no output.

### Task 2: Vue editing ergonomics and Nuxt documentation

**Files:**
- Create: `ftplugin/vue.vim`
- Modify: `lua/engine/plugins/treesitter.lua`
- Modify: `lua/engine/plugins/conform.lua`
- Modify: `doc/frontend.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: the existing Prettier, Treesitter, autotag, Tailwind, ESLint, Emmet, snippets, and TypeScript conventions.
- Produces: Vue SFC parsing and buffer-local editing defaults plus setup/troubleshooting instructions for Nuxt-generated types.

- [ ] **Step 1: Write a failing headless Vue filetype test**

Extend `tests/vue_nuxt_support.lua` to open a temporary `.vue` file with the repository on `runtimepath` and assert `filetype=vue`, two-space expansion, no hard text width, indent folding, and Vue/TypeScript import suffixes.

- [ ] **Step 2: Run the test to verify it fails**

Run the Task 1 headless test command.

Expected: FAIL because the Vue ftplugin does not yet apply the required local options.

- [ ] **Step 3: Add Vue parser and buffer defaults; clarify formatting ownership**

Add `vue` to Treesitter's ensured parsers, create `ftplugin/vue.vim`, and update the Conform section label/comments to describe the shared Vue/React TypeScript stack while leaving Prettier as the sole Vue formatter.

- [ ] **Step 4: Update frontend documentation and README**

Document the two Vue clients, Nuxt `postinstall: nuxt prepare`, `nuxt typecheck`, Vue project requirements, available shared tooling, and troubleshooting checks. Rename the README stack entry to cover Vue/Nuxt and React.

- [ ] **Step 5: Run focused and full verification**

Run the Task 1 headless test, Lua syntax checks, `vim -Nu NONE -n -es -S /dev/null` against the ftplugin, `git diff --check`, and a full headless Neovim startup with a temporary writable state directory.

Expected: all commands exit 0; the test prints its passing assertions; no startup errors refer to the edited Vue/Nuxt configuration.
