# Apple Silicon Neovim Config Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port every functional change in the active Arch Neovim config to `mac-nvim` and adapt the result for an M5 Apple Silicon Mac.

**Architecture:** Treat commit `5e875fe` as the exact shared base, bring the active config's runtime changes across by feature group, and isolate Apple Silicon path discovery in a small `engine.core.macos` helper. Preserve the source feature behavior while replacing Arch/Intel assumptions with `/opt/homebrew`, arm64, macOS JDK, Keychain, and Apple Clang behavior.

**Tech Stack:** Neovim 0.12 Lua/Vimscript, lazy.nvim, native `vim.lsp.config`, Mason, nvim-jdtls, nvim-dap, Treesitter, Conform, headless Neovim tests

**Spec:** `docs/superpowers/specs/2026-11-18-apple-silicon-config-sync-design.md`

## Global Constraints

- The destination is macOS on Apple Silicon (M5/arm64), with Homebrew under `/opt/homebrew`.
- The exact shared merge base is commit `5e875fe49a8673de9fbb91b8875028d03a164400` in both checkouts.
- `/home/jhayonline/.config/nvim` is a read-only source; never edit, stage, clean, or commit it.
- Do not copy `nvim.log`, `.git`, `.superpowers`, caches, or other machine output.
- Preserve destination-only `.agents`, `.codex`, and the approved design/plan documents.
- Keep Neovim 0.12's native `vim.lsp.config` API and the selected `ts_ls` plus `vue_ls` Vue architecture.
- Runtime files and reusable test commands must not hard-code `/home/jhayonline`.
- Do not install packages, update plugins, or contact package registries during implementation.
- Do not commit unless the user explicitly requests a commit.

## Review Focus

- `HOMEBREW_PREFIX` unset or different: default to `/opt/homebrew` while respecting an explicit prefix and retaining `/usr/local` only as a compatibility fallback.
- Missing optional SDK/JDK/tool directories: startup must remain successful and only omit unavailable runtimes or tools.
- A Nuxt app nested in a monorepo: `nuxt.config.*` must win over outer `package.json`/`.git` roots and both `ts_ls` and `vue_ls` must attach to Vue files.
- Mason packages not installed yet on the new Mac: configuration modules must load without dereferencing missing package contents during startup.
- Linux-host verification of macOS logic: tests must inject/probe path decisions without requiring `/opt/homebrew`, macOS binaries, or an arm64 host to exist.

---

### Task 1: Apple Silicon path discovery

**Files:**
- Create: `lua/engine/core/macos.lua`
- Create: `tests/apple_silicon_support.lua`

**Interfaces:**
- Consumes: `vim.env.HOMEBREW_PREFIX`, `vim.env.HOME`, `vim.uv.fs_stat`, and `vim.fn.glob`.
- Produces: `homebrew_prefix() -> string`, `dotnet_roots() -> string[]`, `php_bin_dirs() -> string[]`, `java_runtime_candidates() -> table[]`, `java_runtimes() -> table[]`, and `clang_query_drivers() -> string[]`.

- [ ] **Step 1: Write the failing Apple Silicon discovery test**

Create `tests/apple_silicon_support.lua` with assertions that:

- the default Homebrew prefix is `/opt/homebrew` when no override is supplied;
- an explicit prefix is honored;
- .NET candidates include `~/.dotnet` and `/opt/homebrew/opt/dotnet/libexec`;
- PHP candidates prefer `/opt/homebrew/opt/php@8.4/bin`;
- JDK 21 candidates include mise, Homebrew's JDK bundle, and the standard `/Library/Java/JavaVirtualMachines` bundle pattern;
- query drivers include Apple Clang and Homebrew GCC/Clang paths;
- `java_runtimes()` filters missing paths without throwing.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --clean --headless -u NONE -l tests/apple_silicon_support.lua`

Expected: FAIL because `engine.core.macos` does not exist.

- [ ] **Step 3: Implement the focused macOS helper**

Implement the interfaces above. Read the environment at call time so the test can inject a Homebrew prefix. Keep filesystem filtering in `java_runtimes()` and return candidate metadata separately so discovery decisions remain testable on Linux.

- [ ] **Step 4: Run the focused test**

Run: `nvim --clean --headless -u NONE -l tests/apple_silicon_support.lua`

Expected: PASS and print `Apple Silicon path discovery: ok`.

- [ ] **Step 5: Check Lua syntax**

Run: `luac -p lua/engine/core/macos.lua tests/apple_silicon_support.lua`

Expected: exit 0 with no output.

### Task 2: Shared plugins, Vue/Nuxt, and language-server surface

**Files:**
- Create: `lua/engine/lsp/vue.lua`
- Create: `ftplugin/vue.vim`
- Create: `tests/vue_nuxt_support.lua`
- Modify: `lazy-lock.json`
- Modify: `lua/engine/lazy.lua`
- Modify: `lua/engine/core/options.lua`
- Modify: `lua/engine/plugins/conform.lua`
- Modify: `lua/engine/plugins/dap.lua`
- Modify: `lua/engine/plugins/lsp/lspconfig.lua`
- Modify: `lua/engine/plugins/lsp/mason.lua`
- Modify: `lua/engine/plugins/rust.lua`
- Modify: `lua/engine/plugins/smear_cursor.lua`
- Modify: `lua/engine/plugins/treesitter.lua`

**Interfaces:**
- Consumes: `engine.core.macos.clang_query_drivers()`, existing completion/on-attach settings, Mason's portable `stdpath("data")`, and the active source files at the same relative paths.
- Produces: Vue-aware `ts_ls`, `vue_ls`, the expanded Mason/Treesitter server and parser set, updated DAP/formatting behavior, and a lockfile containing `nvim-jdtls`.

- [ ] **Step 1: Port the existing Vue/Nuxt regression test and verify the destination fails it**

Copy the source test behavior into `tests/vue_nuxt_support.lua` without its hard-coded Linux runtimepath. It must assert both Vue clients, the Mason Vue TypeScript plugin path, Nuxt-prioritized roots, Vue buffer defaults, and Prettier-only Vue formatting.

Run: `nvim --clean --headless -u NONE -l tests/vue_nuxt_support.lua`

Expected: FAIL because `engine.lsp.vue` does not exist.

- [ ] **Step 2: Port Vue LSP and filetype support**

Create `lua/engine/lsp/vue.lua` and `ftplugin/vue.vim` from the active config. Preserve `ts_ls`'s existing JavaScript/TypeScript settings and add only the official `@vue/typescript-plugin` plus the `vue` filetype; configure `vue_ls` with Nuxt markers first.

- [ ] **Step 3: Port the shared source-side plugin changes**

Bring over the current source versions of the listed Lazy, options, Conform, DAP, Mason, Rust, cursor, and Treesitter files. In `lspconfig.lua`, replace the source's `/usr/bin/c++,/usr/bin/g++` query-driver literal with `table.concat(require("engine.core.macos").clang_query_drivers(), ",")`. In `lazy.lua`, retain disabled rocks but rewrite the Arch-specific rationale as a platform-neutral statement that no configured plugin needs runtime rocks.

- [ ] **Step 4: Port the current lockfile**

Replace `lazy-lock.json` with the active config's lockfile, including `nvim-jdtls` and the current plugin revisions. Do not run `:Lazy update` or otherwise change pins.

- [ ] **Step 5: Run focused regression and syntax checks**

Run:

```sh
nvim --clean --headless -u NONE -l tests/vue_nuxt_support.lua
nvim --clean --headless -u NONE -l tests/apple_silicon_support.lua
luac -p lua/engine/lsp/vue.lua lua/engine/core/options.lua lua/engine/plugins/conform.lua lua/engine/plugins/dap.lua lua/engine/plugins/lsp/lspconfig.lua lua/engine/plugins/lsp/mason.lua lua/engine/plugins/rust.lua lua/engine/plugins/smear_cursor.lua lua/engine/plugins/treesitter.lua tests/vue_nuxt_support.lua
```

Expected: both tests pass; Lua parsing exits 0.

### Task 3: Java, graphics, skeletons, and platform-neutral runtime modules

**Files:**
- Create: `lua/engine/core/graphics.lua`
- Create: `lua/engine/plugins/java.lua`
- Create: `ftplugin/java.lua`
- Create: `lua/engine/tools/skeleton_java.lua`
- Create: `tests/ported_features.lua`
- Modify: `lua/engine/core/init.lua`
- Modify: `lua/engine/tools/init.lua`
- Modify: `lua/engine/tools/skeleton.lua`
- Modify: `ftplugin/holyc.vim`
- Modify: `syntax/holyc.vim`

**Interfaces:**
- Consumes: `engine.core.macos.java_runtimes()`, Mason jdtls/debug/test bundle locations, the existing `:Skel` dispatcher, and native filetype/Treesitter APIs.
- Produces: Java LSP/debug/test support, Java skeletons, shader filetypes and `:ShaderCheck`, M5-aware HolyC include/constants, and feature-parity assertions.

- [ ] **Step 1: Write a failing ported-features test**

Create `tests/ported_features.lua` that inspects the real specs/modules and asserts:

- the Java plugin declares `nvim-jdtls`;
- Java skeleton kinds can be required and include representative class/interface/test templates;
- graphics setup registers HLSL/GLSL extensions and the `ShaderCheck` command;
- the Mason and Treesitter specs include Java, GLSL/WGSL, CMake, Odin, Razor, and Vue entries;
- Java runtime configuration is obtained from `engine.core.macos`, not hard-coded mise-only paths.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim --clean --headless -u NONE -l tests/ported_features.lua`

Expected: FAIL because the destination lacks the Java and graphics modules.

- [ ] **Step 3: Port the Java and graphics implementations**

Bring over the source files at the listed paths. In `ftplugin/java.lua`, replace the source's inline mise-only runtime table with `require("engine.core.macos").java_runtimes()` while preserving jdtls workspaces, bundle filtering, keymaps, DAP, and settings.

- [ ] **Step 4: Wire setup and skeleton dispatch**

Port `core/init.lua`, `tools/init.lua`, and `tools/skeleton.lua` so graphics setup and Java skeleton selection/completion are active. Update HolyC's include search to include `/opt/homebrew/include`, and recognize `__aarch64__`/`__arm64__` without removing syntax recognition for existing constants.

- [ ] **Step 5: Run feature and syntax checks**

Run:

```sh
nvim --clean --headless -u NONE -l tests/ported_features.lua
luac -p lua/engine/core/graphics.lua lua/engine/plugins/java.lua ftplugin/java.lua lua/engine/tools/skeleton_java.lua lua/engine/core/init.lua lua/engine/tools/init.lua lua/engine/tools/skeleton.lua tests/ported_features.lua
vim -Nu NONE -n -es +'source ftplugin/holyc.vim' +'source syntax/holyc.vim' +qa
```

Expected: test passes; all parsers/source checks exit 0.

### Task 4: .NET, Razor, PHP, and Apple Silicon tool bootstrap

**Files:**
- Modify: `after/lsp/roslyn.lua`
- Modify: `lua/engine/core/dotnet.lua`
- Modify: `lua/engine/core/php.lua`
- Modify: `lua/engine/plugins/lsp/roslyn.lua`
- Extend: `tests/apple_silicon_support.lua`
- Extend: `tests/ported_features.lua`

**Interfaces:**
- Consumes: `engine.core.macos.dotnet_roots()`, `engine.core.macos.php_bin_dirs()`, the existing Roslyn plugin, and Task 2's DAP/Conform setup.
- Produces: the active source's complete ASP.NET MVC/Razor and PHP workflows with macOS-native path and certificate behavior.

- [ ] **Step 1: Add failing integration assertions**

Extend the tests to assert that:

- .NET bootstrap consumes the macOS helper and does not force Linux `/etc/ssl/certs` or NSS behavior;
- PHP bootstrap consumes the helper and prefers `/opt/homebrew`;
- Roslyn background-analysis comments/settings no longer encode the old Haswell hardware;
- the source's MVC commands and Razor DAP configuration are present.

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```sh
nvim --clean --headless -u NONE -l tests/apple_silicon_support.lua
nvim --clean --headless -u NONE -l tests/ported_features.lua
```

Expected: FAIL on missing helper integration and missing expanded .NET behavior.

- [ ] **Step 3: Port the active .NET and Roslyn behavior**

Bring over the active `dotnet.lua` and `after/lsp/roslyn.lua`. Replace inline SDK candidate lists with `macos.dotnet_roots()`. Remove the Linux `SSL_CERT_DIR`/NSS bridge because `dotnet dev-certs https --trust` uses macOS Keychain. Preserve MVC scaffolding, Razor navigation, project discovery, quickfix/terminal commands, CSharpier, and Roslyn settings.

- [ ] **Step 4: Port PHP and remove old CPU assumptions**

Bring over the active `php.lua`, switch its PATH candidate list to `macos.php_bin_dirs()`, and update Roslyn plugin comments so performance choices are described without the former four-core Haswell assumption.

- [ ] **Step 5: Run focused tests and syntax checks**

Run:

```sh
nvim --clean --headless -u NONE -l tests/apple_silicon_support.lua
nvim --clean --headless -u NONE -l tests/ported_features.lua
luac -p after/lsp/roslyn.lua lua/engine/core/dotnet.lua lua/engine/core/php.lua lua/engine/plugins/lsp/roslyn.lua
```

Expected: both tests pass; Lua parsing exits 0.

### Task 5: M5 documentation and complete source-change accounting

**Files:**
- Create: `doc/CsToolUse.md`
- Modify: `README.md`
- Modify: `doc/csharp.md`
- Modify: `doc/frontend.md`
- Modify: `doc/php.md`
- Modify: `doc/rust.md`
- Create: `docs/superpowers/specs/2026-11-18-vue-nuxt-support-design.md`
- Create: `docs/superpowers/plans/2026-11-18-vue-nuxt-support.md`
- Create: `docs/superpowers/plans/2026-11-02-disable-rust-analyzer.md`

**Interfaces:**
- Consumes: the active source documentation and the implemented M5 runtime behavior.
- Produces: complete Mac-facing setup/use documentation and preserved feature-history documents with portable commands.

- [ ] **Step 1: Write a failing documentation audit**

Run targeted searches over runtime/user-facing files (excluding this migration design/plan, where historical terms are intentional) for `/home/jhayonline`, `pacman`, `This machine is Arch`, `osx-x64`, `x86_64`, `4-core Haswell`, Intel-Homebrew warnings, and `/usr/local/opt` presented as the primary Apple Silicon install.

Expected: FAIL with the current Intel documentation and, after source content is ported, Arch references.

- [ ] **Step 2: Port current source documentation**

Bring over the active README, C#/MVC how-to, frontend/Vue/Nuxt guide, Rust guide, and the source's existing feature design/plan records. Replace the Vue plan's hard-coded test runtimepath with a repository-relative command.

- [ ] **Step 3: Rewrite platform instructions for M5**

Update installation tables and commands for arm64, `/opt/homebrew`, Apple Silicon .NET, macOS Keychain dev certificates, Homebrew/OpenJDK or mise JDKs, Mason Java bundles, and native debugger packages. Retain the complete new MVC/Razor and Vue/Nuxt usage material. Remove claims that tools are already installed until confirmed on the new machine.

- [ ] **Step 4: Run the documentation and inventory audit**

Run:

```sh
rg -n -g '*.lua' -g '*.vim' -g '*.md' -g '!docs/superpowers/specs/2026-11-18-apple-silicon-config-sync-design.md' -g '!docs/superpowers/plans/2026-11-18-apple-silicon-config-sync.md' '/home/jhayonline|This machine is Arch|sudo pacman|osx-x64|4-core Haswell|Homebrew has moved Intel' .
diff -qr --exclude=.git --exclude=.agents --exclude=.codex --exclude=.superpowers --exclude=nvim.log --exclude=docs /home/jhayonline/.config/nvim .
```

Expected: the search returns no matches. Every diff remaining in the inventory is either an Apple Silicon adaptation, a test added by this port, or an explicitly excluded machine/process artifact.

- [ ] **Step 5: Check Markdown and patch hygiene**

Run: `git diff --check`

Expected: exit 0 with no output.

### Task 6: Full isolated verification

**Files:**
- Verify only; fix the owning task's files if a check fails.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: evidence that the complete config loads on the current host without mutating its live Neovim state, plus an explicit on-Mac smoke-test handoff.

- [ ] **Step 1: Run every focused headless test**

Run:

```sh
nvim --clean --headless -u NONE -l tests/apple_silicon_support.lua
nvim --clean --headless -u NONE -l tests/vue_nuxt_support.lua
nvim --clean --headless -u NONE -l tests/ported_features.lua
```

Expected: all tests pass and print their success summaries.

- [ ] **Step 2: Parse every Lua and Vimscript file**

Run Lua parsing over every repository `*.lua` file using `luac -p`, then source each changed Vimscript ftplugin/syntax file in a minimal noninteractive Vim session.

Expected: all files parse/source successfully.

- [ ] **Step 3: Run an isolated full startup**

Create a temporary XDG tree with `mktemp -d`, symlink the already installed Lazy plugin and Mason directories from the current read-only data tree into that temporary data tree, and run the repository's `init.lua` headlessly with temporary data/state/cache paths.

Expected: exit 0 with no startup errors; no package downloads or writes to `~/.local/share/nvim`.

- [ ] **Step 4: Run final repository checks**

Run:

```sh
git diff --check
git status --short
git diff --stat
```

Expected: clean patch hygiene; status/stat contain only the intentional port, tests, and design/plan documents.

- [ ] **Step 5: Prepare the M5 smoke-test handoff**

Document these first-run checks without claiming they ran on Linux:

1. install native arm64 Neovim/Homebrew prerequisites and clone `mac-nvim`;
2. run `:Lazy sync`, `:Mason`, and `:checkhealth`;
3. install non-LSP Mason packages `java-debug-adapter`, `java-test`, `codelldb`, and `netcoredbg` as needed;
4. open representative Nuxt `.vue`, Java, ASP.NET `.cs`/`.cshtml`, PHP, GLSL, and WGSL files;
5. confirm `:LspInfo`, `:FormatInfo`, `:DotnetInfo`, Java test/debug actions, and `:ShaderCheck`.
