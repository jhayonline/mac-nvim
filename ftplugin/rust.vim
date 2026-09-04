" Rust buffer options.
"
" rustfmt is non-negotiable about 4 spaces, so match it rather than let the
" global 8-wide hard tabs fight the formatter on every save.

setlocal expandtab
setlocal tabstop=4
setlocal shiftwidth=4
setlocal softtabstop=4

setlocal textwidth=0

" The global foldmarker is the C++ '#pragma region' spelling. Rust has no
" region syntax, so fold on syntax structure instead.
setlocal foldmethod=indent
setlocal foldlevel=99

setlocal commentstring=//\ %s
setlocal matchpairs+=<:>
