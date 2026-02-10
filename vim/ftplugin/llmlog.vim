" Filetype plugin for llmlog files
" Sets up folding and read-only viewing

setlocal foldmethod=marker
setlocal foldenable
setlocal foldlevel=0
setlocal nomodifiable
setlocal readonly

" Close all folds by default
normal! zM

" Keybindings for navigation
nnoremap <buffer> <Tab> zj
nnoremap <buffer> <S-Tab> zk
nnoremap <buffer> <CR> za
