nnoremap <localleader>e :call CreateInvokerPane()<CR>
nnoremap <localleader>r :call RunInvokerDebug()<CR>

let g:invoker_debug_pane = ""
function! CreateInvokerPane()
    if !empty($TMUX)
        let g:invoker_debug_pane = substitute(system("tmux split-window -h -P -t . -d"), '\n', '', '')
        echom "Created invoker-debug tmux pane with ID " . g:invoker_debug_pane
    else
        echo "Not in a tmux session"
    endif
endfunction

function! RunInvokerDebug()
    let l:filename = expand('%')
    let l:line_number = line('.')
    let l:command = 'invoker debug ' . l:filename . ':' . l:line_number

    if !empty($TMUX) && !empty(g:invoker_debug_pane)
        execute 'silent !tmux send-keys -t ' . g:invoker_debug_pane . ' ' . shellescape(l:command) . ' Enter'
        redraw!
    elseif empty($TMUX)
        execute '!' . l:command
    else
        echo "Error: 'invoker_debug_pane' is empty. Use <localleader>e to create it."
    endif
endfunction
