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
"																DATA STRUCTURER		                         "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DataInit()
	let s:data = {
				\ 'name'				: 'Unknown Project',
				\ 'level'				: 0,
				\ 'sections'		: [],
				\	}

	let s:data_stack_sections = [ s:data ]
	let s:cur_task            = v:null
	let s:cur_task_flag       = v:false
endfunction

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
	call map(s:data['sections'], 's:DataPrintSection(v:val, 0)')		
	" echom s:data
endfunction

" ====================
" = Data Manipulator =
" ====================

function! s:DataStackSectionsPush(section)
	call add(s:data_stack_sections, a:section)
endfunction

function! s:DataStackSectionsTop()
	let l:len = len(s:data_stack_sections)
	return s:data_stack_sections[l:len-1]
endfunction

function! s:DataStackSectionsPop()
	let l:len = len(s:data_stack_sections)
	call remove(s:data_stack_sections, l:len-1)
endfunction

function! s:DataNewSection(name)
	let s:section = {
				\ 'name'        : a:name,
				\ 'level'				: -1,
				\ 'start'				: -1,
				\ 'end'					: -1,
				\ 'sections'	  : [],
				\ 'tasks'       : [],
				\ }
	return s:section	
endfunction

function! s:DataNewTask(name, level)
	let s:task = {	
				\ 'name'  : a:name,
				\ 'level' : a:level,
				\ 'tasks' : []
				\ }
	return s:task
endfunction

function! s:DataAddSection(name, start, level)
	let l:new = s:DataNewSection(a:name)
	let l:new["start"] = a:start
	let l:new["level"] = a:level

	let l:top = s:DataStackSectionsTop()

	if l:new["level"] > l:top["level"]
		call add(l:top['sections'], l:new)
		call s:DataStackSectionsPush(l:new)
		return
	endif

	if l:new["level"] <= l:top["level"]
		
		while l:top["level"] > l:new["level"] - 1
			call s:DataStackSectionsPop()
			let l:top = s:DataStackSectionsTop()
		endwhile

		call add(l:top['sections'], l:new)
		call s:DataStackSectionsPush(l:new)
		return
	endif
	
	let s:cur_task            = v:null
	let s:cur_task_flag       = v:false
	
endfunction

" Returns the section with name = `a:name`.
" If no such section exists, returns an empty list.
function! s:DataGetSection(name)
	return filter(deepcopy(s:data['sections']), 'v:val["name"] == "'.a:name.'"')
endfunction

function! s:DataGetFirstSection()
	return s:data['sections'][0]
endfunction

" Updates the `end` of each Section according to it's successor Section
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

function! s:DataAddTask(name, level)
	let s:new = s:DataNewTask(a:name, a:level)	

	" add as child of a task, subsection or section?

	" check if there is a cur_task and if the new task is a subtask
	if s:cur_task_flag != v:false && s:IsSubTask(s:cur_task, s:new) == v:true
		call add(s:cur_task['tasks'], s:new)
		return
	endif

	if s:cur_subsection_flag != v:false
		call add(s:cur_subsection['tasks'], s:new)
		let s:cur_task      = s:new
		let s:cur_task_flag = v:true
		return
	endif

	if s:cur_section_flag != v:false
		call add(s:cur_section['tasks'], s:new)
		let s:cur_task      = s:new
		let s:cur_task_flag = v:true
		return
	endif

	echom "ERROR: No Current Section!"
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																		DRAWER													     	"
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
		let l:sections = s:data['sections']
	else
		" yes, delete it
		let l:overview      = l:overview[0]
		let l:draw_position = l:overview['start']-1
		" delete old overview
		call deletebufline(bufname(), l:overview['start'], l:overview['end'])
		let l:sections = filter(deepcopy(s:data['sections']), 'v:val["name"] != "OVERVIEW"')
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
"												 		PROJECT-FILE PARSER			                       "
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
			" if s:IsLineTask(l:line) == v:true
			" 	let l:task_name  = s:ExtractTaskName(l:line)
			" 	let l:task_level = s:ExtractTaskLevel(l:line)
			" 	call s:DataAddTask(l:task_name, l:task_level)
      "
			" 	let l:i += 1
			" 	continue
			" endif
			
			let l:i += 1
		endwhile

		let l:last_section        = s:DataUpdateEndOfEachSection(s:data["sections"])
		let l:last_section['end'] = line('$')

		call s:DrawSectionOverview()
	
	catch
		echom "vimdoit:  Exception  in ".v:throwpoint.":"
		echom "   ".v:exception	
	endtry

	" call s:DataPrint()

endfunction

augroup VimDoit
	autocmd!
	" autocmd InsertLeave *.vdo call s:ParseProjectFile()
	autocmd BufWritePost *.vdo call s:ParseProjectFile()
augroup END

" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo
