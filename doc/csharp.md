# C# / .NET in this config

Everything needed for ASP.NET Core MVC, EF Core and plain C# work: code
intelligence from the Roslyn language server, build and EF commands that stay
inside Neovim, CSharpier on save, debugging through netcoredbg, and `:Skel`
templates that know your project's namespace.

---

## What is installed, and where

The SDK went into `~/.dotnet` via Microsoft's official `dotnet-install.sh`
rather than Homebrew. The Homebrew cask (`brew install --cask dotnet-sdk`)
installs a `.pkg` system-wide and needs your admin password typed
interactively; the install script needs no `sudo` and puts everything under
your home directory, which is a fully supported layout.

| Component | Version | Location |
| --- | --- | --- |
| .NET SDK | 10.0.400 (`osx-x64`) | `~/.dotnet` |
| ASP.NET Core runtime | 10.0.11 | `~/.dotnet/shared` |
| `roslyn-language-server` | 5.12.0 | `~/.dotnet/tools` |
| `csharpier` | 1.3.0 | `~/.dotnet/tools` |
| `dotnet-ef` | 10.0.11 | `~/.dotnet/tools` |
| `dotnet-outdated` | 4.8.1 | `~/.dotnet/tools` |
| `netcoredbg` | 3.1.3 | `~/.local/share/nvim/mason/bin` |

`~/.zshrc` gained this block (the previous file is backed up at
`~/.zshrc.bak-predotnet`):

```sh
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
```

Neovim does not rely on that. `engine.core.dotnet` patches `DOTNET_ROOT` and
`PATH` into `vim.env` at startup, so `nvim` launched from Finder or a GUI
launcher — which never reads `.zshrc` — still finds the SDK and the tools.

> **Your machine is Intel (`x86_64`).** Every component above is the
> `osx-x64` build. If you ever move to Apple Silicon, reinstall the SDK and
> re-run `:MasonInstall netcoredbg`; the `dotnet tool` packages are portable
> and need no attention.

### Reinstalling from scratch

```sh
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0 --architecture x64
dotnet tool install -g roslyn-language-server --prerelease \
  --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
dotnet tool install -g csharpier
dotnet tool install -g dotnet-ef
dotnet tool install -g dotnet-outdated-tool
nvim --headless -c 'MasonInstall netcoredbg' -c qa
```

Keep the tools current with `dotnet tool update -g <name>`.

---

## The language server

C# is served by the **Roslyn language server** — the same engine behind Visual
Studio and the VS Code C# extension, driven by
[roslyn.nvim](https://github.com/seblyng/roslyn.nvim).

**OmniSharp has been removed.** It was retired upstream, and it was actively
harmful here: Mason still had it installed, and mason-lspconfig v2 auto-enables
every installed server, so OmniSharp was attaching to `.cs` buffers *alongside*
Roslyn and throwing `INVALID_SERVER_MESSAGE`. It is uninstalled, and
`mason.lua` now lists it under `automatic_enable.exclude` so a stray reinstall
cannot bring the conflict back.

Roslyn reads `.sln`, `.slnx` and `.csproj` directly, so it understands project
references, `ImplicitUsings`, analyzers and source generators the way the real
build does. `.NET 10`'s `dotnet new sln` produces the newer `.slnx` format;
both it and classic `.sln` are handled.

What you get that OmniSharp did not give you:

- **Solution-wide compiler diagnostics.** Rename a model property and every
  broken controller, view-model and migration lights up immediately, not only
  when you open the file.
- **Completion from unimported namespaces**, with the `using` added for you —
  the single biggest quality-of-life win in ASP.NET work.
- **Decompiled sources.** `gd` on a framework or NuGet type lands in readable
  C#, not a metadata stub.
- **Razor / `.cshtml` support in-process.** (`rzls.nvim` was discontinued once
  roslyn.nvim absorbed this; do not install it.)
- **Code lens**: reference counts on members, run/debug lenses on `[Fact]` and
  `[Test]` methods.
- **Inlay hints**: inferred `var` types, lambda parameter types, and argument
  names at call sites.

### Where the settings live, and why

Server settings are in **`after/lsp/roslyn.lua`**, not in the plugin spec. This
is deliberate and worth understanding before you move them.

roslyn.nvim's `plugin/roslyn.lua` calls `vim.lsp.enable("roslyn")` the moment
lazy.nvim sources the plugin — which happens *before* lazy runs the plugin's
`config()`/`opts`. Any `vim.lsp.config("roslyn", …)` call made from `config()`
therefore loses a race: the session's first client starts with none of it
applied. That is not theoretical — it is exactly what happened here during
setup, and it silently cost the inlay hints and every setting below.

Neovim resolves `lsp/<name>.lua` files by re-reading **every match on the
runtimepath** at the moment a client starts, deep-merging them with `after/`
merged last. So `after/lsp/roslyn.lua` always wins over roslyn.nvim's own
`lsp/roslyn.lua`, and always applies regardless of load order. Put server
config there; keep only plugin-level behaviour in
`lua/engine/plugins/lsp/roslyn.lua`.

### Tuning knobs

In `after/lsp/roslyn.lua`:

| Setting | Current | Why |
| --- | --- | --- |
| `dotnet_compiler_diagnostics_scope` | `fullSolution` | Real compile errors everywhere. Worth the cost. |
| `dotnet_analyzer_diagnostics_scope` | `openFiles` | Style/quality analyzers are the expensive half. Raise to `fullSolution` if you want `IDExxxx`/`CAxxxx` everywhere and can spare the CPU — this is a 4-core Haswell. |

In `lua/engine/plugins/lsp/roslyn.lua`:

| Option | Current | Why |
| --- | --- | --- |
| `filewatching` | `"roslyn"` | The server watches files instead of Neovim's libuv watcher. Cheaper, and it silences the one-off `watch.watch: ENOENT` notice Neovim emits when Roslyn asks it to watch a directory the build has not created yet. |
| `broad_search` | `false` | Only looks for a solution beside or above the buffer. Set `true` if you keep solution files in a sibling directory. |
| `lock_target` | `false` | Re-evaluates the solution when you jump into another one. |

Run `:checkhealth roslyn` to see the resolved target, the server path and the
file-watching mode.

---

## `:Skel` for C#

`:Skel` replaces the buffer with a skeleton. It already did this for C/C++;
it now does C# as well, and takes an optional template name.

```vim
:Skel              " infer the template from the filename
:Skel record       " force a specific template (<Tab> completes)
```

### Namespaces are derived, not guessed

The namespace comes from `<RootNamespace>` in the nearest `.csproj` (defaulting
to the project file's own name), plus the directory path from that `.csproj`
down to the file — the same rule the SDK templates use.

```
src/Shop.Web/Shop.Web.csproj
src/Shop.Web/Controllers/HomeController.cs   ->  namespace Shop.Web.Controllers;
src/Shop.Data/Models/Product.cs              ->  namespace Shop.Data.Models;
```

Namespaces are file-scoped (`namespace Foo;`). Set
`vim.g.skel_csharp_block_namespace = true` for the older braced form.

`ImplicitUsings` is read from the `.csproj`: with it enabled, `using System;`
and the ASP.NET defaults are omitted, and only genuinely-needed usings are
written. Indentation follows the buffer, so the output matches
`ftplugin/cs.vim` (4 spaces) and CSharpier.

### Inferred templates

With no argument, the filename decides:

| Filename | Template |
| --- | --- |
| `Program.cs` | top-level statements — full MVC bootstrap in a web project, `Console.WriteLine` otherwise |
| `Startup.cs` | pre-.NET 6 `Startup` class |
| `IFoo.cs` | `interface` |
| `FooController.cs` | `controller` (MVC, returns `View()`) or `apicontroller` (`[ApiController]` + `ControllerBase`) — chosen by whether the project has a `Views/` directory, or the file sits under `Api/` |
| `FooDbContext.cs` | EF Core `DbContext` with primary-constructor options and `OnModelCreating` |
| `FooMiddleware.cs` | middleware class *and* its `UseFoo()` extension |
| `FooTests.cs` | xunit class with a `[Fact]` |
| `FooRepository.cs`, `FooService.cs` | interface + implementing class |
| `FooDto.cs`, `FooViewModel.cs`, `FooRequest.cs`, `FooResponse.cs` | positional `record` |
| `FooOptions.cs`, `FooSettings.cs`, `FooConfig.cs` | options class with a `SectionName` const |
| `FooException.cs` | exception with the three conventional constructors |
| `FooAttribute.cs` | sealed attribute with `[AttributeUsage]` |
| `FooExtensions.cs` | `static class` |
| anything else | `class` |

### Explicit templates

`class`, `static`, `abstract`, `sealed`, `interface`, `record`, `struct`,
`enum`, `exception`, `attribute`, `options`, `service`, `controller`,
`apicontroller`, `dbcontext`, `middleware`, `test`, `program`, `minimalapi`,
`startup`.

Example — `src/Shop.Web/Controllers/ProductController.cs`, `:Skel`:

```csharp
using Microsoft.AspNetCore.Mvc;

namespace Shop.Web.Controllers;

public class ProductController : Controller
{
    public IActionResult Index()
    {
        return View();
    }
}
```

---

## Commands

### Build pipeline — results go to the quickfix list

These run asynchronously and populate `:copen` with real diagnostics. MSBuild
repeats each diagnostic once per target framework and per referencing project;
duplicates are collapsed, and the trailing `[/path/Project.csproj]` is stripped.

| Command | Action |
| --- | --- |
| `:DotnetBuild [args]` | Build the solution (or nearest project) |
| `:DotnetRestore` | Restore NuGet packages |
| `:DotnetClean` | Clean build output |
| `:DotnetPublish [args]` | Publish in Release |
| `:DotnetAdd <package>` | `dotnet add package` on the nearest project |
| `:DotnetFormat` | CSharpier over the whole project |

Navigate results with `:cnext` / `:cprev`. On success the quickfix window
closes itself.

### Interactive — these open a terminal split

| Command | Action |
| --- | --- |
| `:DotnetRun [args]` | Run the current project |
| `:DotnetWatch [args]` | `dotnet watch run` — rebuild and hot-reload on save. **The ASP.NET inner loop.** |
| `:DotnetTest [args]` | Run the test suite |
| `:DotnetNew <template>` | Scaffold from a template (`<Tab>` completes `mvc`, `webapi`, `classlib`, `xunit`, `sln`, …) |
| `:DotnetOutdated` | List outdated NuGet packages |

`:DotnetRun` and `:DotnetWatch` need a single project, never a solution. From a
file in a class library they automatically target the web project in the
solution, which is what you almost always mean.

### Entity Framework Core

| Command | Action |
| --- | --- |
| `:EfAdd [name]` | Add a migration (prompts if no name given) |
| `:EfUpdate [target]` | Apply migrations. With a target, migrate *to* it — `:EfUpdate 0` reverts the database to empty |
| `:EfRemove` | Remove the last migration |
| `:EfList` | List migrations |
| `:EfScript` | Generate an idempotent SQL script |
| `:EfDrop` | Drop the database (asks first) |
| `:EfScaffold "<conn>" [provider]` | Reverse-engineer models from an existing database into `Models/` (provider defaults to SQL Server) |
| `:EfProject [path]` | Pin `--project` (no argument resets) |
| `:EfStartupProject [path]` | Pin `--startup-project` (no argument resets) |

EF needs two projects: the one holding the `DbContext` and migrations
(`--project`) and the one that boots the host and builds the service provider
(`--startup-project`). In a single-project MVC app they are the same. In a
layered solution they are not, and **this is resolved for you**: `--project` is
the nearest `.csproj`, and `--startup-project` automatically hops to the web
project in the solution when you are editing a class library. Both are
overridable with `:EfProject` / `:EfStartupProject` when the guess is wrong.

### Diagnostics and formatting

| Command | Action |
| --- | --- |
| `:DotnetInfo` | Show the resolved context: solution, project, EF project pair, the solution Roslyn selected, and the path to every tool |
| `:DotnetFormatToggle` | Toggle CSharpier on save |

`:DotnetInfo` is the first thing to run when something behaves oddly — it shows
exactly which project and solution the commands are acting on.

---

## Formatting

CSharpier runs on every save of a `.cs` file. It is the gofmt of C#: opinionated
and essentially optionless, so there is nothing to configure and no formatting
argument to have.

It prefers a **project-local** CSharpier when the `.csproj` pins one via
`CSharpier.MsBuild`, falling back to the global tool — so your output stays
byte-identical with CI. Disable per-session with `:DotnetFormatToggle`, or
permanently with `vim.g.dotnet_format_on_save = false`.

`.editorconfig` is honoured by Roslyn for analyzer and style rules; CSharpier
handles layout.

---

## Debugging

netcoredbg is wired into your existing nvim-dap setup, so the keys are the ones
you already use:

| Key | Action |
| --- | --- |
| `<leader>db` | Toggle breakpoint |
| `<leader>dc` | Continue / start |
| `<leader>ds` / `<leader>di` / `<leader>do` | Step over / into / out |
| `<leader>dr` / `<leader>dt` | Restart / terminate |

Three configurations appear for C# buffers:

- **Launch** — runs the built assembly.
- **Launch (ASP.NET Development)** — sets `ASPNETCORE_ENVIRONMENT=Development`
  so `appsettings.Development.json`, user secrets and the developer exception
  page all behave as they do in a normal `dotnet run`. **Use this one for web
  work.**
- **Attach to process** — pick a running process, e.g. an existing
  `dotnet watch`.

The assembly is found by globbing `bin/<config>/<tfm>/<AssemblyName>.dll`
(newest wins), so target-framework bumps need no config changes. **Run
`:DotnetBuild` before debugging** — the picker prompts for a path if nothing
has been built.

---

## Editing behaviour

`ftplugin/cs.vim` and `ftplugin/razor.vim` override the global defaults
(8-wide hard tabs, right for C, wrong for C#):

- 4-space indentation, matching every .NET convention and CSharpier.
- Folding on `#region` / `#endregion` in C# — the global `foldmarker` is the
  C++ `#pragma region` spelling and never matches a C# file. Razor folds on
  indent instead.
- `commentstring` set correctly per language: `// …` for C#, `@* … *@` for
  Razor, which is neither the HTML nor the C# form.
- `matchpairs` includes `<`/`>` so `%` jumps across generic arguments.

Filetype detection is extended in `engine.core.dotnet`: `.cshtml` and `.razor`
map to `razor` (Neovim ships `.cshtml` as plain `html`, which loses every C#
construct in the file and stops Roslyn from attaching), and `.csproj`,
`.props`, `.targets`, `.slnx` and `nuget.config` map to `xml`.

---

## Typical workflows

### New MVC app

```vim
:DotnetNew mvc
:DotnetWatch          " hot reload; leave it running
```

Then create `Controllers/ProductController.cs` and run `:Skel`.

### New layered solution

```sh
dotnet new sln -n Shop
dotnet new mvc -o src/Shop.Web
dotnet new classlib -o src/Shop.Data
dotnet sln add src/Shop.Web src/Shop.Data
dotnet add src/Shop.Web reference src/Shop.Data
```

Open any file in the tree; Roslyn finds the solution on its own.

### Adding an EF model and migration

1. Create `src/Shop.Data/Models/Order.cs`, `:Skel` → a class.
2. Add `public DbSet<Order> Orders => Set<Order>();` to your `DbContext`.
3. `:EfAdd AddOrders`
4. `:EfUpdate`

The `--project` / `--startup-project` split is handled automatically. Confirm
with `:DotnetInfo` if a migration lands somewhere unexpected.

---

## Where things live

```
after/lsp/roslyn.lua                    Roslyn server settings (read the note at the top)
lua/engine/plugins/lsp/roslyn.lua       roslyn.nvim plugin spec
lua/engine/core/dotnet.lua              :Dotnet*/:Ef* commands, PATH, filetypes, format on save
lua/engine/tools/skeleton_csharp.lua    :Skel templates and namespace resolution
lua/engine/tools/skeleton.lua           :Skel dispatcher (C/C++ and C#)
ftplugin/cs.vim, ftplugin/razor.vim     buffer options
lua/engine/plugins/dap.lua              netcoredbg adapter and configurations
lua/engine/plugins/lsp/mason.lua        omnisharp excluded from auto-enable
lua/engine/plugins/todo_marker.lua      conform: cs -> csharpier
```

---

## Troubleshooting

**No completion or diagnostics.** `:DotnetInfo` — if `roslyn server` shows
`NOT FOUND`, the global tool is missing; reinstall it (see above).
`:checkhealth roslyn` shows which solution was selected. `:LspLog` has the rest.

**Wrong solution selected.** `:Roslyn target` switches between solutions.
Set `broad_search = true` if your solution file is not beside or above the
buffer.

**First open of a solution is slow.** Expected: Roslyn restores and loads every
project before diagnostics settle. Subsequent opens are much faster.

**Migration landed in the wrong project.** `:DotnetInfo` shows the resolved
pair; pin it with `:EfProject` and `:EfStartupProject`.

**Editor feels heavy on a large solution.** Set
`dotnet_compiler_diagnostics_scope` to `openFiles` in `after/lsp/roslyn.lua`.

---

## Treesitter (fixed after this document was first written)

`lua/engine/plugins/treesitter.lua` pinned `branch = "master"` but called
`require("nvim-treesitter").setup{...}` — the wrong entry point on that branch,
which silently discarded `highlight`, `autotag` and `ensure_installed`. No
parser had ever been installed and highlighting was off for every language.

This was fixed while setting up the React/TypeScript stack, where JSX
highlighting made it a blocker. The change was one line
(`require("nvim-treesitter.configs")`), and 31 parsers are now compiled —
`c_sharp`, `xml` and `sql` among them, so C# files now get treesitter
highlighting layered under Roslyn's semantic tokens.

See [`doc/frontend.md`](frontend.md) for the details.
