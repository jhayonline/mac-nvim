# Apple Silicon Neovim Config Sync Design

## Intent

Turn `mac-nvim` into the macOS/Apple Silicon counterpart of the active
`~/.config/nvim` configuration. Every user-facing editor capability added to
the Arch configuration since the shared September 4 baseline should be
available on the M5 Mac, without carrying over Linux package assumptions,
paths, or installation instructions that would make the Mac setup misleading
or fail at runtime.

## Goals

- Port all functional changes from `~/.config/nvim`, including Vue 3/Nuxt 4,
  Java, Razor/ASP.NET MVC, graphics and shader tooling, CMake, Odin, Mojo, and
  the revised Rust workflow.
- Preserve the active configuration's behavior for existing TypeScript,
  React, C/C++, Lua, PHP, Godot, Haskell, Typst, and Git workflows.
- Target an M5 Apple Silicon Mac with native arm64 tooling and Homebrew under
  `/opt/homebrew`.
- Keep home-directory and Mason-installed tools working when they are the
  configuration's existing preferred installation mechanism.
- Carry over the Vue/Nuxt regression test and add focused checks for the
  macOS-specific path and architecture decisions introduced by this port.
- Update documentation so installation commands and resolved paths describe
  the new M5 Mac rather than the former Intel Mac or the current Arch host.

## Non-goals

- Turning this repository into the one shared configuration for both Arch and
  macOS.
- Changing the live Arch configuration in `~/.config/nvim`.
- Installing Homebrew packages, language runtimes, Mason packages, or Neovim
  plugins on the current Linux machine or on the Mac remotely.
- Copying machine output and repository internals such as `nvim.log`, `.git`,
  `.superpowers`, or editor caches.
- Redesigning working keymaps, UI choices, or language workflows unrelated to
  the platform migration.

## Constraints

- The destination is macOS on Apple Silicon (M5/arm64), not the Intel Mac
  documented by the September configuration.
- The authoritative shared merge base is commit `5e875fe` (`init: I am
  Batman`, dated 2026-09-04) in both checkouts.
- The active Arch config contains uncommitted work. It is a read-only source;
  the port must not edit, clean, stage, or commit it.
- Before this design document was added, the destination had no tracked or
  untracked runtime edits after `5e875fe`. If an overlap appears during the
  port, preserve the source's current feature behavior and change only the
  platform-specific path, architecture, package, or documentation detail
  required for macOS.
- Existing destination-only metadata under `.agents` and `.codex`, if any, is
  preserved.
- Use Neovim's portable `stdpath()` locations for Lazy, Mason, cache, and data
  wherever the source already does so.
- Do not hard-code `/home/jhayonline` or Linux-only package-manager paths into
  runtime configuration or reusable verification commands.
- Keep the native Neovim 0.12 `vim.lsp.config` API and the source config's
  selected `ts_ls` plus `vue_ls` architecture.

## Approaches

1. **macOS-focused selective port (selected).** Merge every functional source
   change into the destination, then adapt paths, architecture, discovery, and
   documentation for Apple Silicon. This preserves the purpose of `mac-nvim`
   and avoids making its behavior depend on Linux branches that will never be
   used there.
2. **One cross-platform mirror.** Copy the active config wholesale and add OS
   checks around all platform differences. This would reduce future diff size,
   but it changes `mac-nvim` into a second general-purpose config and retains
   Linux concerns the user explicitly separated into another checkout.
3. **Raw file synchronization.** Copy all changed and new files verbatim. This
   is rejected because the source currently documents and probes Arch-specific
   .NET locations, package names, certificate behavior, JDK installs, and
   formatter packages; a verbatim copy would not be a dependable Mac config.

The selected approach follows the user's request for a macOS version and their
clarification that the new machine is an M5 Mac.

## Design

### Source-of-truth merge

Use commit `5e875fe` as the exact merge base. Port every
changed runtime file and every newly added runtime module from the active
config, including its current `lazy-lock.json`. Preserve destination files
that have no source-side change. The result should have feature parity rather
than byte-for-byte parity: platform documentation and discovery code are
expected to differ.

The feature port includes:

- Vue/Nuxt hybrid LSP support (`vue_ls` plus the Vue TypeScript plugin in
  `ts_ls`), Vue filetype defaults, Treesitter, Prettier ownership, Mason setup,
  documentation, and headless regression coverage.
- Java via `nvim-jdtls`, Java debug/test bundles, per-project workspaces,
  filetype keymaps, and Java skeleton generation.
- Expanded .NET/Razor/ASP.NET MVC commands, Roslyn settings, DAP integration,
  skeletons, and documentation.
- Shader filetypes, Treesitter parsers, GLSL/WGSL language servers,
  `:ShaderCheck`, CMake support, and associated formatters.
- The active config's Rust simplification, Odin and Mojo support, cursor
  behavior, formatting updates, and documentation corrections.

### Apple Silicon adaptation

Runtime discovery will prefer portable paths and Apple Silicon conventions:

- Homebrew prefixes use `/opt/homebrew`; `/usr/local` remains only as a benign
  compatibility fallback for manually installed tools.
- .NET supports the existing `~/.dotnet` install-script layout and the
  Apple-Silicon Homebrew layout. Documentation uses an `osx-arm64` SDK and no
  longer describes Intel `osx-x64` artifacts or Arch split packages.
- PHP documentation and PATH bootstrapping prefer
  `/opt/homebrew/opt/php@8.4`; Composer/global tool discovery remains under the
  user's home directory where appropriate.
- Java runtime discovery supports mise plus standard macOS JDK bundles under
  `/Library/Java/JavaVirtualMachines` and Homebrew OpenJDK under
  `/opt/homebrew/opt`.
- C/C++ LSP query-driver configuration accepts Apple Clang and Homebrew
  compilers without assuming GNU compilers live only under `/usr/bin`.
- CodeLLDB uses `liblldb.dylib` on macOS. Mason and `stdpath()` continue to
  supply architecture-correct package locations.
- Linux-specific certificate-store and package-manager guidance is replaced
  with macOS Keychain/Homebrew guidance. Linux fallback probes may remain only
  where they are inert and make runtime discovery safer, not in Mac-facing
  instructions.

### Documentation and install handoff

The README and stack documents will describe what the config supports and
what must be installed on the new Mac. Commands should avoid claiming that
software is already installed before the configuration has actually run on
the M5. Where package availability can vary, documentation will distinguish
Homebrew packages, official installers, Mason packages, and project-local npm
dependencies.

Vue/Nuxt documentation retains `nuxt prepare`, `nuxt typecheck`, project-local
TypeScript, Vue, ESLint, and Prettier prerequisites. C# documentation retains
the newly added MVC/Razor workflow while replacing the Arch installation
section. Java documentation is added to the README/tooling notes sufficiently
to explain JDK and Mason bundle prerequisites.

### Verification

- Compare source and destination inventories and explicitly account for every
  source-side runtime change or addition.
- Run the ported Vue/Nuxt headless regression test using a runtimepath resolved
  from `stdpath()` or the current environment, never a hard-coded Linux home.
- Add/run a focused headless test that stubs or inspects platform discovery for
  Apple Silicon paths without requiring macOS binaries on the Linux host.
- Parse every changed Lua file with `luac` when available and source changed
  Vim ftplugins in a minimal Vim/Neovim session.
- Run `git diff --check` and a full headless Neovim startup with temporary XDG
  state/cache/data directories so verification does not mutate the user's live
  Arch Neovim state.
- Because the implementation host is Linux, clearly separate static/headless
  verification completed here from the final smoke test that must run on the
  M5 (`:checkhealth`, `:Lazy sync`, `:Mason`, and representative Vue, Java,
  C#, PHP, and shader files).

## Success Criteria

- Every functional file added or changed in the active config is represented
  in `mac-nvim`, with any deliberate difference explained by macOS adaptation.
- A Vue or Nuxt project receives both required Vue/TypeScript clients, Vue
  parsing, formatting, Tailwind/ESLint/Emmet integration, and documented Nuxt
  generated types.
- No runtime file contains a hard-coded `/home/jhayonline` path or depends on
  `pacman`/Arch package layout to start successfully.
- Installation documentation targets M5/arm64 and `/opt/homebrew`, with no
  stale claim that the machine is Intel.
- All locally runnable verification passes, and the remaining on-device smoke
  tests are concise and explicit.
