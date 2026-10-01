if has('clipboard_provider')
    unlet! s:clipboard_executable s:clipboard_copy_command s:clipboard_paste_command

    function! s:ClipboardText(lines) abort
        let l:linewise = a:lines =~# "\n$"
        let l:lines = split(a:lines, "\n", 1)
        if l:linewise
            call remove(l:lines, -1)
        endif
        return [l:linewise ? 'V' : 'v', l:lines]
    endfunction

    if !empty($TMUX) && executable('tmux')
        function! s:TmuxClipboardCopy(register, type, lines) abort
            let l:text = join(a:lines, "\n")
            if a:type ==# 'V'
                let l:text .= "\n"
            endif
            silent call system('tmux load-buffer -w -', l:text)
        endfunction

        function! s:TmuxClipboardPaste(register) abort
            let l:text = system('tmux save-buffer -')
            if v:shell_error
                return ['', []]
            endif
            return s:ClipboardText(l:text)
        endfunction

        let v:clipproviders.tmux = {
            \ 'available': {-> !empty($TMUX) && executable('tmux')},
            \ 'copy': {'+': function('s:TmuxClipboardCopy'), '*': function('s:TmuxClipboardCopy')},
            \ 'paste': {'+': function('s:TmuxClipboardPaste'), '*': function('s:TmuxClipboardPaste')},
            \ }
        set clipmethod=tmux
    elseif !empty($SSH_CONNECTION) || !empty($SSH_TTY)
        let g:osc52_disable_paste = 1
        let g:osc52_force_avail = 1
        silent! packadd osc52
        if has_key(v:clipproviders, 'osc52')
            set clipmethod=osc52
        endif
    else
        if !empty($WSL_DISTRO_NAME) && executable('win32yank.exe')
            let s:clipboard_executable = 'win32yank.exe'
            let s:clipboard_copy_command = 'win32yank.exe -i --crlf'
            let s:clipboard_paste_command = 'win32yank.exe -o --lf'
        elseif !empty($WAYLAND_DISPLAY) && executable('wl-copy') && executable('wl-paste')
            let s:clipboard_executable = 'wl-copy'
            let s:clipboard_copy_command = 'wl-copy'
            let s:clipboard_paste_command = 'wl-paste --type text/plain'
        elseif !empty($DISPLAY) && executable('xclip')
            let s:clipboard_executable = 'xclip'
            let s:clipboard_copy_command = 'xclip -selection clipboard -in'
            let s:clipboard_paste_command = 'xclip -selection clipboard -out'
        elseif !empty($DISPLAY) && executable('xsel')
            let s:clipboard_executable = 'xsel'
            let s:clipboard_copy_command = 'xsel --clipboard --input'
            let s:clipboard_paste_command = 'xsel --clipboard --output'
        endif
    endif

    if exists('s:clipboard_copy_command')
        function! s:ExternalClipboardCopy(register, type, lines) abort
            let l:text = join(a:lines, "\n")
            if a:type ==# 'V'
                let l:text .= "\n"
            endif
            silent call system(s:clipboard_copy_command, l:text)
        endfunction

        function! s:ExternalClipboardPaste(register) abort
            let l:text = system(s:clipboard_paste_command)
            return v:shell_error ? ['', []] : s:ClipboardText(l:text)
        endfunction

        let v:clipproviders.external = {
            \ 'available': {-> executable(s:clipboard_executable)},
            \ 'copy': {'+': function('s:ExternalClipboardCopy'), '*': function('s:ExternalClipboardCopy')},
            \ 'paste': {'+': function('s:ExternalClipboardPaste'), '*': function('s:ExternalClipboardPaste')},
            \ }
        set clipmethod=external
    elseif empty($TMUX) && empty($SSH_CONNECTION) && empty($SSH_TTY) && !has('clipboard')
        let g:osc52_disable_paste = 1
        let g:osc52_force_avail = 1
        silent! packadd osc52
        if has_key(v:clipproviders, 'osc52')
            set clipmethod=osc52
        endif
    endif
endif
