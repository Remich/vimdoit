" File: vimdoit.vim
" Author: René Michalke <rene@renemichalke.de>
" Description: A Project Management Software for Vim

" Disable loading of plugin.
if exists("g:vimdoit_load") && g:vimdoit_load == 0
  finish
endif

" Save user's options, for restoring at the end of the script.
let s:save_cpo = &cpo
set cpo&vim



" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo

