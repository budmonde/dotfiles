" Neovim configuration
" Sources shared vim config, then applies neovim-specific settings

" Skip colorscheme from vimrc (lazy.nvim handles it)
let g:skip_colorscheme = 1

" Session mode: disabled by default, enable with --cmd 'let g:enable_session=1'
" Usage: nvim -S (alias recommended) or nvim --cmd 'let g:enable_session=1'
if !exists('g:enable_session')
    let g:enable_session = 0
endif

source ~/.vim/vimrc

" Auto-set tab-local CWD to file's directory on new tabs
augroup TabLocalCwd
    autocmd!
    autocmd TabNewEntered * if expand('%:p') != '' | tcd %:p:h | endif
augroup END

" Neovim-specific overrides
set nolazyredraw               " lazyredraw behaves differently in neovim
set undodir=~/.local/state/nvim/undo
if !isdirectory($HOME . "/.local/state/nvim/undo")
    call mkdir($HOME . "/.local/state/nvim/undo", "p", 0700)
endif

" Load Lua configuration (includes colorscheme via lazy.nvim)
lua require('config.lazy')
