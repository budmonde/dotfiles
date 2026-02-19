" Neovim configuration
" Architecture: vimrc.before -> lazy.nvim -> vimrc.after
"   vimrc.before - Common settings (no rtp dependencies)
"   lazy.nvim    - Plugin manager (resets rtp, restores ~/.vim via rtp.paths)
"   vimrc.after  - Settings requiring ~/.vim in rtp (keymap, spell)

" Skip colorscheme from vimrc (lazy.nvim handles it)
let g:skip_colorscheme = 1

" Session mode: disabled by default, enable via env var NVIM_SESSION=1
" Usage: NVIM_SESSION=1 nvim (or use the `vs` alias)
if !exists('g:enable_session')
    let g:enable_session = !empty($NVIM_SESSION)
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
set autoread                   " Reload files changed outside of nvim
set undodir=~/.local/state/nvim/undo
if !isdirectory($HOME . "/.local/state/nvim/undo")
    call mkdir($HOME . "/.local/state/nvim/undo", "p", 0700)
endif

" Auto-reload files modified externally (e.g. by opencode, git)
augroup AutoReload
    autocmd!
    autocmd FocusGained,BufEnter * checktime
augroup END

" Load Lua configuration (includes colorscheme via lazy.nvim)
" lazy.nvim preserves ~/.vim in rtp via performance.rtp.paths
lua require('config.lazy')

" Source vimrc.after now that rtp includes ~/.vim
" Needs ~/.vim/keymap/ for Mongolian input and ~/.vim/spell/ for dictionaries
source ~/.vim/vimrc.after
