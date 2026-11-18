# Rust

Rust Analyzer and rustaceanvim are intentionally disabled in this configuration
to keep Neovim responsive. Rust buffers still get deterministic formatting,
Cargo dependency tooling, and CodeLLDB debugging without a resident analyzer.

## Active workflow

- `rustfmt` runs on save through conform.nvim.
- Run `cargo check` or `cargo clippy --no-deps` in a terminal when you want
  compiler diagnostics.
- `crates.nvim` provides Cargo.toml completion, hover, version information, and
  dependency update actions.
- nvim-dap uses `lldb-dap` or `codelldb` for binaries you build with Cargo.

There are no active `:RustLsp` commands, rust-analyzer diagnostics, inlay hints,
runnables, macro expansion, or rustaceanvim keymaps. The disabled plugin spec
remains in `lua/engine/plugins/rust.lua` as migration context, but Lazy does
not load it and Mason does not install rust-analyzer.

## Formatting and checks

The Rust ftplugin uses four spaces to match rustfmt. Conform reads the edition
from Cargo.toml, so modern syntax is not formatted as Rust 2015.

Useful terminal commands:

```sh
cargo fmt --check
cargo check
cargo clippy --no-deps
cargo test
```

Use `:FormatInfo` if save formatting stops. It should list `rustfmt`; install
it through the active rustup toolchain if it is unavailable:

```sh
rustup component add rustfmt clippy
```

## Cargo.toml keymaps

These mappings are active only in Cargo.toml through crates.nvim:

| Key | Action |
| --- | --- |
| `K` / `<leader>rc` | Crate details |
| `<leader>rv` | Available versions |
| `<leader>rf` | Available features |
| `<leader>ru` | Update this crate |
| `<leader>rU` | Upgrade this crate, allowing a major version |
| `<leader>rA` | Upgrade every crate |

## Debugging

Install an arm64-compatible adapter with Mason:

```vim
:MasonInstall codelldb
```

Build the target first, place a breakpoint with `<leader>db`, then use
`<leader>dc`. The plain nvim-dap launcher looks for a matching executable in
the project root, `build/`, `bin/`, or `out/`; if none is found it prompts for
the path.

| Key | Action |
| --- | --- |
| `<leader>db` | Toggle breakpoint |
| `<leader>dc` | Continue/start |
| `<leader>ds` / `<leader>di` / `<leader>do` | Step over / into / out |
| `<leader>dt` | Terminate |

## Where things live

```text
lua/engine/plugins/rust.lua        disabled rustaceanvim spec + active crates.nvim
lua/engine/plugins/conform.lua     rustfmt formatting
lua/engine/plugins/dap.lua         plain LLDB/CodeLLDB Rust launch configuration
lua/engine/plugins/lsp/mason.lua   no rust-analyzer installation
ftplugin/rust.vim                  four-space buffer defaults
```
