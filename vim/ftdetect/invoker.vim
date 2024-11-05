augroup InvokerScriptFiletype
  autocmd!
  autocmd BufRead,BufNewFile * if filereadable(fnamemodify(expand('%:p:h') . '/invoker.py', ':p'))
        \ | set filetype=python.invoker
        \ | endif
augroup END

