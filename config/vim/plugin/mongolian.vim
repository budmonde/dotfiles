" See: http://vim.wikia.com/wiki/Insert-mode_only_Caps_Lock
" See: http://vi.stackexchange.com/q/2260/267
set imsearch=-1
set keymap=qwerty2mongolian
set iminsert=0

function! ToggleMongolianInput()
    if &iminsert == 0
        set iminsert=1
        echom "Mongolian input: ON"
    else
        set iminsert=0
        echom "Mongolian input: OFF"
    endif
endfunction
