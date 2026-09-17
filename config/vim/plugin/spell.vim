" Regenerate spell dictionary binary - requires ~/.vim/spell/ in runtimepath
" See: https://vi.stackexchange.com/questions/5050
for d in glob('~/.vim/spell/*.add', 1, 1)
    if filereadable(d) && (
    \   !filereadable(d . '.spl') || getftime(d) > getftime(d . '.spl')
    \)
        exec 'mkspell! ' . fnameescape(d)
    endif
endfor
