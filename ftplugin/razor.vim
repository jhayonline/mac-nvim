" Razor (.cshtml) buffer options.
"
" Razor is HTML with C# interleaved, so it follows the HTML convention of
" 4-space indentation rather than the global 8-wide hard tabs. The Roslyn
" language server (see lua/engine/plugins/lsp/roslyn.lua) provides completion
" and diagnostics inside both the markup and the @{ } blocks.

setlocal expandtab
setlocal tabstop=4
setlocal shiftwidth=4
setlocal softtabstop=4

setlocal textwidth=0

" Razor has no #region, and the global #pragma region marker never matches
" here; indent folding is the useful choice for nested markup.
setlocal foldmethod=indent
setlocal foldlevel=99

" Razor comments are @* ... *@, which is neither the HTML nor the C# form.
setlocal commentstring=@*\ %s\ *@

setlocal matchpairs+=<:>
