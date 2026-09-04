# PHP — Laravel and vanilla

PHP 8.4 with Composer, intelephense configured with the framework stubs that
make Laravel resolve, Blade as a real filetype with its own treesitter parser
and Tailwind support, and `artisan` driven from inside Neovim.

Laravel is treated as a **superset, not a requirement**. There are three levels
of project and everything degrades to whichever it finds:

| You have | Detected by | You get |
| --- | --- | --- |
| A Laravel app | an `artisan` file | `:Artisan*`, plus everything below |
| A Composer project | `composer.json` | `:Composer`, `vendor/bin` tooling, plus below |
| A loose `.php` file | neither | `:Php*`, formatting, and intelephense in single-file mode |

A `.php` file sitting on its own on the Desktop still gets completion,
diagnostics, `php -l` checking and format-on-save.

---

## What is installed, and where

| Component | Version | Location |
| --- | --- | --- |
| PHP | 8.4.25 | `/usr/local/opt/php@8.4/bin` (keg-only) |
| Composer | 2.10.3 | `/usr/local/bin/composer` |
| Laravel installer | 5.32 | `~/.composer/vendor/bin/laravel` |
| intelephense | Mason | `~/.local/share/nvim/mason/bin` |
| blade-formatter | Mason | `~/.local/share/nvim/mason/bin` |
| Pint | 1.30.5 | `~/.composer/vendor/bin` (and per-project `vendor/bin/pint`) |
| PHP CS Fixer | 3.95.23 | `~/.composer/vendor/bin` |

`~/.zshrc` gained:

```sh
export PATH="/usr/local/opt/php@8.4/bin:/usr/local/opt/php@8.4/sbin:$PATH"
export PATH="$HOME/.composer/vendor/bin:$PATH"
```

`engine.core.php` also patches both into `vim.env.PATH` at startup, so nvim
launched from a GUI launcher — which never reads `.zshrc` — still finds them.

### Why not plain `brew install php`

**Homebrew has moved Intel macOS to Tier 3 and no longer ships bottles for it.**
`brew install php composer` fails outright with `no bottle available!`, and
building PHP from source takes the better part of an hour.

PHP therefore comes from the `shivammathur/php` tap, which does publish bottles
for this configuration, and Composer from its official installer. Note this
affects **every** future `brew install` on this machine, not just PHP — expect
either a tap with its own bottles or a source build.

`php@8.4` is keg-only, which is why it needs the explicit `PATH` entry above.

### Reinstalling

```sh
brew tap shivammathur/php
brew install shivammathur/php/php@8.4
php -r "copy('https://getcomposer.org/installer','composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer && rm composer-setup.php
composer global require laravel/installer
nvim --headless -c 'MasonInstall intelephense blade-formatter' -c qa
```

---

## intelephense and the Laravel stubs

This is the setting that makes the difference between "usable" and "a wall of
red". Without the framework stubs, every facade (`Route::`, `Schema::`,
`Auth::`, `DB::`) and every global helper (`route()`, `view()`, `collect()`,
`dd()`) is an undefined symbol.

`lspconfig.lua` now passes the full `stubs` list, plus:

- `files.maxSize = 5000000` — Laravel apps are large and the default 1 MB cap
  silently skips the bigger vendor files.
- `environment.includePaths` pointing at `barryvdh/laravel-ide-helper`, so if
  you generate `_ide_helper.php` it gets picked up automatically.
- `completion.insertUseDeclaration` — completing a class adds its `use` line.

Verified: a controller using `Route`, `User::query()`, `route()` and `view()`
produces **zero** undefined-symbol errors.

### Even better model completion

Laravel models are built from magic properties that no static analyser can see.
For real column completion on `$user->email`:

```sh
composer require --dev barryvdh/laravel-ide-helper
php artisan ide-helper:generate
php artisan ide-helper:models --nowrite   # writes _ide_helper_models.php
```

intelephense is already configured to read those files.

### intelephense licensing

The free tier covers completion, diagnostics, hover and go-to-definition — what
you'll use most. Rename across a project, find-all-references and a few other
features are premium. If you hit the limits, a key goes in
`~/.config/intelephense/licence.txt`; no config change is needed.

---

## Blade

Neovim already maps `*.blade.php` to the `blade` filetype. What was missing is
everything after that, and it's now in place:

- **Treesitter.** The `blade` parser is compiled and highlighting, so
  `@if`/`@foreach` directives and `{{ }}` echoes are distinct from the HTML.
- **Tailwind.** The `tailwindcss` server attaches to Blade buffers, with
  `includeLanguages` mapping `blade → html` so it extracts classes correctly.
  ~23k completions, same as in `.tsx`.
- **Emmet.** `div.flex.gap-2` expansion works in templates.
- **Formatting.** `blade-formatter` runs on save at 4 spaces with
  `--wrap-attributes preserve-aligned`.
- **`ftplugin/blade.vim`** sets 4-space indent and the correct
  `commentstring` — `{{-- %s --}}`, which is neither the HTML nor the PHP form,
  so commenting with your usual mapping now produces valid Blade.

Tailwind deliberately does **not** attach to plain `.php`. Classes live in
templates; attaching there would start a Tailwind client on every controller
and model for no gain.

> Tailwind needs `node_modules/tailwindcss` to exist. `composer create-project`
> does not run `npm install`, so do that once in a new app.

---

## Commands

### artisan

| Command | Action |
| --- | --- |
| `:Artisan <cmd>` | Any artisan command. `<Tab>` completes from the app's real `artisan list` |
| `:ArtisanMake <type> <Name>` | `:ArtisanMake controller PostController` — `<Tab>` completes the type |
| `:ArtisanServe` | Development server |
| `:ArtisanTinker` | Tinker REPL |
| `:ArtisanMigrate [args]` | `:ArtisanMigrate fresh --seed`, `rollback`, `status`, … |
| `:ArtisanRoutes` | `route:list`, trimmed to method/uri/name/action |
| `:ArtisanQueue [args]` | `queue:work` |
| `:ArtisanTest [args]` | Test suite — **failures go to the quickfix list** |
| `:ArtisanReload` | Re-read the command list after adding a package |

`<Tab>` completion is real: it shells out to `php artisan list --raw` once per
session and caches the result, so it includes commands from whatever packages
the app has installed. `:ArtisanReload` refreshes it.

Everything except `:ArtisanTest` opens a terminal split you can `Ctrl-C`, since
`serve`, `tinker` and `queue:work` are interactive or long-lived.
`:ArtisanTest` runs async and puts PHPUnit/Pest failure locations into
`:copen` — ANSI colour is stripped first, which otherwise defeats every
errorformat pattern.

### Vanilla PHP

These work with no `artisan` and no `composer.json`, and upgrade themselves
when those exist:

| Command | Loose file / Composer project | Inside Laravel |
| --- | --- | --- |
| `:PhpRun [args]` | `php <thisfile>` | same |
| `:PhpLint` | `php -l` → quickfix | same |
| `:PhpServe [addr]` | `php -S localhost:8000 -t <root>` | `artisan serve` |
| `:PhpTest [args]` | `vendor/bin/pest`, then `vendor/bin/phpunit`, then global | `artisan test` |
| `:PhpRepl` | `php -a` | `artisan tinker` |
| `:PhpInfo` | Resolved context and tool paths | same |

`:PhpLint` is the compiler's own verdict rather than the language server's —
useful on the rare occasion the two disagree, and it's how you check a file
parses before running it. Duplicate entries are collapsed (`php -l` prints each
error to both stdout and stderr, spelled differently on each).

### Composer, formatting, diagnostics

| Command | Action |
| --- | --- |
| `:Composer <cmd>` | Any composer command, `<Tab>` completes the common ones |
| `:Pint` | Run Laravel Pint over the project |
| `:LaravelInfo` | Resolved context: composer root, Laravel root and version, tool paths |
| `:PhpInfo` | Same, but works outside Laravel too |
| `:Format`, `:FormatToggle`, `:FormatInfo` | Shared formatting commands |

`:LaravelInfo` is the first thing to run when something behaves oddly.

---

## Formatting

The formatter is chosen **per project**, because the two are not
interchangeable:

| Project has | Formatter used | Why |
| --- | --- | --- |
| `.php-cs-fixer.php` / `.dist.php` | **php-cs-fixer** | You've committed to a rule set; it wins |
| Anything else, incl. Laravel | **pint** | Zero config, and it runs on a loose file with no project at all |

Pint resolves `vendor/bin/pint` first so a Laravel app uses its own pinned
version (byte-identical with CI), and falls back to the global 1.30.5.

This matters for vanilla PHP specifically: conform's `php-cs-fixer` roots
itself at `composer.json` and therefore **cannot run outside a project** — which
is exactly why it isn't the default. Pint has no such restriction.

`blade` files go to **blade-formatter**.

### A note on timing

PHP formatters pay an interpreter start-up cost on every invocation — pint
measures ~1500 ms here, blade-formatter ~1250 ms, and more on the first run of
a session. The format-on-save budget for `php` and `blade` is therefore **8
seconds**, not the 3 used elsewhere.

That is not paranoia: at 3 seconds the first save in a project silently
exceeded the timeout, conform gave up, and the file was written unformatted
with no visible error. If a format ever does fail now, `notify_on_error` makes
it say so.

`ftplugin/php.vim` sets 4 spaces per PSR-12, which is what both formatters
enforce.

---

## Typical workflow

```sh
laravel new blog        # or: composer create-project laravel/laravel blog
cd blog && npm install  # Tailwind needs this
```

Then in Neovim:

```vim
:ArtisanMake model Post -mfs      " model + migration + factory + seeder
:ArtisanMake controller PostController --resource
:ArtisanMigrate
:ArtisanServe
```

`:ArtisanRoutes` to check what you wired up, `:ArtisanTest` to run the suite,
`:ArtisanTinker` to poke at models.

---

## Where things live

```
lua/engine/core/php.lua                :Artisan*/:Php*/:Composer/:Pint, PATH, filetypes
lua/engine/plugins/lsp/lspconfig.lua   intelephense + stubs, tailwindcss, emmet
lua/engine/plugins/conform.lua         pint and blade-formatter on save
lua/engine/plugins/treesitter.lua      php, phpdoc parsers (blade added separately)
ftplugin/php.vim, ftplugin/blade.vim   indent, commentstring, folding
```

`.env`, `.env.example` and any `.env.*` are mapped to `sh` so they highlight,
and `artisan` itself is mapped to `php`.

---

## Troubleshooting

**Facades show as undefined.** The stubs aren't loading. `:LspRestart`, and
confirm `:LaravelInfo` finds the Laravel root (it looks for the `artisan` file).

**Model properties don't complete.** Expected without `laravel-ide-helper` —
they're magic properties. See above.

**No Tailwind completion in Blade.** Run `npm install` in the app.

**`:Artisan` completes nothing.** It needs `php` on `PATH` and an `artisan`
file above the buffer. Check `:LaravelInfo`, then `:ArtisanReload`.

**Pint not found.** It's installed globally at `~/.composer/vendor/bin/pint`,
so this should only happen if that dropped off `PATH`. Check `:PhpInfo`.

**A file saved without being formatted.** Almost always a timeout. `:FormatInfo`
shows which formatter applies and whether it was found; the conform log at
`~/.local/state/nvim/conform.log` records timeouts explicitly.

**Blade file has no highlighting.** `:TSInstall blade`.
