" C# buffer options.
"
" The global defaults in lua/engine/core/options.lua are 8-wide hard tabs,
" which is right for C but wrong for C#: every .NET convention, the SDK
" templates and CSharpier all use 4 spaces. Match them, otherwise format-on-
" save reindents every line you touch and your diffs are noise.

setlocal expandtab
setlocal tabstop=4
setlocal shiftwidth=4
setlocal softtabstop=4

setlocal textwidth=0

" The global foldmarker is the C++ spelling (#pragma region). C# writes plain
" #region / #endregion, so fold on those instead.
setlocal foldmethod=marker
setlocal foldmarker=#region,#endregion

setlocal commentstring=//\ %s
setlocal comments=sO:*\ -,mO:*\ \ ,exO:*/,s1:/*,mb:*,ex:*/,://

" gf on a using directive or a type name has nothing to resolve to, but gf on
" a path in a csproj/appsettings comment does; keep .cs in suffixesadd so
" `gf` over a bare type name at least tries Foo.cs.
setlocal suffixesadd=.cs

" Generic type arguments read better when % jumps across them.
setlocal matchpairs+=<:>
