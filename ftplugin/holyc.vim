" HolyC filetype settings (hcc -- holyc-lang.com)

if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

let s:cpo_save = &cpo
set cpo&vim

setlocal commentstring=//\ %s
setlocal comments=sO:*\ -,mO:*\ \ ,exO:*/,s1:/*,mb:*,ex:*/,://

" HolyC is brace-and-semicolon C-shaped, so cindent reads it correctly.
setlocal cindent
setlocal cinoptions=:0,l1,t0,g0,(0

" `gf` and `[i` over #include lines. hcc resolves headers from
" <install-dir>/include. Prefer Apple Silicon Homebrew and retain the
" traditional /usr/local location for manual hcc installs.
setlocal include=^\\s*#\\s*include
setlocal define=^\\s*#\\s*define
setlocal suffixesadd=.HC,.HH
setlocal path+=/opt/homebrew/include,/usr/local/include

let b:undo_ftplugin = "setlocal commentstring< comments< cindent< cinoptions<"
      \ . " include< define< suffixesadd< path<"

let &cpo = s:cpo_save
unlet s:cpo_save
