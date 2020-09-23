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

" TODO better way
let g:plugindir = '/home/pepe/software/vimdoit'

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																Writing Zettels   												 "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:GetAllProjects(dir)
	let l:cwd = getcwd()
	execute "cd ".a:dir
	
	let l:assoc = { 'name' : a:dir, 'areas' : [], 'projects' : [] }
	let l:files = split(system('ls -1'), '\v\n')
	
	for i in l:files
		if filereadable(i) == v:false
			let l:list = []
			let l:ret = s:GetAllProjects(i)
			call add(l:assoc['areas'], l:ret)
		else
			if match(i, '.*vdo') != -1
				let l:tree = s:ParseProject(i)
				call add(l:assoc['projects'], l:tree)
			endif
		endif
	endfor
	
	execute "cd ".l:cwd
	return l:assoc
endfunction

function! s:ParseProject(name)
	execute "edit! ".a:name
	echom "Parsing: ".a:name
	call s:ParseProjectFile()
	call s:DataComputeProgress()
	let l:tree = deepcopy(s:project_tree)
	bdel!
	return l:tree
endfunction

function! s:WriteZettelOverviewOfAllProjects()
	" get and parse all projects
	let l:projects = s:GetAllProjects('.')
	let l:projects['name'] = "All Projects"
	
	" encode data and write to file
	execute 'edit! data.json'
	execute 'normal! dG'
	call append(1, json_encode(l:projects))
	execute 'normal! 1dd'
	execute 'normal! 2dd'
	write!
	bdel!
	
	" call external zettel writer
	" let l:ret = system('node '.g:plugindir.'/src/write-zettels.js')
	" if trim(l:ret) != ""
	" 	echom l:ret
	" endif
endfunction
command! -nargs=0 WritePO	:call s:WriteZettelOverviewOfAllProjects()

function! s:WriteZettels()
	echom s:project_tree
	let l:data = json_encode(s:project_tree)		
	let l:ret = system('node '.g:plugindir.'/src/write-zettels.js -d '.shellescape(l:data))
	if trim(l:ret) != ""
		echom l:ret
	endif
endfunction
command! -nargs=0 WriteZettels	:call s:WriteZettels()

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																Project Tree															 "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DataInit()
	
	" the tree generated by the project-file parser	
	let s:project_tree = {
				\ 'id'			 : -1,
				\ 'type'		 : 'project',
				\ 'name'		 : 'Unknown Project',
				\ 'progress' : 0,
				\ 'level'		 : 0,
				\ 'sections' : [],
				\ 'tasks'		 : [],
				\ 'flags'		 : {},
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
	" `DataStackPop` to manipulate `s:tasks_stack`.
	let s:tasks_stack = [ s:project_tree ]
endfunction

" Initial Init
call s:DataInit()

function! s:DataSaveJSON()
	echom "called DataSaveJSON"
	" remove 'OVERVIEW' section
	call filter(s:project_tree['sections'], 'v:val["name"] !=# "OVERVIEW"')
	let l:path = expand('%:p:h')
	let l:filename = substitute(expand('%:t'), '\v\.vdo', '', "")
	let l:fullname = l:path."/.".l:filename.".json"
	execute "edit! ".l:fullname
	execute 'normal! dG'
	call append(1, json_encode(s:project_tree))
	execute 'normal! 1dd'
	execute 'normal! 2dd'
	write!
	" echom "calling: ".'node /home/pepe/software/vimdoit/src/generate-overviews/index.js -p '.l:fullname
  call system('node /home/pepe/software/vimdoit/src/generate-overviews/index.js -p '.l:fullname)
	
	let l:curbufname = bufname("%")
	let l:alternative = bufname("#")
	enew!
	execute "bwipeout! ".l:curbufname
	if l:alternative !=# ""
		execute "buffer ".l:alternative
	endif
endfunction
	
" ========================
" = Data Printer (Debug) =
" ========================

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

function! s:DataNewSection(name)
	let s:section = {
				\ 'id'					: -1,
				\ 'type'			  : 'section',
				\ 'name'        : a:name,
				\ 'start'				: -1,
				\ 'level'				: -1,
				\ 'end'					: -1,
				\ 'progress'		: 0,
				\ 'sections'	  : [],
				\ 'tasks'       : [],
				\ 'flags'				: {},
				\ }
	return s:section	
endfunction

function! s:DataNewTask(name, linenum, level)
	let s:task = {	
				\ 'id'	  		: -1,
				\ 'type'		 : 'task',
				\ 'name'	 	 : a:name,
				\ 'linenum'	 : a:linenum,
				\ 'level'		 : a:level,
				\ 'done'		 : 0,
				\ 'waiting'	 : 0,
				\ 'failed'	 : 0,
				\ 'blocking' : 0,
				\ 'tasks'		 : [],
				\ 'flags'		 : {},
				\ }
	return s:task
endfunction

" Notes are speciel types of tasks.
function! s:DataNewNote(name, linenum, level)
	let s:note = {	
				\ 'id'	   	: -1,
				\ 'type'		 : 'note',
				\ 'name'	 	 : a:name,
				\ 'linenum'	 : a:linenum,
				\ 'level'		 : a:level,
				\ 'done'		 : -1,
				\ 'tasks'	 	 : [],
				\ 'flags'		 : {},
				\ }
	return s:note
endfunction

" Links are speciel types of tasks.
function! s:DataNewLink(project, section, linenum, level)
	let s:link = {	
				\ 'id'	  	: -1,
				\ 'type'		 : 'link',
				\ 'project'	 : a:project,
				\ 'section'	 : a:section,
				\ 'linenum'	 : a:linenum,
				\ 'level'		 : a:level,
				\ 'flags'		 : {},
				\ }
	return s:link
endfunction

function! s:GetProjectType(flags)
	if !has_key(a:flags, 'tag')
		return 'project'
	endif

	for i in a:flags['tag']
		if i ==# '#sprint'
			return 'sprint'
		endif
	endfor

	return 'project'
	
endfunction

function! s:DataSetProject(name, flags)
	let s:project_tree['name']  = a:name
	let s:project_tree['flags'] = a:flags
	let s:project_tree['type']  = s:GetProjectType(a:flags)
endfunction

function! s:DataAddSection(name, start, level, flags)
	" create new section object
	let l:new = s:DataNewSection(a:name)
	let l:new['start'] = a:start
	let l:new['level'] = a:level
	let l:new['flags'] = a:flags
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

function! s:DataGetProjectProgress()
	return s:project_tree['progress']
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

function! s:IsTaskWaiting(flags)
	if has_key(a:flags, "waiting_block") == 1
		if len(a:flags['waiting_block']) > 0
			return v:true
		else
			return v:false
		endif
	else
		return v:false
	endif
endfunction

function! s:IsTaskBlocking(flags)
	if has_key(a:flags, "block") == 1
		if len(a:flags['block']) > 0
			return v:true
		else
			return v:false
		endif
	else
		return v:false
	endif
endfunction

function! s:DataAddTask(name, linenum, level, flags)
	
	let l:new = s:DataNewTask(a:name, a:linenum, a:level)	
	let l:new['flags'] = a:flags
	
	let l:new['done']     = s:IsTaskDone(a:linenum)
	let l:new['waiting']  = s:IsTaskWaiting(a:flags)
	let l:new['blocking'] = s:IsTaskBlocking(a:flags)
	let l:new['failed']   = s:IsTaskFailed(a:linenum)
	
	" set id as supplied in flag
	if has_key(a:flags, 'id') == v:true && len(a:flags['id']) != 0
		let l:new['id'] = a:flags['id']
	endif

	" update tasks stack according to level	
	call s:DataStackUpdate(s:tasks_stack, l:new["level"])
	
	" decide where to add task to (current section or current tasks)
	if len(s:tasks_stack) == 0
		let l:top = s:DataStackTop(s:sections_stack)
	else
		let l:top = s:DataStackTop(s:tasks_stack)
	endif
	
	call add(l:top['tasks'], l:new)

	" add task as top of `s:task_stack`
	call s:DataStackPush(s:tasks_stack, l:new)
endfunction

function! s:DataAddNote(name, linenum, level, flags)
	
	let l:new = s:DataNewNote(a:name, a:linenum, a:level)	
	let l:new['flags'] = a:flags
	
	" set id as supplied in flag
	if has_key(a:flags, 'id') == v:true && len(a:flags['id']) != 0
		let l:new['id'] = a:flags['id']
	endif

	" update tasks stack according to level	
	call s:DataStackUpdate(s:tasks_stack, l:new["level"])
	
	" decide where to add note to (current section or current tasks)
	if len(s:tasks_stack) == 0
		let l:top = s:DataStackTop(s:sections_stack)
	else
		let l:top = s:DataStackTop(s:tasks_stack)
	endif
	
	call add(l:top['tasks'], l:new)

	" add link as top of `s:task_stack`
	call s:DataStackPush(s:tasks_stack, l:new)
endfunction

function! s:DataAddLink(project, section, linenum, level, flags)
	
	let l:new = s:DataNewLink(a:project, a:section, a:linenum, a:level)	
	let l:new['flags'] = a:flags
	
	" update tasks stack according to level	
	call s:DataStackUpdate(s:tasks_stack, l:new["level"])
	
	" decide where to add link to (current section or current tasks)
	if len(s:tasks_stack) == 0
		let l:top = s:DataStackTop(s:sections_stack)
	else
		let l:top = s:DataStackTop(s:tasks_stack)
	endif
	
	call add(l:top['tasks'], l:new)

	" add link as top of `s:task_stack`
	call s:DataStackPush(s:tasks_stack, l:new)
endfunction


" =========================================
" = Methods for computing additional data =
" =========================================

function! s:DataComputeProgress()
	call map([s:project_tree], "s:DataComputeProgressSection(v:val)")	
endfunction

function! s:DataComputeProgressSection(section)

	if a:section['name'] ==# "OVERVIEW"
		return a:section
	endif
	
	" compute progress of subsections
	if len(a:section['sections']) > 0
		call map(a:section['sections'], "s:DataComputeProgressSection(v:val)")
	endif

	" get the number of all subtasks and the number of done subtasks
	" in all subsections
	let l:info = { 'num' : 0, 'done' : 0 }
	call s:GetInfoAllSubsections(a:section, l:info)
	if l:info['done'] == 0 && l:info['num'] == 0
		let a:section['progress'] = 0
	else
		let a:section['progress'] = 1.0 * l:info['done'] / l:info['num']
	endif

	return a:section
endfunction

function! s:GetInfoAllSubsections(section, info)
	for i in a:section['tasks']
		call s:GetInfoAllSubtasks(i, a:info, v:false)
	endfor
	for i in a:section['sections']
		call s:GetInfoAllSubsections(i, a:info)
	endfor
endfunction

function! s:GetInfoAllSubtasks(task, info, parent)

	" skip links
	if a:task['type'] ==# 'link'
		return
	endif

	"skip notes
	if a:task['type'] ==# 'task'
		let a:info['num']	+= 1
		
		if a:parent == v:false
			" parent task is not done, check if current task is done
			let a:info['done'] += a:task['done'] == v:true ? 1 : 0
			let l:parent = a:task['done']
		else
			" parent task is done, therefore this task is also done
			let a:info['done'] += 1
			let l:parent = v:true
		endif
	else
		let l:parent = a:parent		
	endif
	
	for i in a:task['tasks']
		call s:GetInfoAllSubtasks(i, a:info, l:parent)
	endfor
endfunction

function! s:HasItemFlagSprint(item)
	if has_key(a:item['flags'], 'sprint') != 0 && len(a:item['flags']['sprint']) > 0
		return v:true
	else
		return v:false
	endif
endfunction

" return a flat list of all tasks filtered by `a:condition`
function! s:FilterTasks(item, list)

	if s:HasItemFlagSprint(a:item) == v:true
		call add(a:list['items'], a:item)
	endif

	for i in a:item['tasks']
		call s:FilterTasks(i, a:list)
	endfor
	
	if has_key(a:item, 'sections') == 0
		return
	endif
	
	for i in a:item['sections']
		call s:FilterTasks(i, a:list)
	endfor

endfunction

function! s:DataGetAllTasksAndNotes(item, list)

	if a:item['type'] == 'task' || a:item['type'] == 'note'
		call add(a:list['items'], a:item)
	endif

	for i in a:item['tasks']
		call s:DataGetAllTasksAndNotes(i, a:list)
	endfor
	
	if has_key(a:item, 'sections') == 0
		return
	endif
	
	for i in a:item['sections']
		call s:DataGetAllTasksAndNotes(i, a:list)
	endfor

endfunction


function! s:DataUpdateReferencesIsRefLocal(ref)
	" TODO
	return v:true
endfunction

function! s:DataUpdateReferencesLocalRef(ref)
	" does the section exist?	
	" NO: throw error; abort
	
	" add reference to section in `s:project_tree`
endfunction

function! s:DataAppendFlagDelimiter(linenum)
	let l:line = getline(a:linenum)
	call setline(a:linenum, l:line.' --')
endfunction

function! s:DataAddFlag(flag, linenum)
	" is there are delimiter?
	if s:HasLineFlagDelimiter(a:linenum) == v:false
		" append delimiter
		call s:DataAppendFlagDelimiter(a:linenum)
	endif
	
	" append flag
	let l:line = getline(a:linenum)
	call setline(a:linenum, l:line.' '.a:flag)
endfunction

function! s:GenerateID()
	return trim(system('date "+%s%N" | sha256sum')[0:7])
endfunction

function! s:NewID()	
	" save grep command of user
	let l:grep_save = &grepprg
	set grepprg=rg\ --vimgrep
	
	let l:id = s:GenerateID()
	
	" check if ID is already in use
	silent execute "grep! '0x".l:id."'" 
	let l:qf = getqflist()
	while len(l:qf) > 0 " yes, generate new ID
		let l:id = s:GenerateID()
		silent execute "grep! '0x".l:id."'" 
		let l:qf = getqflist()
	endwhile
	
	" restore grep command of user
	let &grepprg=l:grep_save

	return l:id
endfunction

command! -nargs=? NewID	:call s:NewID()

function! s:DataAddID(ref)

	" `a:ref` is a section, therefore it has no `linenum` but `start` and `end`
	if has_key(a:ref, 'start')
		let l:linenum = a:ref['start'] + 1
	else
		let l:linenum = a:ref['linenum']
	endif
	
	let l:id				= s:NewID()
	let a:ref['id'] = l:id
	let l:id				= '0x'.l:id

	" actual adding of ID
	call s:DataAddFlag(l:id, l:linenum)
endfunction

function! s:DataHasID(ref)
	if a:ref['id'] != -1
		return v:true
	else
		return v:false
	endif
endfunction

function! s:DataCheckIDs()

	" get all tasks
	let l:tasks = { 'items' : [] }
	call s:DataGetAllTasksAndNotes(s:project_tree, l:tasks)
	
	" decide what to do
	for item in l:tasks['items']
		" has the task/section of the reference already an ID?
		if s:DataHasID(item) == v:false
			" no: create it
			call s:DataAddID(item)
		endif
	endfor
	
endfunction

function! s:DataFindChanges()
	
	redir => l:changedlines
	silent execute 'w !diff --unchanged-line-format="" --old-line-format="" --new-line-format=";\%dn" % -'
	redir END
	
	let l:split = split(l:changedlines, '')
	if len(l:split) == 0
		return []
	endif
	
	return split(l:split[0], ';')
	return l:lines
endfunction

function! s:DataGetIDOfLine(line)
	let l:pattern = '\v0x(\x{8})'
	let l:id    = []
	call substitute(a:line, l:pattern, '\=add(l:id, submatch(1))', 'g')
	
	if len(l:id) == 0
		return -1
	else
		return l:id[0]
	endif
endfunction

function! s:DataUpdateReferences()

	"save cursor
	let l:save_buffer = bufname()
	let l:save_cursor = getcurpos()

	" save grep command of user
	let l:grep_save = &grepprg
	set grepprg=rg\ --vimgrep

	call s:DataCheckIDs()
	let l:changedlines = s:DataFindChanges()
	
	"write
	execute "write!"

	for i in l:changedlines
		let l:line = getline(i)
		
		" get ID of line
		let l:id = s:DataGetIDOfLine(l:line)
		
		" line does not have an ID, so skip
		if l:id == -1
			continue
		endif
		
		" grep for id
		silent execute "grep! '0x".l:id."'" 
		let l:qf = getqflist()

		" no external references: continue
		if len(l:qf) == 0
			continue
		endif

		" change lines
		for entry in l:qf
			execute 'buffer '.entry['bufnr']
			
			" make sure that the indendation is correct
			let l:level = s:ExtractTaskLevel(getline(entry['lnum']))
			let l:padding = ""
			for k in range(l:level)
				let l:padding .= "	"
			endfor
			
			call setline(entry['lnum'], l:padding."".trim(l:line))
			
			execute 'update'
		endfor
		
		execute 'update'
		
	endfor

	execute "update!"
	
	" restore grep command of user
	let &grepprg=l:grep_save

	" restore buffer
	execute "buffer ".l:save_buffer
	
	" restore cursor
	call setpos('.', l:save_cursor)
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																		Drawer													     	"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DrawProjectStatistics()
	" check if there is already a line with progress
	if match(getline(2), '^Progress') != -1
		" yes: delete it
		call deletebufline(bufname(), 2)
	endif
	
	call append(1, "Progress: ".printf('%.2f%%', s:DataGetProjectProgress()*100))
endfunction

function! s:DrawComputeOverviewText(sections, text, num, padding)
	let l:j = 1
	let l:sep = a:num == "" ? '' : '.'
	let l:padding = a:padding."	"
	let l:text = a:text
	for i in a:sections
		let l:numstr = a:num.l:sep.l:j
		call add(l:text, l:padding.l:numstr.'. '.i['name'].' '.printf('[%.2f%%]', i['progress']*100))
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

function! s:IsLinenumSectionHeading(linenum)
	if s:IsLineSectionDelimiter(a:linenum - 1) || s:IsLineSubsectionDelimiter(a:linenum - 1)
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

function! s:IsLineNote(line)
	let l:pattern = '\v^\s*-\s.*$'
	let l:result  = match(a:line, l:pattern)
	
	if l:result == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:IsLineLink(line)
	let l:pattern = '\v^\s*-\s\<[^\>]+\>$'
	let l:result  = match(a:line, l:pattern)
	
	if l:result == -1
		return v:false
	else
		return v:true
	endif
endfunction


function! s:HasLineFlagDelimiter(linenum)
	let l:line = getline(a:linenum)
	let l:pattern = '\v\s--\s'
	let l:result  = match(l:line, l:pattern)
	
	if l:result == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:ExtractProjectName(line)
	return s:ExtractSectionHeading(getline(a:line))
endfunction

function! s:ExtractProjectFlags(line)
	return s:ExtractSectionHeadingFlags(getline(a:line))
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

function! s:ExtractNoteName(line)
	let l:pattern = '\v\s*-\s\zs.*\ze((--)|$)'
	let l:note    = []
	call substitute(a:line, l:pattern, '\=add(l:note, submatch(0))', 'g')
	return trim(l:note[0])
endfunction

function! s:ExtractLinkProject(line)
	let l:pattern = '\v^\s*-\s\<p:\zs[^;]+\ze[^\>]*\>$'
	let l:link    = []
	call substitute(a:line, l:pattern, '\=add(l:link, submatch(0))', 'g')
	return trim(l:link[0])
endfunction

function! s:ExtractLinkSection(line)
	let l:pattern = '\v^\s*-\s\<p:[^;]+;s:\zs[^;]+\ze[^\>]*\>$'
	let l:link    = []
	call substitute(a:line, l:pattern, '\=add(l:link, submatch(0))', 'g')

	if len(l:link) == 0
		return ''
	else
		return trim(l:link[0])
	endif
endfunction


function! s:ExtractTaskLevel(line)
	let l:pattern = '\v\zs\s*\ze-'
	let l:tabs    = []
	call substitute(a:line, l:pattern, '\=add(l:tabs, submatch(0))', 'g')
	return strlen(l:tabs[0])
endfunction

function! s:ExtractNoteLevel(line)
	return s:ExtractTaskLevel(a:line)	
endfunction

function! s:ExtractLinkLevel(line)
	return s:ExtractTaskLevel(a:line)	
endfunction

function! s:ExtractFlagsFromFlagRegion(region)

	let l:line = a:region
	
	let l:flags = {
				\ 'normal'				: [],
				\ 'sprint'				: [],
				\ 'block'					: [],
				\ 'waiting_block' : [],
				\ 'waiting_date'	: [],
				\ 'tag'						: [],
				\ 'id'						: [],
				\	}

	" extract sprint flags ('@sprint')
	let l:pattern = '\v\@[^ \t]+'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["sprint"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	" extract block flags ('-block#42')
	let l:pattern = '\v\$\d+'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["block"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	" extract waiting for block flags ('-waiting=block#23')
	let l:pattern = '\v\~\d+'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["waiting_block"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	" extract waiting for date flags ('-waiting=2020-07-08')
	let l:pattern = '\v-waiting\=\d{4}-\d{2}-\d{2}'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["waiting_date"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	" extract id flag ('0xa3c922ba')
	let l:pattern = '\v0x(\x{8})'
	let l:id = []
	call substitute(l:line, l:pattern, '\=add(l:id, submatch(1))', 'g')
	let l:flags["id"] = l:id[0]
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	"extract flag ordinary tag ('#tag')
	let l:pattern = '\v#[^ \t]*'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["tag"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	" extract normal flag ('-flag')
	let l:pattern = '\v-[^ \t]+'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["normal"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')

	return l:flags
	
endfunction

function! s:ExtractSectionHeadingFlags(line)
	
	" remove section heading
	" everything remaining is the flag region
	let l:line = substitute(a:line, '\v^.*\>', '', '') 

	" no flags
	if strlen(trim(l:line)) == 0
		return {}
	endif

	" extract them
	return s:ExtractFlagsFromFlagRegion(l:line)
endfunction

function! s:ExtractTaskFlags(line)

	" does the task have any flags?
	if s:HasTaskFlags(a:line) == v:false
		return {}
	endif
	
	" remove everything which is not the flag region
	let l:line = substitute(a:line, '\v^.*--\s', '', '') 

	" extract them
	return s:ExtractFlagsFromFlagRegion(l:line)
endfunction

function! s:ExtractNoteFlags(line)
	return s:ExtractTaskFlags(a:line)
endfunction

function! s:HasTaskFlags(line)
	let l:pattern = '\v\s--\s'
	if match(a:line, l:pattern) == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:IsTaskFailed(linenum)
	let l:line = getline(a:linenum)
	let l:pattern = '\v\s*-\s\[F\]\s.*$'
	if match(l:line, l:pattern) == -1
		return v:false
	else
		return v:true
	endif
endfunction

function! s:IsTaskDone(linenum)
	let l:line = getline(a:linenum)
	let l:pattern = '\v\s*-\s\[x\]\s.*$'
	if match(l:line, l:pattern) == -1
		return v:false
	else
		return v:true
	endif
endfunction

" Iterates over every line of the file exactly once!
command! ParseFile :call s:ParseProjectFile()
function! s:ParseProjectFile()
	
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

			" is this the first line?
			if l:i == 1
				let l:project_name  = s:ExtractProjectName(l:i)
				let l:project_flags = s:ExtractProjectFlags(l:i)
				call s:DataSetProject(l:project_name, l:project_flags)
				
				let l:i += 1
				continue
			endif

			" is line a Section Delimiter?
			if s:IsLineSectionDelimiter(l:line) == v:true
				" yes: then next line contains the Section Heading
				let l:section_name  = s:ExtractSectionHeading(getline(l:i+1))
				let l:section_level = 1
				let l:flags         = s:ExtractSectionHeadingFlags(getline(l:i+1))
				call s:DataAddSection(l:section_name, l:i, section_level, l:flags)
				
				let l:i += 2
				continue
			endif
			
			" is line a Subsection Delimiter?
			if s:IsLineSubsectionDelimiter(l:line) == v:true
				" yes: then next line contains the Section Heading
				let l:section_name  = s:ExtractSectionHeading(getline(l:i+1))
				let l:section_level = 2 + s:ExtractSectionLevel(getline(l:i+1))
				let l:flags         = s:ExtractSectionHeadingFlags(getline(l:i+1))
				call s:DataAddSection(l:section_name, l:i, section_level, flags)
				
				let l:i += 2
				continue
			endif
			
			" is line a Task?	
			if s:IsLineTask(l:line) == v:true
				let l:task_name  = s:ExtractTaskName(l:line)
				let l:task_level = s:ExtractTaskLevel(l:line)
				let l:flags      = s:ExtractTaskFlags(l:line)
				call s:DataAddTask(l:task_name, l:i, l:task_level, l:flags)

				let l:i += 1
				continue
			endif
			
			" is line a Note?	
			if s:IsLineNote(l:line) == v:true
				let l:note_name   = s:ExtractNoteName(l:line)
				let l:note_level  = s:ExtractNoteLevel(l:line)
				let l:flags				= s:ExtractNoteFlags(l:line)
				call s:DataAddNote(l:note_name, l:i, l:note_level, l:flags)
			endif

			" is line a Link?
			if s:IsLineLink(l:line) == v:true
				let l:link_project = s:ExtractLinkProject(l:line)
				let l:link_section = s:ExtractLinkSection(l:line)
				let l:link_level   = s:ExtractLinkLevel(l:line)
				call s:DataAddLink(l:link_project, l:link_section, l:i, l:link_level, {})
			endif

			let l:i += 1
		endwhile

		let l:last_section        = s:DataUpdateEndOfEachSection(s:project_tree["sections"])
		let l:last_section['end'] = line('$')

	catch
		echom "vimdoit:  Exception  in ".v:throwpoint.":"
		echom "   ".v:exception	
	endtry

endfunction

function! s:AfterProjectChange()

	try
		
		call s:ParseProjectFile()
		call s:DataUpdateReferences()
		call s:ParseProjectFile() " yes again
		call s:DataComputeProgress()
		call s:DrawSectionOverview()
		call s:DrawProjectStatistics()
		" call s:DataSaveJSON()

	catch
		echom "vimdoit:  Exception  in ".v:throwpoint.":"
		echom "   ".v:exception	
	endtry
	
endfunction


augroup VimDoit
	autocmd!
	" disable .swap files, otherwise changing tasks/notes in external files
	" won't work
	autocmd BufEnter *.vdo setlocal noswapfile
	autocmd BufWritePre *.vdo call s:AfterProjectChange()
	
	if !hasmapto('<Plug>VimdoitCheckTask')
		autocmd Filetype vimdoit nmap <buffer> <leader>X	<Plug>VimdoitCheckTask
	endif
	
	if !hasmapto('<Plug>VimdoitUncheckTask')
		autocmd Filetype vimdoit nmap <buffer> <leader><Space>	<Plug>VimdoitUncheckTask
	endif
augroup END

function! s:CheckTask()
	let l:line    = getline('.')
	let l:newline = substitute(l:line, '\v\[ \]', '\[x\]', "")
	call setline('.', l:newline)
endfunction

function! s:UncheckTask()
	let l:line    = getline('.')
	let l:newline = substitute(l:line, '\v\[x\]', '\[ \]', "")
	call setline('.', l:newline)
endfunction

command! -nargs=? GrepToday	:call s:GrepToday()

function! s:GrepToday()
	echom "grepping today"
	" grep HABIT *
	execute ":Grepper -noprompt -side -query HABIT"
endfunction

" ============
" = MAPPINGS =
" ============

if exists("g:vimdoit_loaded_mappings") == v:false
	
	noremap <silent> <unique> <script> <Plug>VimdoitCheckTask	<SID>CheckTask
	noremap <SID>CheckTask		:<c-u> call <SID>CheckTask()<CR>
	
	noremap <silent> <unique> <script> <Plug>VimdoitUncheckTask	<SID>UncheckTask
	noremap <SID>UncheckTask		:<c-u> call <SID>UncheckTask()<CR>
	
	noremap <silent> <unique> <script> <Plug>VimdoitGrepToday	<SID>GrepToday
	noremap <SID>GrepToday		:<c-u> call <SID>GrepToday()<CR>
	let g:vimdoit_loaded_mappings = 1
endif

" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo
