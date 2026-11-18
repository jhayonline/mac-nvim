# C# / .NET in this config

Everything needed for ASP.NET Core MVC, EF Core and plain C# work: code
intelligence from the Roslyn language server, build and EF commands that stay
inside Neovim, CSharpier on save, debugging through netcoredbg, and `:Skel`
templates that know your project's namespace.

> **Looking for how to *use* it?** This document is the reference — what is
> installed, how it is wired, every command and setting. For walkthroughs —
> a console app, an MVC app from `dotnet new` to working CRUD screens, and the
> keys to press day to day — see [`doc/CsToolUse.md`](CsToolUse.md).

---

## What to install, and where it lives

The target machine is an M5 Mac. Use the native arm64 .NET SDK. The debugger is
the current exception: Mason's `netcoredbg` definition maps both `darwin_arm64`
and `darwin_x64` to Samsung's `netcoredbg-osx-amd64.tar.gz`, because upstream
does not publish a native Apple Silicon archive. It therefore requires Rosetta
2. If you do not want Rosetta on the Mac, skip `netcoredbg`; editing, building,
testing, Roslyn, and every non-debug command in this guide remain native arm64.
The recommended SDK layout is Microsoft's install script under `~/.dotnet`,
which includes the compiler, MSBuild, ASP.NET Core runtime, and targeting packs
together.

| Component | Install with | Expected location |
| --- | --- | --- |
| .NET 10 SDK + ASP.NET Core packs | `dotnet-install.sh --channel 10.0 --architecture arm64` | `~/.dotnet` |
| `roslyn-language-server` | `dotnet tool install -g` | `~/.dotnet/tools` |
| `csharpier` | `dotnet tool install -g` | `~/.dotnet/tools` |
| `dotnet-ef` | `dotnet tool install -g` | `~/.dotnet/tools` |
| `dotnet-aspnet-codegenerator` | `dotnet tool install -g` | `~/.dotnet/tools` |
| `dotnet-outdated` | `dotnet tool install -g` | `~/.dotnet/tools` |
| `netcoredbg` (amd64) | Rosetta 2, then `:MasonInstall netcoredbg` | `~/.local/share/nvim/mason/bin` |

`engine.core.dotnet` patches `DOTNET_ROOT` and `PATH` into `vim.env` at
startup. It checks `~/.dotnet` first, then the Apple Silicon Homebrew SDK
location, and always adds `~/.dotnet/tools`. Neovim therefore finds the SDK
and global tools even when launched from a GUI that never reads `.zshrc`.

### Installing from scratch

```sh
# 1. Native Apple Silicon SDK. The SDK includes ASP.NET Core and its packs.
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 10.0 --architecture arm64
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"

# 2. Global tools. The Roslyn server is NOT on nuget.org at a usable version:
#    roslyn.nvim wants >= 5.12.0-1.26453.19, and razor/.cshtml support needs
#    >= 5.8.0-1.26262.10. The Azure DevOps feed is the one vscode itself uses.
dotnet tool install -g roslyn-language-server --prerelease \
  --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
dotnet tool install -g csharpier
dotnet tool install -g dotnet-ef
dotnet tool install -g dotnet-aspnet-codegenerator
dotnet tool install -g dotnet-outdated-tool

# 3. Optional C# debugging. Mason currently installs the amd64 archive on
#    darwin_arm64, so install Rosetta 2 first or skip this line.
softwareupdate --install-rosetta
nvim --headless -c 'MasonInstall netcoredbg' -c qa

# 4. The native Razor parser
nvim --headless -c 'Lazy load nvim-treesitter' -c 'TSInstallSync razor' -c qa

# 5. HTTPS dev certificate. macOS asks for permission to trust it in Keychain.
dotnet dev-certs https --trust        # or :DotnetDevCerts
```

The debugger limitation is architectural, not a PATH problem. Do not replace
the Mason package with an unverified binary renamed `netcoredbg`; either use
the published amd64 build through Rosetta 2 or leave debugging uninstalled.

`dotnet dev-certs https --trust` integrates with macOS Keychain. Approve the
system prompt; do not set Linux `SSL_CERT_DIR` or NSS paths in the Mac shell.

Keep the tools current with `dotnet tool update -g <name>`. Verify the whole
chain from inside nvim with `:DotnetInfo`, which reports the SDK version
separately from the `dotnet` binary — `dotnet --version` answers with the
*host* version even when no SDK is installed, so use `dotnet --list-sdks` as
the definitive check.

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
| `dotnet_analyzer_diagnostics_scope` | `openFiles` | Style/quality analyzers are the expensive half. Raise to `fullSolution` if you want `IDExxxx`/`CAxxxx` everywhere and can spare the background work. |

In `lua/engine/plugins/lsp/roslyn.lua`:

| Option | Current | Why |
| --- | --- | --- |
| `filewatching` | `"roslyn"` | The server watches files instead of Neovim's libuv watcher. Cheaper, and it silences the one-off `watch.watch: ENOENT` notice Neovim emits when Roslyn asks it to watch a directory the build has not created yet. |
| `broad_search` | `false` | Only looks for a solution beside or above the buffer. Set `true` if you keep solution files in a sibling directory. |
| `lock_target` | `false` | Re-evaluates the solution when you jump into another one. |

Run `:checkhealth roslyn` to see the resolved target, the server path and the
file-watching mode.

---

### Code lens

Reference counts above every member. **Informational only** — the reference
lens carries no command, and this server advertises an empty
`executeCommandProvider`, so there is nothing to click and deliberately no
keymap to "run" one. It is still worth having: `0 references` above a method
you thought was wired up is the cheapest dead-code check there is.

Getting even that on screen took **two** things, and only the first was here:

1. Asking the server for lenses — `dotnet_enable_references_code_lens` in
   `after/lsp/roslyn.lua`.
2. Enabling code lens for the buffer. Neovim renders nothing until
   `vim.lsp.codelens.enable()` is called, and nothing called it — so Roslyn was
   computing lenses on every edit and they were dropped on the floor.

`on_attach` now does (2) with `vim.lsp.codelens.enable(true, { bufnr })` rather
than the older `codelens.refresh()`: `enable` goes through the same
`vim.lsp._capability` machinery as `inlay_hint.enable`, so it re-requests as
the buffer changes instead of needing hand-written
`BufEnter`/`CursorHold`/`InsertLeave` autocmds. (`refresh()` is deprecated for
removal in 0.13.) It is scoped to C# rather than added to the shared
`LspAttach` handler, since Roslyn is the only server here that emits lenses.

#### Test lenses are off, on purpose

`dotnet_enable_tests_code_lens` is `false`. Roslyn's *Run Test* / *Debug Test*
/ *Run All Tests* lenses invoke `dotnet.test.run` — a **VS Code** command
contributed by the C# extension, not an LSP one. In the current server stack the
server advertises no executable commands, roslyn.nvim implements only
`fixAllCodeAction`, `nestedCodeAction` and `completionComplexEdit`, and nothing
handles `dotnet.test.run`. Left on, you get four lenses per test file that
render, offer themselves in a picker, and do nothing.

**`:DotnetTestHere` is the working replacement.** It runs the test under the
cursor via `dotnet test --filter FullyQualifiedName~Class.Method`, built from
the cursor position with treesitter — no editor integration required. Cursor
inside a method runs that test; elsewhere in the class runs the class.

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
| `:DotnetTestHere` | Run only the test under the cursor, via `--filter` (see [Code lens](#test-lenses-are-off-on-purpose)) |
| `:DotnetNew <template>` | Scaffold from a template (`<Tab>` completes `mvc`, `webapi`, `classlib`, `xunit`, `sln`, …) |
| `:DotnetOutdated` | List outdated NuGet packages |

`:DotnetRun` and `:DotnetWatch` need a single project, never a solution. From a
file in a class library they automatically target the web project in the
solution, which is what you almost always mean.

### ASP.NET Core MVC

| Command | Action |
| --- | --- |
| `:MvcCrud [Model] [DbContext] [ControllerName]` | Scaffold a CRUD controller **and its five Razor views** from an EF model |
| `:MvcScaffold [generator] [args]` | Raw `dotnet aspnet-codegenerator`. `<Tab>` completes `controller`, `view`, `razorpage`, `identity`, `minimalapi`, `area`, `blazor`. No arguments lists the installed generators |
| `:MvcAlternate` | Jump between a controller action and its view, in both directions |
| `:DotnetSecrets [verb] [args]` | `dotnet user-secrets` on the web project (`init`, `list`, `set`, `remove`, `clear`; defaults to `list`) |
| `:DotnetDevCerts` | Create and trust the HTTPS development certificate |

#### `:MvcCrud` — the scaffolding shortcut

This is the CLI behind Visual Studio's *Add → New Scaffolded Item*. From
`Models/Product.cs`:

```vim
:MvcCrud
```

The model defaults to the type in the current buffer, and the `DbContext` is
**found by scanning for a class deriving from `DbContext`** rather than asked
for — matching the declaration, not the file name, so an
`AppDb : IdentityDbContext<ApplicationUser>` in `Data/AppDb.cs` is still
located. With several contexts in the solution you get a picker. Override
either explicitly:

```vim
:MvcCrud Product AppDb
:MvcCrud Product AppDb CatalogController   " override the controller name
```

The controller name is pluralised properly rather than by appending an `s`:
`Category → CategoriesController`, `Person → PeopleController`,
`Address → AddressesController`, `Branch → BranchesController`,
`Shelf → ShelvesController`, and `Photo → PhotosController` while
`Potato → PotatoesController`. That matters because the controller name is
baked into every generated route and redirect, so a `CategorysController` is
not something you want to rename by hand afterwards. Irregulars and the
`-o` exceptions live in `IRREGULAR_PLURALS` in `engine.core.dotnet`; pass a
third argument when it still reads wrong.

You get `Controllers/ProductsController.cs` plus `Views/Products/{Index,
Create,Edit,Details,Delete}.cshtml`, wired to `_Layout.cshtml` with jQuery
validation referenced in the form views.

##### What the generator needs before it will run

The scaffolder is unhelpful about its prerequisites: it surfaces **one** missing
thing per run, and **exits 0 on every one of these failures** while writing no
files. Discovering the set by trial costs a slow design-time build each time,
so `:MvcCrud` front-loads the checks.

Three package references, all added for you after a single confirmation:

| Package | Why |
| --- | --- |
| `Microsoft.VisualStudio.Web.CodeGeneration.Design` | The generator itself |
| `Microsoft.EntityFrameworkCore.Tools` | Reads the model and the `DbContext` |
| `Microsoft.EntityFrameworkCore.SqlServer` | **Required even if you use another provider.** Verified against a Sqlite-only project: the generator still refused with *"install the following Entity Framework core packages and try again: Microsoft.EntityFrameworkCore.SqlServer"*. Its provider check is hard-coded rather than read off the project, so the reference has to be present even though nothing uses it. |

And two things no package check can fix:

- **The `DbContext` must be registered in DI.** The generator boots your app's
  service provider to reach it, so without a
  `builder.Services.AddDbContext<AppDb>(...)` line in `Program.cs` it fails
  with `Unable to resolve service for type DbContextOptions<AppDb>` — which
  reads like an EF bug rather than the missing registration it is. `:MvcCrud`
  warns when `Program.cs` has no `AddDbContext` call, before paying for the
  build.
- **The project must compile.** Scaffolding runs a design-time build first, so
  fix `:DotnetBuild` before scaffolding.

#### `:MvcAlternate` — controller ↔ view

A controller action and its view are a pair, but they live in different trees
and nothing links them: `return View()` names the view by convention, not by
reference, so `gd` cannot help. `:MvcAlternate` walks that convention:

- **From a `.cs` controller**, with the cursor anywhere inside an action, it
  opens `Views/<Controller>/<Action>.cshtml`, falling back to
  `Views/Shared/<Action>.cshtml`. The enclosing action is found with
  treesitter, so attributes, properties and expression-bodied actions
  (`public IActionResult Index() => View();`) all resolve correctly — a
  backwards regex search lands on the attribute line about as often as the
  method.
- **From a view**, it opens `<Controller>Controller.cs` and jumps to the
  action, searching the project if the controller is not under `Controllers/`
  (MVC discovers controllers by base class, not by folder).
- **Areas work.** A file under `Areas/Admin/Controllers` pairs with
  `Areas/Admin/Views`, not the project root.
- When the action renders a differently-named view (`return View("Confirm")`),
  or the cursor is not in an action, you get a picker of that controller's
  views instead of a guess.

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
| `:DotnetInfo` | Show the resolved context: solution, project, web project, discovered `DbContext`es, EF project pair, the solution Roslyn selected, the **SDK version** and the path to every tool |
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
:DotnetNew mvc            " or: dotnet new mvc -o Shop.Web
:DotnetDevCerts           " once per machine, not per project
:DotnetWatch              " hot reload; leave it running in its split
```

`:DotnetWatch` is the ASP.NET inner loop: every save rebuilds and hot-reloads.
Keep it open in the bottom split and only restart it when you change
`Program.cs` or a `.csproj`.

### Model → migration → CRUD screens

The full MVC loop, which is the one worth memorising:

1. `Models/Product.cs`, then `:Skel` → a class with the right namespace.
2. Add `public DbSet<Product> Products => Set<Product>();` to the `DbContext`.
   (No context yet? `:Skel dbcontext`.)
3. Put the connection string where it belongs, outside git:
   ```vim
   :DotnetSecrets init
   :DotnetSecrets set ConnectionStrings:Default "Server=...;Database=Shop;..."
   ```
4. `:EfAdd AddProducts` then `:EfUpdate` — migration written and applied.
5. `:MvcCrud` from the model buffer — controller plus five views, generated.
6. `:MvcAlternate` to hop between the generated action and its view while you
   edit them.

Steps 4 and 5 are the two that used to mean leaving the editor.

### New layered solution

```sh
dotnet new sln -n Shop
dotnet new mvc -o src/Shop.Web
dotnet new classlib -o src/Shop.Data
dotnet sln add src/Shop.Web src/Shop.Data
dotnet add src/Shop.Web reference src/Shop.Data
```

Open any file in the tree; Roslyn finds the solution on its own, and the
`:Dotnet*` / `:Ef*` / `:Mvc*` commands resolve the web project themselves — so
`:DotnetRun` from a file in `Shop.Data` still runs `Shop.Web`, and `:EfAdd`
from the same file still uses `Shop.Web` as its startup project. Confirm with
`:DotnetInfo` whenever something lands somewhere unexpected.

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
lua/engine/plugins/conform.lua          conform: cs -> csharpier
lua/engine/plugins/treesitter.lua       c_sharp, razor, xml and sql parsers
```

---

## Troubleshooting

**Nothing works at all; `dotnet --info` says "No SDKs were found".** Only a
runtime is installed or `DOTNET_ROOT` points at the wrong architecture. Run
`dotnet --list-sdks`; if it is empty, rerun the arm64 SDK install command
above. `dotnet --version` can still report a host version without an SDK.

**`NETSDK1073` on an MVC project.** The selected SDK is incomplete or does not
contain the requested ASP.NET targeting pack. Confirm the project's target
framework, run `dotnet --list-sdks`, and reinstall the matching arm64 SDK.

**No completion or diagnostics.** `:DotnetInfo` — if `roslyn server` shows
`NOT FOUND`, the global tool is missing; reinstall it (see above).
`:checkhealth roslyn` shows which solution was selected. `:LspLog` has the rest.

**`.cshtml` has no highlighting.** The razor parser is not compiled:
`:TSInstall razor`. It is generated at install time, so it needs the
`tree-sitter` CLI and node on `$PATH`.

**No HTML completion inside a view.** Razor support in roslyn.nvim works by
co-hosting: the server hands the markup regions to a *separate* language server
that must be named exactly `html`. That is `vscode-html-language-server`, which
mason installs and mason-lspconfig auto-enables — so if view completion is
dead, check `:Mason` for `html-lsp` first. Razor also needs
`roslyn-language-server` >= `5.8.0-1.26262.10`.

**`:MvcCrud` wrote no files but reported no error.** Expected, unfortunately:
the scaffolder exits 0 on most of its failures. Read the terminal split it
opened — the real message is in there. The three usual causes are a missing
package, an unregistered `DbContext`, or a project that does not compile; all
three are covered under [what the generator
needs](#what-the-generator-needs-before-it-will-run).

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

## Treesitter

`lua/engine/plugins/treesitter.lua` once pinned `branch = "master"` but called
`require("nvim-treesitter").setup{...}` — the wrong entry point on that branch,
which silently discarded `highlight` and `ensure_installed`. No parser had ever
been installed and highlighting was off for every language. The fix was one
line (`require("nvim-treesitter.configs")`); see
[`doc/frontend.md`](frontend.md).

Four parsers matter here:

| Parser | Covers |
| --- | --- |
| `c_sharp` | `.cs`, layered under Roslyn's semantic tokens |
| `razor` | `.cshtml` and `.razor` |
| `xml` | `.csproj`, `.props`, `.targets`, `.slnx`, `nuget.config` |
| `sql` | the scripts `:EfScript` generates |

**`razor` is what makes a view readable.** Without it an MVC view had *no
highlighting at all*: Neovim ships no `razor` syntax file, `engine.core.dotnet`
deliberately maps `.cshtml` away from `html` to its own `razor` filetype (so
that Roslyn attaches and so C# constructs are not lost), and that left nothing
to colour the buffer. The parser injects `html` into the markup and applies the
`c_sharp` queries to the `@` regions, so `@model`, `@{ }` blocks, `@foreach`
and the surrounding markup all highlight as themselves.

Unlike the other three, the razor parser is **generated at install time** — its
upstream repo ([`tris203/tree-sitter-razor`](https://github.com/tris203/tree-sitter-razor))
ships no pre-generated `parser.c` — so `:TSInstall razor` needs the
`tree-sitter` CLI and node on `$PATH`. Install native Apple Silicon builds
(for example with `brew install tree-sitter node`) before compiling it.

One gap: **nvim-ts-autotag does not auto-close tags in a view.** It matches
tags through a per-filetype set of node-name patterns in its own
`config/ft.lua` and ships none for razor; the razor grammar names its nodes
differently from the html one, so aliasing `razor → html` would register a
config whose patterns never match. Closing tags in `.cshtml` stay manual.
