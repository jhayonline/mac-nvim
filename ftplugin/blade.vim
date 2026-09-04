" Blade template buffer options.
"
" Blade is HTML with @directives and {{ }} echoes. It follows the HTML
" convention of 4 spaces, which is also what blade-formatter emits.

setlocal expandtab
setlocal tabstop=4
setlocal shiftwidth=4
setlocal softtabstop=4

setlocal textwidth=0

setlocal foldmethod=indent
setlocal foldlevel=99

" Blade comments are {{-- --}}, which is neither the HTML nor the PHP form.
setlocal commentstring={{--\ %s\ --}}

setlocal matchpairs+=<:>
