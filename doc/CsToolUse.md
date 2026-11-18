# C# tooling — how to actually use it

A task-oriented companion to [`doc/csharp.md`](csharp.md). That file explains
*how the setup works and why*; this one is the thing to keep open for the first
week: what to press, in what order, to get real work done.

The workflow matches the current commands and was originally validated against
a real `dotnet new mvc` app. Run the M5 smoke checks in the README after the
new SDK and tools are installed.

---

## The one-screen cheat sheet

### Code intelligence (any `.cs` or `.cshtml` buffer)

| Key | Does |
| --- | --- |
| `K` | Hover docs for the symbol under the cursor |
| `gd` / `gD` | Go to definition / declaration |
| `gr` | References (Telescope) |
| `gi` / `gt` | Implementations / type definitions |
| `<leader>ca` | Code actions — **this is your "add using", "generate constructor", "implement interface"** |
| `<leader>rn` | Rename across the whole solution |
| `<leader>dd` | Diagnostics for this buffer |
| `<leader>dl` | Floating detail for the diagnostic on this line |
| `[d` / `]d` | Previous / next diagnostic |
| `<leader>ci` / `<leader>co` | Incoming / outgoing calls |
| `<leader>rs` | Restart the language server |

**Code lens** shows a reference count above every member — informational, not
clickable. `0 references` over a method you thought was wired up is the
cheapest dead-code check there is.

> Roslyn can also emit *Run Test* / *Debug Test* lenses, and they are turned
> **off** here on purpose: their command is `dotnet.test.run`, a **VS Code**
> command contributed by the C# extension, not an LSP one. Nothing in Neovim
> implements it, so those lenses rendered and then did nothing when invoked.
> `:DotnetTestHere` is the working equivalent.

`<leader>` is the spacebar. `<leader>ca` is the one to build a habit around —
in C# most of what an IDE "does for you" is a code action.

### Build and run

| Command | Does |
| --- | --- |
| `:DotnetBuild` | Build → errors land in the quickfix list |
| `:DotnetRun` | Run the project |
| `:DotnetWatch` | **Run with hot reload — the ASP.NET inner loop** |
| `:DotnetTest` | Run the tests |
| `:DotnetTestHere` | **Run only the test under the cursor** |
| `:DotnetRestore` / `:DotnetClean` | Restore / clean |
| `:DotnetAdd <package>` | Add a NuGet package to this project |
| `:DotnetNew <template>` | Scaffold from a template (`<Tab>` completes) |
| `:DotnetInfo` | **What am I actually pointed at?** Run this first when anything is odd |

After `:DotnetBuild`, walk the errors with `:cnext` / `:cprev`, and `:copen` to
see the list. On success the quickfix window closes itself.

### MVC

| Command | Does |
| --- | --- |
| `:MvcCrud` | Controller + 5 views from the model in the current buffer |
| `:MvcAlternate` | Jump controller action ↔ its Razor view |
| `:MvcScaffold …` | Raw `aspnet-codegenerator` |
| `:DotnetSecrets set <k> <v>` | Connection strings, out of git |
| `:DotnetDevCerts` | Trust the HTTPS dev certificate (once per machine) |

### EF Core

| Command | Does |
| --- | --- |
| `:EfAdd <Name>` | Create a migration |
| `:EfUpdate` | Apply migrations (`:EfUpdate 0` reverts everything) |
| `:EfList` / `:EfRemove` | List / drop the last migration |
| `:EfScript` | Idempotent SQL script |
| `:EfScaffold "<conn>"` | Generate models *from* an existing database |

### Debugging (`nvim-dap` + netcoredbg)

| Key | Does |
| --- | --- |
| `<leader>db` | Toggle breakpoint |
| `<leader>dc` | Start / continue |
| `<leader>ds` / `<leader>di` / `<leader>do` | Step over / into / out |
| `<leader>dt` | Terminate |

**`:DotnetBuild` before you debug.** The launcher looks for a built
`bin/Debug/<tfm>/*.dll`; it cannot attach to source.

---

## Part 1 — a basic C# program

### Start a console app

Open a terminal where you want it (or use `:DotnetNew`, which runs in Neovim's
current directory):

```vim
:DotnetNew console -o Hello
```

Then open `Hello/Program.cs`. Roslyn attaches on its own — the first time in a
project it takes a few seconds while it restores and loads, and that is normal.

```vim
:DotnetRun
```

A terminal splits open at the bottom with the output. `i` to interact with it,
`<C-\><C-n>` to get back to normal mode, `:q` to close it.

### Add a class

Create the file first, then let `:Skel` fill it in — it reads your
`.csproj` and the folder path to get the namespace right:

```vim
:e Models/Product.cs
:Skel
```

You get:

```csharp
namespace Hello.Models;

public class Product
{
}
```

`:Skel` **infers the kind from the filename**, which is most of its value:

| Filename | You get |
| --- | --- |
| `Product.cs` | a class |
| `IRepository.cs` | an interface |
| `ProductsController.cs` | an MVC controller (`: Controller`) — or `: ControllerBase` under `Api/` |
| `AppDbContext.cs` | an EF `DbContext` |
| `ProductTests.cs` | an xUnit test class |
| `NotFoundException.cs` | an exception with the three standard constructors |
| `ProductService.cs`, `ProductRepository.cs` | an interface **and** its implementation |
| `ProductViewModel.cs`, `CreateProductRequest.cs` | a positional `record` |
| `CacheOptions.cs`, `AppSettings.cs` | an options class |
| `StringExtensions.cs` | a `static class` for extension methods |
| `AuthMiddleware.cs` | ASP.NET middleware, with the `RequestDelegate` ctor |
| `ColorAttribute.cs` | a `sealed class : Attribute` |

Override it by naming a template: `:Skel record`, `:Skel enum`, `:Skel struct`,
`:Skel sealed`, `:Skel apicontroller`, `:Skel minimalapi`, `:Skel test`,
`:Skel attribute`. `<Tab>` lists them all.

### The edit loop

Just type. On every save CSharpier reformats the file — so stop hand-aligning
anything, and let `<leader>ca` write the boilerplate:

- Using a type you have not imported? Type it anyway; completion offers
  unimported types and `<leader>ca` adds the `using`.
- `public Product(string name)` — `<leader>ca` on the class generates the
  constructor, or the properties from a constructor you already wrote.
- Red squiggle anywhere? `<leader>dl` to read it, `<leader>ca` to fix it.

Then:

```vim
:DotnetBuild      " errors into quickfix, :cnext to walk them
:DotnetRun
```

### Add tests

```vim
:DotnetNew xunit -o Hello.Tests
```

Reference the project under test, then run:

```vim
:DotnetAdd ...          " for packages
" project references are a shell command:
"   dotnet add Hello.Tests reference Hello
:DotnetTest
```

With a solution file present, `:DotnetTest` runs every test project at once.

To run **one** test, put the cursor in it and:

```vim
:DotnetTestHere
```

It builds a `dotnet test --filter FullyQualifiedName~Class.Method` from the
cursor position using treesitter, so:

- inside a test method → just that test
- anywhere else in the class → that whole class
- outside a class → it tells you so instead of running the suite

Because `FullyQualifiedName~` is a substring match, a method named `Add` also
matches `AddTwice`. When that bites, pass an exact filter yourself:

```vim
:DotnetTest --filter "FullyQualifiedName=Hello.Tests.CalculatorTests.Add"
```

To **debug** a single test, there is no one-key path: set a breakpoint in the
test, then `:DotnetBuild` and attach with `<leader>dc` → *Attach to process*
against the test host.

### A multi-project solution

Roslyn is much happier with a solution file, and so are the `:Dotnet*`
commands — they resolve the solution and act on all of it:

```sh
dotnet new sln -n Playground
dotnet new console -o Hello
dotnet new xunit -o Hello.Tests
dotnet sln add Hello Hello.Tests
dotnet add Hello.Tests reference Hello
```

Open any file in the tree afterwards; nothing else to configure. Confirm with
`:DotnetInfo` that `solution:` is filled in.

### Debug it

1. `:DotnetBuild` — required; the debugger launches a built DLL.
2. `<leader>db` on the line you care about.
3. `<leader>dc`, then pick **Launch**.
4. Step with `<leader>ds` / `<leader>di` / `<leader>do`, `<leader>dt` to stop.

---

## Part 2 — ASP.NET Core MVC, start to finish

This is the whole loop: new app → model → database → CRUD screens. It is worth
doing once verbatim.

### 0. Once per machine

```vim
:DotnetDevCerts
```

The MVC template serves `https://`, so without a trusted certificate every new
app opens on a browser warning. Approve the macOS Keychain trust prompt; no
Neovim restart or Linux certificate environment variable is required.

### 1. Create the app

```vim
:DotnetNew mvc -o Shop.Web
```

Open `Shop.Web/Program.cs`, then start the inner loop and **leave it running**
in its split:

```vim
:DotnetWatch
```

Every save now rebuilds and hot-reloads. Visit the URL it prints. You only need
to restart it when you change `Program.cs` or the `.csproj`.

### 2. A model

```vim
:e Models/Product.cs
:Skel
```

```csharp
namespace Shop.Web.Models;

public class Product
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public decimal Price { get; set; }
}
```

`Id` is the convention EF uses for the primary key — keep it.

### 3. A DbContext

```vim
:e Data/AppDb.cs
:Skel
```

The filename ends in `Context`/`DbContext` under `Data/`, so you get an EF
context. Add a `DbSet` per model:

```csharp
public DbSet<Product> Products => Set<Product>();
```

### 4. Packages and registration

```vim
:DotnetAdd Microsoft.EntityFrameworkCore.Sqlite
```

Then register it in `Program.cs` — **this step is not optional**, scaffolding
and migrations both boot your app's service provider to find the context:

```csharp
builder.Services.AddDbContext<AppDb>(o =>
    o.UseSqlite(builder.Configuration.GetConnectionString("Default")));
```

### 5. The connection string, out of git

```vim
:DotnetSecrets init
:DotnetSecrets set ConnectionStrings:Default "Data Source=shop.db"
```

User secrets live in `~/.microsoft/usersecrets/`, outside the repo, and the
Development environment reads them ahead of `appsettings.json`. Never commit a
connection string to `appsettings.json`.

`:DotnetSecrets` on its own lists what is set.

### 6. Create the database

```vim
:EfAdd InitialCreate
:EfUpdate
```

`:EfAdd` writes `Migrations/<timestamp>_InitialCreate.cs`; `:EfUpdate` applies
it. In a layered solution the `--project` / `--startup-project` split is worked
out for you — `:DotnetInfo` shows which pair it picked.

### 7. CRUD screens, generated

From the model buffer:

```vim
:e Models/Product.cs
:MvcCrud
```

The model comes from the buffer and the `DbContext` is found by scanning, so
usually there is nothing to type. First run in a project asks once to add three
packages — say yes.

Out comes:

```
Controllers/ProductsController.cs
Views/Products/Index.cshtml
Views/Products/Create.cshtml
Views/Products/Edit.cshtml
Views/Products/Details.cshtml
Views/Products/Delete.cshtml
```

Fully wired to `_Layout.cshtml`, with validation scripts in the form views.
Visit `/Products`.

Naming is handled properly: `Category → CategoriesController`,
`Person → PeopleController`. Override it when you want something else:

```vim
:MvcCrud Product AppDb CatalogController
```

> **`:MvcCrud` finished but wrote nothing?** The scaffolder exits successfully
> even when it fails, so **read the terminal split** — the real message is in
> there. It is nearly always one of: the project does not compile (`:DotnetBuild`
> first), or `AddDbContext` is missing from `Program.cs` (step 4).

### 8. Edit the generated code

This is where `:MvcAlternate` earns its keep. In `ProductsController.cs`, put
the cursor anywhere inside an action and press:

```vim
:MvcAlternate
```

You land in that action's `.cshtml`. Run it again to go back — and you land on
the action, not line 1. It understands `Views/Shared/`, areas
(`Areas/Admin/...`), and expression-bodied actions.

Worth mapping, since you will use it constantly:

```lua
vim.keymap.set("n", "<leader>mv", "<cmd>MvcAlternate<cr>", { desc = "MVC: action <-> view" })
```

### 9. Changing the model later

The loop you will repeat for the rest of the project:

1. Edit the model.
2. `:EfAdd AddProductSku`
3. `:EfUpdate`
4. Adjust the views by hand (do **not** re-scaffold over edited views — it
   overwrites them).

`dotnet watch` picks up the rest as you save.

---

## Part 3 — the daily loop, condensed

Once a project exists, a normal session is just:

```vim
:DotnetWatch          " once, leave it running
```

then, repeatedly:

| Situation | Do |
| --- | --- |
| Writing code | type; save formats it |
| Need a using / constructor / interface impl | `<leader>ca` |
| What is this? | `K`, `gd`, `gr` |
| Renaming something | `<leader>rn` — solution-wide, safe |
| Something is red | `<leader>dl`, then `<leader>ca` |
| Did it compile? | `:DotnetBuild`, `:cnext` through errors |
| Changed a model | `:EfAdd <Name>` → `:EfUpdate` |
| New entity needs screens | `:MvcCrud` |
| Hopping action ↔ view | `:MvcAlternate` |
| Need to inspect state | `<leader>db`, `:DotnetBuild`, `<leader>dc` |

---

## Part 4 — debugging an MVC app

1. `:DotnetBuild`
2. `<leader>db` in the controller action.
3. `<leader>dc` and choose **Launch (ASP.NET Development)** — that config sets
   `ASPNETCORE_ENVIRONMENT=Development`, which is what gives you
   `appsettings.Development.json`, user secrets and the developer exception
   page. The plain **Launch** config does not.
4. Hit the route in your browser; execution stops on the breakpoint.

To debug a `dotnet watch` session you already have running, pick **Attach to
process** instead and choose the `dotnet` process from the list.

---

## Part 5 — when something is wrong

Run `:DotnetInfo` first, always. It prints the SDK version, the resolved
solution/project/web project, the discovered `DbContext`es, the EF project
pair, and the path to every tool.

| Symptom | Cause |
| --- | --- |
| No completion, no errors, nothing | Check `roslyn server:` in `:DotnetInfo`. Then `:Roslyn target` to pick the right solution. `<leader>rs` restarts the server. |
| First open of a solution is slow | Normal. Roslyn restores and loads every project before diagnostics settle. |
| Wrong project being built or run | `:DotnetInfo`. `:DotnetRun` needs a single project and falls back to the web project from a class library. |
| Migration landed in the wrong project | `:DotnetInfo` shows the pair; pin with `:EfProject` / `:EfStartupProject`. |
| `.cshtml` has no colour | `:TSInstall razor` |
| Tags do not auto-close in a view | Known gap, no razor support upstream. Manual in `.cshtml`. |
| Format on save stopped | `:FormatInfo` shows what applies; `:DotnetFormatToggle` toggles C#. |
| `NETSDK1073` | `dotnet --list-sdks`; reinstall the arm64 SDK if its ASP.NET targeting pack is missing |
| Debugger will not start | `:DotnetBuild` first — it needs a built DLL. |

---

## Reference

- [`doc/csharp.md`](csharp.md) — how the setup works, the Roslyn settings, the
  full command tables, install and troubleshooting.
- `:DotnetInfo` — the resolved state of the current buffer.
- `:FormatInfo` — which formatter applies here.
- `:checkhealth roslyn` — which solution the server selected.
