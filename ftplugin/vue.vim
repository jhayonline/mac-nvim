" Vue 3 single-file component buffer options.
"
" Keep template, <script setup lang="ts">, and style blocks aligned with the
" two-space output produced by Prettier.

setlocal expandtab
setlocal tabstop=2
setlocal shiftwidth=2
setlocal softtabstop=2

setlocal textwidth=0

" SFCs are naturally nested; start folds open so structure is available
" without hiding code on first load.
setlocal foldmethod=indent
setlocal foldlevel=99

" Make gf useful for local component and composable imports.
setlocal suffixesadd=.vue,.ts,.tsx,.js,.jsx,.mjs,.cjs,.json

setlocal matchpairs+=<:>
