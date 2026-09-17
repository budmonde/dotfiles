if !has('nvim')
    augroup fugitive_commit_folding
        autocmd!
        autocmd User FugitiveCommit setlocal foldmethod=syntax
    augroup END
endif

function! s:ConfigureGclogPreview() abort
    if get(b:, 'dotfiles_gclog_preview_mapping', 0)
        silent! nunmap <buffer> p
        unlet b:dotfiles_gclog_preview_mapping
    endif

    if &buftype !=# 'quickfix'
        return
    endif

    let window_info = getwininfo(win_getid())
    if empty(window_info) || get(window_info[0], 'loclist', 0)
        return
    endif

    if get(getqflist({'title': 1}), 'title', '') =~# '^:Gclog\>'
        nnoremap <buffer> <silent> p <CR><C-W>p
        let b:dotfiles_gclog_preview_mapping = 1
    endif
endfunction

augroup gclog_preview
    autocmd!
    autocmd BufWinEnter * call <SID>ConfigureGclogPreview()
augroup END
