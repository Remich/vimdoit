" File: vim-tmsu.vim
" Author: René Michalke <rene@renemichalke.de>
" Description: A Vim wrapper for TMSU.

" Disable loading of plugin.
if exists("g:vimtmsu_load") && g:vimtmsu_load == 0
  finish
endif

" Save user's options, for restoring at the end of the script.
let s:save_cpo = &cpo
set cpo&vim

echom "Plugin vimdoit loaded."

" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo
