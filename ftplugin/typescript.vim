" typescript buffer options.
"
" The global default in lua/engine/core/options.lua is 8-wide hard tabs, which
" is right for C and wrong here: prettier emits 2 spaces and every React
" codebase follows it. Anything else means the formatter rewrites each line you
" touch and your diffs fill with whitespace.

setlocal expandtab
setlocal tabstop=2
setlocal shiftwidth=2
setlocal softtabstop=2

setlocal textwidth=0

" JSX/TSX nests deeply; indent folding is the only thing that fits, and the
" global '#pragma region' foldmarker never matches here.
setlocal foldmethod=indent
setlocal foldlevel=99

" So gf works on `import Button from "./Button"` and on "@/components/Button".
" (No 'include' pattern: an unescaped | in a :setlocal value is parsed as a
" command separator, and escaping it through both the option parser and the
" regex is more trouble than [i is worth here.)
setlocal suffixesadd=.ts,.tsx,.js,.jsx,.mjs,.cjs,.json

setlocal matchpairs+=<:>
