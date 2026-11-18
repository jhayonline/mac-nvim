# Disable Rust Analyzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop Neovim from starting rust-analyzer while preserving Rust formatting and lightweight manual Cargo checks.

**Architecture:** Remove the rustaceanvim Rust LSP plugin and its Mason installation entry. Keep `conform.nvim`'s `rustfmt` formatter and the existing Rust filetype settings. Update documentation and stale debugger/LSP comments so the config accurately describes the reduced Rust stack.

**Tech Stack:** Neovim, lazy.nvim, Mason, conform.nvim, rustfmt, Cargo.

**Spec:** Approved option 1 from the conversation: disable Rust Analyzer for responsiveness; retain rustfmt and manual `cargo check`/`cargo clippy` workflows.

## Global Constraints

- Do not alter unrelated uncommitted Neovim changes.
- Do not remove Rust formatting support.
- Do not add another resident Rust language server.

## Review Focus

- Rust buffers must not load rustaceanvim or start rust-analyzer.
- Rust save formatting must continue through rustfmt.
- Mason must not reinstall rust-analyzer through `ensure_installed`.
- Rust debugging configuration must remain syntactically valid.
- Documentation must not claim Rust Analyzer features remain available.

### Task 1: Remove the Rust LSP integration

**Files:**
- Modify: `lua/engine/plugins/rust.lua`
- Modify: `lua/engine/plugins/lsp/mason.lua`
- Modify: `lua/engine/plugins/lsp/lspconfig.lua`
- Modify: `lua/engine/plugins/dap.lua`

- [ ] Remove the rustaceanvim plugin declaration and Rust Analyzer-specific Mason/LSP ownership comments while retaining `crates.nvim` and plain CodeLLDB Rust fallback configuration.
- [ ] Verify Lua syntax and search the active config for executable Rust Analyzer/rustaceanvim setup.

### Task 2: Keep the lightweight Rust workflow documented

**Files:**
- Modify: `README.md`
- Modify: `doc/rust.md`

- [ ] Document rustfmt-on-save and manual `cargo check`/`cargo clippy` as the Rust workflow, removing claims about rustaceanvim/rust-analyzer commands.
- [ ] Verify the docs match the active configuration.

### Task 3: Validate the configuration

- [ ] Run Neovim headless startup and Lua syntax checks.
- [ ] Confirm `conform.nvim` still maps Rust buffers to `rustfmt`.
- [ ] Review the diff to ensure unrelated user changes are untouched.
