
let g:vimdoit_save_options   = {}
let g:vimdoit_save_registers = {}
let g:vimdoit_save_cf_id     = -1

function! vimdoit_utility#PrintOptions()
	echom &grepprg
	echom &grepformat
	echom &cpo
	echom &selection
endfunction

function! vimdoit_utility#SaveOptions()
	let g:vimdoit_save_options["grepprg"]    = &grepprg
	let g:vimdoit_save_options["grepformat"] = &grepformat
	let g:vimdoit_save_options["cpo"]        = &cpo
	let g:vimdoit_save_options["selection"]  = &selection
	let g:vimdoit_save_options["cwd"]				 = getcwd()
endfunction

function! vimdoit_utility#SetOptions()
	set grepprg=rg\ --vimgrep\ --smart-case
	set grepformat^=%f:%l:%c:%m
	set cpo&vim
	set selection=inclusive
endfunction

function! vimdoit_utility#RestoreOptions()
	let &grepprg    = g:vimdoit_save_options["grepprg"]
	let &grepformat = g:vimdoit_save_options["grepformat"]
	let &cpo        = g:vimdoit_save_options["cpo"]
	let &selection  = g:vimdoit_save_options["selection"]
	execute "cd ".g:vimdoit_save_options["cwd"]
endfunction

function! vimdoit_utility#PrintRegisters()
	echom g:vimdoit_save_registers
	for key in keys(g:vimdoit_save_registers)
		echom getreg(key)
	endfor
endfunction

function! vimdoit_utility#SaveRegisters(regs)
	for i in a:regs
		let g:vimdoit_save_registers[i] = getreg(i)
	endfor
endfunction

function! vimdoit_utility#RestoreRegisters()
	for key in keys(g:vimdoit_save_registers)
		call setreg(key, g:vimdoit_save_registers[key])
	endfor
	let g:vimdoit_save_registers = {}
endfunction

function! vimdoit_utility#SaveCfStack()
	
	" check if there are any qflists
  if getqflist({'nr' : '$'}).nr == 0
		" no, abort
		return
	endif
		
	" get id of current qflist
	let l:qfid = getqflist({'id' : 0}).id
	
	" save
	let g:vimdoit_save_cf_id = l:qfid
endfunction

function! vimdoit_utility#RestoreCfStackAndPushNewList(qflist, title)

	" restore stack
	call vimdoit_utility#RestoreCfStack()
		
	" add new list on top of stack
	call setqflist(a:qflist)
	
	" set title
	call setqflist([], 'r', { 'title' : a:title })
		
endfunction

function! vimdoit_utility#RestoreCfStack()
	
	" no previous list
	if g:vimdoit_save_cf_id == -1
		" empty whole stack
		call setqflist([], 'f')
		return
	endif
	
	" get id of current list
	let l:cur_qfid = getqflist({'id': 0}).id

	while l:cur_qfid != g:vimdoit_save_cf_id
		" free current list
		call setqflist([], 'r')
		" go to previous list
		silent colder
		" get id of current list
		let l:cur_qfid = getqflist({'id': 0}).id
	endwhile
	
endfunction
