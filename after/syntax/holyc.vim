" Sourced right after syntax/holyc.vim, which is what makes this the correct
" place for it: loading a syntax file clears the buffer's syntax first, so
" keywords added from a FileType autocmd can be wiped depending on callback
" order. Here the timing is guaranteed and synchronous.
"
" Adds the class/union tags declared in this buffer as a type group -- hcc's
" server exposes no semantic tokens, so nothing else knows those names.
lua require("engine.core.holyc").refresh_user_types(vim.api.nvim_get_current_buf())
