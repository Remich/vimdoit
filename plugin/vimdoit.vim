" File: vimdoit.vim
" Author: René Michalke <rene@renemichalke.de>
" Description: A VIM Project Manager

" Disable loading of plugin.
if exists("g:vimdoit_load") && g:vimdoit_load == 0
  finish
endif

" Save user's options, for restoring at the end of the script.
let s:save_cpo = &cpo
set cpo&vim

echom "Plugin vimdoit loaded."

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																Project Tree															 "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DataInit()
	
	" the tree generated by the project-file parser	
	let s:project_tree = {
				\ 'name'		 : 'Unknown Project',
				\ 'level'		 : 0,
				\ 'sections' : [],
				\ 'tasks'		 : [],
				\	}
	
	" A stack to keep track of the nesting of (sub-)sections.
	" The top always points to the section to which
	" the currently parsed section should be added to.
	" Always use `DataStackPush`, `DataStackTop` and
	" `DataStackPop` to manipulate `s:sections_stack`.
	let s:sections_stack = [ s:project_tree ]
	
	" A stack to keep track of the nesting of tasks/notes.
	" The top always points to the section/task/note to which
	" the currently parsed task/note should be added to.
	" Always use `DataStackPush`, `DataStackTop` and
	" `DataStackPop` to manipulate `s:tasks`.
	let s:tasks_stack = [ s:project_tree ]
endfunction

" Initial Init
call s:DataInit()
	
" =================
" = Data Printer =
" =================

function! s:DataGetPadding(level)
	let l:r = range(a:level)
	let l:padding = ""
	for i in l:r 
		let l:padding .= "		"
	endfor

	return l:padding
endfunction

function! s:DataPrintSection(section, level)

	let l:padding   = s:DataGetPadding(a:level)
	let l:nextlevel = a:level + 1
	
	echom l:padding."# ".a:section['name']

	if len(a:section['tasks']) > 0
		echom l:padding."Tasks:"
		call map(a:section['tasks'], 's:DataPrintTask(v:val, l:nextlevel)')	
	endif

	if len(a:section['sections']) > 0
		echom l:padding."Sections:"
		call map(a:section['sections'], 's:DataPrintSection(v:val, l:nextlevel)')	
	endif
endfunction

function! s:DataPrintTask(task, level)
	
	let l:padding   = s:DataGetPadding(a:level + a:task['level'])
	let l:nextlevel = a:level
	
	echom l:padding."".a:task['name']." – ".a:task['level']
	
	if len(a:task['tasks']) > 0
		call map(a:task['tasks'], 's:DataPrintTask(v:val, l:nextlevel)')	
	endif
endfunction

function! s:DataPrint()
	call map(s:project_tree['sections'], 's:DataPrintSection(v:val, 0)')		
	" echom s:project_tree
endfunction

" ===========================================
" = Methods for generating the project tree =
" ===========================================

" ========================
" = Datastructure: Stack =
" ========================

function! s:DataStackPush(stack, object)
	call add(a:stack, a:object)
endfunction

function! s:DataStackTop(stack)
	let l:len = len(a:stack)
	return a:stack[l:len-1]
endfunction

function! s:DataStackPop(stack)
	let l:len = len(a:stack)
	call remove(a:stack, l:len-1)
endfunction

function! s:DataStackReset(stack)
	if len(a:stack) > 0
		unlet a:stack[0 : ]
	endif
endfunction

function! s:DataStackLen(stack)
	return len(a:stack)
endfunction
" Decides to pop some objects of `a:stack` according to `a:level`.
function! s:DataStackUpdate(stack, level)

	if len(a:stack) == 0
		return
	endif
	
	let l:top = s:DataStackTop(a:stack)
	
	if a:level <= l:top["level"]
		while l:top["level"] > a:level - 1
			
			call s:DataStackPop(a:stack)
			
			if len(a:stack) == 0
				return
			endif
			
			let l:top = s:DataStackTop(a:stack)
			
		endwhile
	endif
endfunction

" =======================
" = Datastructure: Tree =
" =======================

function! s:DataNewSection(name, start, level)
	let s:section = {
				\ 'name'        : a:name,
				\ 'start'				: a:start,
				\ 'level'				: a:level,
				\ 'end'					: -1,
				\ 'sections'	  : [],
				\ 'tasks'       : [],
				\ }
	return s:section	
endfunction

function! s:DataNewTask(name, line, level)
	let s:task = {	
				\ 'name'  : a:name,
				\ 'line'  : a:line,
				\ 'level' : a:level,
				\ 'tasks' : []
				\ }
	return s:task
endfunction

function! s:DataAddSection(name, start, level)
	" create new section object
	let l:new = s:DataNewSection(a:name, a:start, a:level)
	" update sections stack according to level	
	call s:DataStackUpdate(s:sections_stack, l:new["level"])
	" add section as child
	let l:top = s:DataStackTop(s:sections_stack)
	call add(l:top['sections'], l:new)
	" add section as top of `s:sections_stack`
	call s:DataStackPush(s:sections_stack, l:new)
	" set section as top of `s:tasks_stack`
	call s:DataStackReset(s:tasks_stack)
	call s:DataStackPush(s:tasks_stack, l:new)
endfunction

" Returns the section with name = `a:name`.
" If no such section exists, returns an empty list.
function! s:DataGetSection(name)
	return filter(deepcopy(s:project_tree['sections']), 'v:val["name"] == "'.a:name.'"')
endfunction

function! s:DataGetFirstSection()
	return s:project_tree['sections'][0]
endfunction

" Updates the `end` of each Section according to it's successor's `start`
function! s:DataUpdateEndOfEachSection(section)
	
	let l:prev_section = {}
	
	for i in a:section
		
		if l:prev_section != {}
			let l:prev_section['end'] = i['start'] - 1
		endif

		if l:prev_section != {} && len(l:prev_section['sections']) > 0
			let l:last_section        = s:DataUpdateEndOfEachSection(l:prev_section['sections'])
			let l:last_section['end'] = i['start'] - 1
		endif
		
		let l:prev_section = i
	endfor
	
	return l:prev_section
endfunction

function! s:IsSubTask(t1, t2)
	if a:t1["level"] > a:t2["level"]
		return v:true
	else
		return v:false
	endif
endfunction

" CUR:
function! s:DataAddTask(name, line, level)
	let l:new = s:DataNewTask(a:name, a:line, a:level)	

	" update tasks stack according to level	
	call s:DataStackUpdate(s:tasks_stack, l:new["level"])
	
	" decide where to add task to (current section or current tasks)
	if s:DataStackLen(s:tasks_stack) == 0
		let l:top = s:DataStackTop(s:sections_stack)
	else
		let l:top = s:DataStackTop(s:tasks_stack)
	endif
	
	call add(l:top['tasks'], l:new)

	" add task as top of `s:task_stack`
	call s:DataStackPush(s:tasks_stack, l:new)
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																		Drawer													     	"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DrawComputeOverviewText(sections, text, num, padding)
	let l:j = 1
	let l:sep = a:num == "" ? '' : '.'
	let l:padding = a:padding."	"
	let l:text = a:text
	for i in a:sections
		let l:numstr = a:num.l:sep.l:j
		call add(l:text, l:padding.l:numstr.'. '.i['name'])
		" recurse
		if len(i['sections']) > 0
			let l:text = s:DrawComputeOverviewText(i['sections'], l:text, l:numstr, l:padding)
		endif
		let l:j += 1
	endfor

	return l:text
endfunction

function! s:DrawSectionOverview()
	let l:overview = s:DataGetSection("OVERVIEW")
	
	" check if there is already a section 'OVERVIEW' in the document
	if l:overview == []
		" no, just get the drawing position
		let s:tmp = s:DataGetFirstSection()
		let l:draw_position = s:tmp['start']-1
		let l:sections = s:project_tree['sections']
	else
		" yes, delete it
		let l:overview      = l:overview[0]
		let l:draw_position = l:overview['start']-1
		" delete old overview
		call deletebufline(bufname(), l:overview['start'], l:overview['end'])
		let l:sections = filter(deepcopy(s:project_tree['sections']), 'v:val["name"] != "OVERVIEW"')
	endif
	
	" insert new overview

	let l:text = [ 
				\ "==============================================================================", 
				\ "<OVERVIEW>",
				\ "",
				\ ]	

	let l:text     = s:DrawComputeOverviewText(l:sections, l:text, "", "")
	call add(l:text, "")
	
	call append(l:draw_position, l:text)

endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"												 		Project-file Parser			                       "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:IsLineEmpty(line)
	if trim(a:line) == ""
		return v:true
	else
		return v:false
	endif
endfunction

function! s:IsLineSectionDelimiter(line)
	let l:pattern = '^===.*===$'
  let l:result  = match(a:line, l:pattern)
	
	if l:result == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:IsLineSubsectionDelimiter(line)
	let l:pattern = '^---.*---$'
  let l:result  = match(a:line, l:pattern)
	
	if l:result == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:IsLineTask(line)
	let l:pattern = '\v^\s*-\s\[.*\]\s.*$'
	let l:result  = match(a:line, l:pattern)
	
	if l:result == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:ExtractSectionHeading(line)
	let l:pattern  = '\v^\t*\<\zs.*\ze\>'
	let l:heading  = []
	call substitute(a:line, l:pattern, '\=add(l:heading, submatch(0))', 'g')

	if l:heading == []
		throw "ERROR: Heading not found!"
		return
	endif
	
	return trim(l:heading[0])
endfunction

function! s:ExtractSectionLevel(line)
	let l:pattern = '\v\zs\s*\ze[^\s]'
	let l:tabs    = []
	call substitute(a:line, l:pattern, '\=add(l:tabs, submatch(0))', 'g')
	return strlen(l:tabs[0])
endfunction

function! s:ExtractTaskName(line)
	let l:pattern = '\v\s*-\s\[.*\]\s\zs.*\ze((--)|$)'
	let l:task    = []
	call substitute(a:line, l:pattern, '\=add(l:task, submatch(0))', 'g')
	return trim(l:task[0])
endfunction

function! s:ExtractTaskLevel(line)
	let l:pattern = '\v\zs\s*\ze-'
	let l:tabs    = []
	call substitute(a:line, l:pattern, '\=add(l:tabs, submatch(0))', 'g')
	return strlen(l:tabs[0])
endfunction

" Iterates over every line of the file exactly once!
function! s:ParseProjectFile()
	
	echom "Parsing Project File"
	call s:DataInit()

	try
	
		let l:cur_line_num   = 0
		let l:total_line_num = line('$')

		" some flags
		let l:is_line_section_heading    = v:false
		let l:is_line_subsection_heading = v:false
		
		let l:i = 1
		while l:i <= l:total_line_num

			let l:line = getline(l:i)

			" skip empty lines
			if s:IsLineEmpty(l:line) == v:true
				let l:i += 1
				continue
			endif

			" is line a Section Delimiter?
			if s:IsLineSectionDelimiter(l:line) == v:true
				" yes: then next line contains the Section Heading
				let l:section_name  = s:ExtractSectionHeading(getline(l:i+1))
				let l:section_level = 1
				call s:DataAddSection(l:section_name, l:i, section_level)
				
				let l:i += 2
				continue
			endif
			
			" is line a Subsection Delimiter?
			if s:IsLineSubsectionDelimiter(l:line) == v:true
				" yes: then next line contains the Section Heading
				let l:section_name  = s:ExtractSectionHeading(getline(l:i+1))
				let l:section_level = 2 + s:ExtractSectionLevel(getline(l:i+1))
				call s:DataAddSection(l:section_name, l:i, section_level)
				
				let l:i += 2
				continue
			endif
			
			" is line a Task?	
			if s:IsLineTask(l:line) == v:true
				let l:task_name  = s:ExtractTaskName(l:line)
				let l:task_level = s:ExtractTaskLevel(l:line)
				call s:DataAddTask(l:task_name, l:i, l:task_level)

				let l:i += 1
				continue
			endif
			
			let l:i += 1
		endwhile

		let l:last_section        = s:DataUpdateEndOfEachSection(s:project_tree["sections"])
		let l:last_section['end'] = line('$')

		call s:DrawSectionOverview()
	
	catch
		echom "vimdoit:  Exception  in ".v:throwpoint.":"
		echom "   ".v:exception	
	endtry

	" echom s:project_tree

endfunction

augroup VimDoit
	autocmd!
	" autocmd InsertLeave *.vdo call s:ParseProjectFile()
	autocmd BufWritePost *.vdo call s:ParseProjectFile()
augroup END

" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo
