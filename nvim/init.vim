" Neovim configuration
" Architecture: vimrc.before -> lazy.nvim -> vimrc.after
"   vimrc.before - Common settings (no rtp dependencies)
"   lazy.nvim    - Plugin manager (resets rtp, then restores ~/.vim)
"   vimrc.after  - Settings requiring ~/.vim in rtp (loaded by lazy.lua)

" Skip colorscheme from vimrc (lazy.nvim handles it)
let g:skip_colorscheme = 1

" Session mode: disabled by default, enable with --cmd 'let g:enable_session=1'
" Usage: nvim --cmd 'let g:enable_session=1'
if !exists('g:enable_session')
    let g:enable_session = 0
endif

source ~/.vim/vimrc.before

" Auto-set tab-local CWD to file's directory on new tabs
augroup TabLocalCwd
    autocmd!
    autocmd TabNewEntered * if expand('%:p') != '' | tcd %:p:h | endif
augroup END

" WSL: set fileformat based on path (Windows mounts use CRLF)
augroup CrossPlatformLineEndings
    autocmd!
    autocmd BufReadPost,BufNewFile /mnt/* setlocal fileformat=dos
    autocmd BufReadPost,BufNewFile /home/* setlocal fileformat=unix
augroup END

" Neovim-specific overrides
set nolazyredraw               " lazyredraw behaves differently in neovim
set undodir=~/.local/state/nvim/undo
if !isdirectory($HOME . "/.local/state/nvim/undo")
    call mkdir($HOME . "/.local/state/nvim/undo", "p", 0700)
endif

" Load Lua configuration (includes colorscheme via lazy.nvim)
lua require('config.lazy')

" Restore ~/.vim to runtimepath (lazy.setup() resets it)
" Must be after lazy.nvim loads
set runtimepath+=~/.vim
set runtimepath+=~/.vim/after

" Source vimrc.after now that rtp includes ~/.vim
" This loads keymap and other rtp-dependent settings
source ~/.vim/vimrc.after
