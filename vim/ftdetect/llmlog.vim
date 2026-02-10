" Detect llmlog output files
" Files with .llmlog extension or piped from llmlog command

autocmd BufRead,BufNewFile *.llmlog setfiletype llmlog

" Detect by content pattern (separator lines and USER/ASSISTANT headers)
autocmd BufRead,BufNewFile * if getline(1) =~ '^━\+$' && getline(2) =~ '^\(USER\|ASSISTANT\) │' | setfiletype llmlog | endif
