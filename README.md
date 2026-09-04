# Pride's Neovim Config

A focused Neovim setup for day-to-day coding, with fast navigation, LSP-backed editing, debugging, file browsing, and a theme workflow that is easy to switch without touching config files.

## Showcase

| Start screen | Code editing |
| --- | --- |
| ![Start screen](showcase/start_screen.png) | ![Code editing](showcase/code_editing.png) |

| File tree | Theme picker |
| --- | --- |
| ![File tree](showcase/file_tree.png) | ![Theme picker](showcase/color_theme_selection.png) |

## Highlights

- Plugin management through [lazy.nvim](https://github.com/folke/lazy.nvim), bootstrapped automatically on first launch.
- Fuzzy finding, live grep, references, implementations, and diagnostics through Telescope.
- LSP setup for TypeScript, C/C++, Lua, Rust, Typst, Haskell, GDScript, and Godot shader files.
- Completion with `nvim-cmp`, LuaSnip snippets, path suggestions, buffer words, and LSP sources.
- Treesitter highlighting for web, systems, scripting, markdown, Haskell, C#, Rust, PHP/Blade and Godot filetypes.
- Debugging through `nvim-dap`: C/C++/Rust via CodeLLDB, C# via netcoredbg, Rust also via `:RustLsp debuggables`.
- Format on save through `conform`, with the project-local formatter preferred over the global one.
- Git and GitHub: inline blame (GitLens-style), hunk staging, lazygit, diffview, and pull
  requests/issues through `octo`. See [`doc/git.md`](doc/git.md).

### Language stacks

Four stacks are set up end to end, each with its own document:

| Stack | Highlights | Docs |
| --- | --- | --- |
| C# / .NET | Roslyn LSP, `:Dotnet*` and `:Ef*` commands, CSharpier, netcoredbg, C# `:Skel` templates | [`doc/csharp.md`](doc/csharp.md) |
| React + TypeScript + Tailwind | `ts_ls`, Tailwind, ESLint, Emmet, prettier with class sorting | [`doc/frontend.md`](doc/frontend.md) |
| Rust | rustaceanvim, Clippy on save, `crates.nvim`, CodeLLDB debugging | [`doc/rust.md`](doc/rust.md) |
| PHP (Laravel **and** vanilla) | intelephense with framework stubs, Blade, `:Artisan*`, `:Php*`, Pint | [`doc/php.md`](doc/php.md) |
- A custom theme picker with persisted selection and quick next/previous theme commands.
- Practical UI touches: file tree, bufferline, lualine, diagnostics, folds, markdown rendering, and quality-of-life editing plugins.

## Install

Back up your existing config first, then clone this repo into Neovim's config directory:

```sh
git clone git@github.com:jhayonline/nvim.git ~/.config/nvim
nvim
```

On first launch, `lazy.nvim` installs itself and then installs the configured plugins.

### External tools

Some features work best when these tools are available on your `PATH`:

- `git`, `make`, and a C compiler for native plugin builds.
- Language servers such as `clangd`, `rust-analyzer`, `lua-language-server`, `tinymist`, and `haskell-language-server-wrapper`.
- `lldb-dap` or `codelldb` for debugging C, C++, and Rust.
- `gdshader-lsp` for Godot shader support.
- The .NET SDK plus the `roslyn-language-server`, `csharpier` and `dotnet-ef` global tools, and
  `netcoredbg`, for C#.
- `node`/`npm` and `prettier` for the React/TypeScript stack.
- `rustup` (cargo, clippy, rustfmt) and `codelldb` for Rust.
- PHP 8.4, Composer and the Laravel installer for PHP work.
- `git`, `gh`, `lazygit`, `delta`, `rg` and `fd` for version control and search.

All of these are already installed; each stack's document lists exact versions, install
locations and how to reinstall them.

> **Homebrew note:** Homebrew has moved Intel macOS to Tier 3 and no longer ships prebuilt
> bottles for it, so `brew install <formula>` may fail with `no bottle available!` and need
> either a tap that publishes its own bottles or a source build. This is how PHP ended up
> coming from the `shivammathur/php` tap.

## Keybindings

Leader is `<Space>`.

| Key | Action |
| --- | --- |
| `<leader>ff` | Find files |
| `<leader>fw` | Live grep |
| `<leader>fc` | Search word under cursor |
| `<leader>fW` / `<leader>fF` | Grep / find **including** ignored dirs (`vendor`, `node_modules`, …) |
| `<leader>fb`, `<leader>fh`, `<leader>fk` | Buffers, help, keymaps |
| `<leader>fs` / `<leader>fS` | Document / workspace symbols |
| `<leader>fd` | Workspace diagnostics |
| `<leader>fr` | Resume last picker |
| `<C-n>` | Focus file tree |
| `<leader>e` | Toggle file tree |
| `<Tab>` / `<S-Tab>` | Next / previous buffer |
| `<leader>x` | Close current buffer |
| `<leader>ts` | Select theme |
| `<leader>tn` / `<leader>tp` | Next / previous theme |
| `gd`, `gD`, `gi`, `gt` | LSP navigation |
| `<leader>ca` | Code action |
| `<leader>rn` | Rename symbol |
| `<leader>d` / `<leader>D` | Line / buffer diagnostics |
| `<leader>dc` | Continue debugger |
| `<leader>db` | Toggle breakpoint |
| `<leader>ds`, `<leader>di`, `<leader>do` | Step over / into / out |
| `<leader>rr`, `<leader>rd`, `<leader>rt` | Rust runnables / debuggables / testables |
| `<leader>rm`, `<leader>re`, `<leader>rc` | Rust expand macro / explain error / open Cargo.toml |
| `<leader>gb` / `<leader>gL` | Blame this line / blame the whole file |
| `<leader>gg` | Lazygit |
| `<leader>gs` / `<leader>gr` | Stage / reset hunk (works on a visual selection) |
| `]h` / `[h` | Next / previous hunk |
| `<leader>gm` | Diffview: this branch vs main |
| `<leader>gx` | Open the current line on GitHub |
| `<leader>gop` / `<leader>goi` | GitHub pull requests / issues |

## Commands

| Command | Action |
| --- | --- |
| `:Skel [template]` | Replace the buffer with a skeleton for its file type (C/C++ and C#) |
| `:DotnetBuild`, `:DotnetRun`, `:DotnetWatch`, `:DotnetTest` | .NET build and run, results in the quickfix list |
| `:EfAdd`, `:EfUpdate`, `:EfList`, … | EF Core migrations |
| `:Artisan*` | Laravel artisan, with real `<Tab>` completion from the app |
| `:PhpRun`, `:PhpLint`, `:PhpServe`, `:PhpTest`, `:PhpRepl` | Vanilla PHP — no Laravel needed |
| `:Composer`, `:Pint` | Composer commands and Laravel Pint |
| `:RustLsp runnables` / `debuggables` / `expandMacro` | rust-analyzer extensions (buffer-local, Rust files) |
| `:Format`, `:FormatToggle`, `:FormatInfo` | Format now, toggle format-on-save, show active formatters |
| `:DotnetInfo`, `:LaravelInfo` | Show the resolved project context for the current buffer |
| `:TypstPreview` | Open the compiled PDF for the current Typst file |
| `:Theme`, `:ThemeNext`, `:ThemePrev` | Theme picker |

Each stack's full command set is in its document, linked above.

## Structure

```text
init.lua                 Entry point
lua/engine/core/          Options, keymaps, theme state, filetype setup
lua/engine/plugins/       Plugin specs
lua/engine/plugins/lsp/   LSP and Mason setup
lua/engine/tools/         Small local helper tools
after/lsp/               Language server settings that must win the runtimepath merge
ftplugin/                Per-filetype buffer options
doc/                     Long-form documentation
showcase/                README screenshots
```
