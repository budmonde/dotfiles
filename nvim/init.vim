" Neovim configuration
" Sources shared vim config, then applies neovim-specific settings

" Add vim paths for shared resources (keymap, spell, etc.)
set runtimepath+=~/.vim

" Skip colorscheme from vimrc (lazy.nvim handles it)
let g:skip_colorscheme = 1

source ~/.vim/vimrc

" Neovim-specific overrides
set nolazyredraw               " lazyredraw behaves differently in neovim
set undodir=~/.local/state/nvim/undo
if !isdirectory($HOME . "/.local/state/nvim/undo")
    call mkdir($HOME . "/.local/state/nvim/undo", "p", 0700)
endif

" Load Lua configuration (includes colorscheme via lazy.nvim)
lua require('config.lazy')
