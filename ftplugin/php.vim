" PHP buffer options.
"
" PSR-12 -- which Laravel Pint enforces -- mandates 4 spaces and no hard tabs.

setlocal expandtab
setlocal tabstop=4
setlocal shiftwidth=4
setlocal softtabstop=4

setlocal textwidth=0

setlocal foldmethod=indent
setlocal foldlevel=99

setlocal commentstring=//\ %s

" Namespaced class names contain backslashes; keep them in a single `*` jump.
setlocal iskeyword+=\\
setlocal suffixesadd=.php
