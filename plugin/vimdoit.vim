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

" check user option for vim plugin path
if exists("g:vimdoit_plugindir") == v:false
	echoe "Vimdoit: Option 'g:vimdoit_plugindir' not set!"
	finish
endif

" check user option for projects path
if exists("g:vimdoit_projectsdir") == v:false
	echoe "Vimdoit: Option 'g:vimdoit_projectsdir' not set!"
	finish
endif

" check user option for enabling undo/redo
if exists("g:vimdoit_undo_enable") == v:false
	let g:vimdoit_undo_enable = v:true
endif

" check if necessary tools are installed
let s:tools = ['diff', 'date', 'dateadd', 'dround', 'grep', 'git', 'sed' ]

for t in s:tools
	if trim(system("whereis ".t)) ==# t.":"
		echoe "ERRROR: ".t." not found! A lot of stuff won't work. Please install ".t."."
		finish
	endif
endfor

" check if we are in the project folder
let cwd = getcwd()
if cwd !~# '\v'.g:vimdoit_projectsdir
	finish
endif

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																Global Variables												   "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:quickfix_type = 'none'
let s:changedlines  = []
let s:syntax_errors = []
let s:parse_runtype = 'single'
let s:undo_enable   = v:false
let b:undo_event    = v:false

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																Utility Functions													 "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:InList(haystack, needle)
	for i in a:haystack
		if a:needle ==# i | return v:true | endif
	endfor | return v:false
endfunction

function! s:StackPush(list, value)
	call add(a:list, a:value)
endfunction

function! s:StackPop(list)
	if s:StackEmpty(a:list) == v:true
		return -1
	else
		let top = s:StackTop(a:list)
		call remove(a:list, -1)
		return top
	endif
endfunction

function! s:StackTop(list)
	return a:list[-1]
endfunction

function! s:StackBottom(list)
	return a:list[0]
endfunction

function! s:StackLen(list)
	return len(a:list)
endfunction

function! s:StackEmpty(list)
	if s:StackLen(a:list) == 0
		return v:true
	else
		return v:false
endfunction

function! s:StackFree(list)
	if s:StackEmpty(a:list) == v:false
		call remove(a:list, 0, -1)
	endif
endfunction

function! s:GetDatefileName()
	let filepath = expand('%:h')
	let filename = expand('%:t:r')
	return filepath.'/.'.filename.'-dates.vdo'	
endfunction

function! s:SetGrep()
	let g:vdo_grep_save = &grepprg
	set grepprg=rg\ --vimgrep
endfunction

function! s:RestoreGrep()
	let &grepprg=g:vdo_grep_save
endfunction

let s:location_stack = []
function! s:SaveLocation()
	let loc = {
				\'cursor' : getcurpos(),
				\'buffer' : bufname(),
				\'cwd'		: getcwd(),
				\'winnr'  : winnr(),
				\}
	call add(s:location_stack, loc)
endfunction

function! s:RestoreLocation()
	let loc = s:location_stack[-1]
	execute "cd ".loc['cwd']
	call win_gotoid(loc['winnr'])
	execute "buffer ".loc['buffer']
	call setpos('.', loc['cursor'])
	normal! zz
	call remove(s:location_stack, -1)
endfunction

" TODO SaveBuffers and RestoreBuffers might blow up, when we close buffers
" after SaveBuffers
function! s:SaveBuffers()
	" get list of all listed buffers
	return getbufinfo({'buflisted':1})	 
endfunction

function! s:MaybeDeleteBuffer(buffers_save)
	" get current buffer number
	let nr = bufnr()
	for b in a:buffers_save
		if b['bufnr'] == nr
			return
		endif
	endfor
	" delete buffer
	silent! bdelete
endfunction

function! s:RestoreBuffers(buffers)
	" get list of all buffers to delete, except the ones which were previously listed
	let buflist   = getbufinfo({'buflisted':1})
	let to_delete = []

	for i in buflist
		let found = v:false
		for j in a:buffers
			if i['name'] ==# j['name']
				let found = v:true
			endif
		endfor

		if found == v:false
			call add(to_delete, i)
		endif
	endfor
	
	" delete buffers
	for buf in to_delete
		execute 'silent bdelete '.buf.bufnr
	endfor
endfunction

function! s:InitBufferlist()
	echom "Initializing buffer list"
	call s:SaveLocation()
	execute 'argadd '.g:vimdoit_projectsdir.'/**/*.vdo '.g:vimdoit_projectsdir.'/**/.*.vdo'
	silent argdo silent call s:InitUndo()
	call s:RestoreLocation()
	echom "Initializing finished, vimdoit ready"
endfunction

" afer running `mv`, `rm`, `cp`, etc. we have to make sure 
" that the bufferlist is always up to date
function! s:UpdateBufferlist()
	" unload buffers where the corresponding file doesn't exist anymore
	let buffers = getbufinfo({'buflisted':1})	 
	
	for b in buffers
		" no undo files
		" TODO maybe remove?
		" echom "fullpath: ".expand('#'.b['bufnr'].':p')
		" if expand('#'.b['bufnr'].':p') =~# '\v\.undo\/'
		" 	echom "wiping buffer :".bufname(b['bufnr'])
		" 	execute "bwipeout!".b['bufnr']
		" endif

		" wipe not existing files
		if filereadable(bufname(b['bufnr'])) == v:false
			echom "wiping buffer :".bufname(b['bufnr'])
			execute "bwipeout!".b['bufnr']
		endif
	endfor
	
	" load files which are not existing
	call s:SaveLocation()
	execute 'args '.g:vimdoit_projectsdir.'/**/*.vdo '.g:vimdoit_projectsdir.'/**/.*.vdo'
	call s:RestoreLocation()
endfunction

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
	" let l:ret = system('node '.g:vimdoit_plugindir.'/src/write-zettels.js')
	" if trim(l:ret) != ""
	" 	echom l:ret
	" endif
endfunction
command! -nargs=0 WritePO	:call s:WriteZettelOverviewOfAllProjects()

function! s:WriteZettels()
	echom s:wproject_tree
	let l:data = json_encode(s:project_tree)		
	let l:ret = system('node '.g:vimdoit_plugindir.'/src/write-zettels.js -d '.shellescape(l:data))
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
  call system('node '.g:vimdoit_plugindir.'/src/generate-overviews/index.js -p '.l:fullname)
	
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
	
	echom l:padding."".a:task['text']." – ".a:task['level']
	
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

" this function is only for documentation purposes
function! s:DataNewTask()
	" a task has the following attributes and default values:
	let s:task = {	
		\ 'type'				: 'task',
		\ 'linenum'			: -1,
		\ 'line'				: '',
		\ 'id'					: -1,
		\ 'level'				: 0,
		\ 'status'			: 'todo',
		\ 'text'				: 'BE: like water',
		\ 'date'				: {},
		\ 'repetition'	: {},
		\ 'priority'		: 0,
		\ 'tags'				: [],
		\ 'waiting'			: [],
		\ 'blocking'		: v:false,
		\ 'tasks'				: [],
	\ }
	return s:task
endfunction

" this function is only for documentation purposes
function! s:DataNewNote()
	let s:note = {	
		\ 'type'				: 'note',
		\ 'linenum'			: -1,
		\ 'line'				: '',
		\ 'id'					: -1,
		\ 'level'				: 0,
		\ 'status'			: -1,
		\ 'text'				: 'BE: like water',
		\ 'date'				: {},
		\ 'repetition'	: {},
		\ 'priority'		: 0,
		\ 'tags'				: [],
		\ 'waiting'			: [],
		\ 'blocking'		: v:false,
		\ 'tasks'				: [],
	\ }
	return s:note
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

function! s:DataAddTask(task)
	" DEPRECATED: those attributes are only for compatibility purposes kept
	
	" update tasks stack according to level	
	call s:DataStackUpdate(s:tasks_stack, a:task["level"])
	" decide where to add task to (current section or current tasks)
	if len(s:tasks_stack) == 0
		let l:top = s:DataStackTop(s:sections_stack)
	else
		let l:top = s:DataStackTop(s:tasks_stack)
	endif
	" adding
	call add(l:top['tasks'], a:task)
	" add task as top of `s:task_stack`
	call s:DataStackPush(s:tasks_stack, a:task)
endfunction

function! s:DataAddNote(note)
	" update tasks stack according to level	
	call s:DataStackUpdate(s:tasks_stack, a:note["level"])
	" decide where to add note to (current section or current tasks)
	if len(s:tasks_stack) == 0
		let l:top = s:DataStackTop(s:sections_stack)
	else
		let l:top = s:DataStackTop(s:tasks_stack)
	endif
	" adding
	call add(l:top['tasks'], a:note)
	" add link as top of `s:task_stack`
	call s:DataStackPush(s:tasks_stack, a:note)
endfunction

" =========================================
" = Methods for computing additional data =
" =========================================

function! s:DataComputeProgress()
	echom "Computing progress of file ".expand('%')
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

	"skip notes
	if a:task['type'] ==# 'task'
		let a:info['num']	+= 1
		
		if a:parent == v:false
			" parent task is not done, check if current task is done
			let a:info['done'] += s:IsTaskDone(a:task) == v:true ? 1 : 0
			let l:parent = s:IsTaskDone(a:task) 
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

function! s:GenerateID(len)
	return trim(system('date "+%s%N" | sha256sum'))[0:a:len-1]
endfunction

" works like grep, but also considers unsaved changes,
" whereas grep only works on the files written to disk.
function! s:GetNumOccurences(pat)
	" save location
	call s:SaveLocation()
	" save register
	let l:save_a = @a
	" clear register a
	let @a = ''
	" find occurences
	execute 'silent! bufdo global/'.a:pat.'/yank A'
	" save  result
	let l:res = @a
	" restore register a
	let @a = l:save_a
	" restore location
	call s:RestoreLocation()
	" return found occurrences
	return len(split(l:res, '\n'))
endfunction

function! s:NewID()	
	" generate ID
	let l:id = s:GenerateID(8)
	" check if ID is already in use
	while s:GetNumOccurences('\v<0x'.l:id.'(\|\d+)?>') > 0
		let l:id = trim(system('echo '.l:id.' | sha256sum'))[0:7]
	endwhile 
	return l:id
endfunction

command! -nargs=? NewID	:call s:NewID()

function! s:ReplaceLineWithTask(task, lnum)
	" change the level accordingly
	let a:task['level'] = s:ExtractFromString(getline(a:lnum), {'level':1})['level']
	call setline(a:lnum, s:CompileTaskString(a:task))
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																		Drawer													     	"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DrawProjectStatistics()
	echom "Drawing statistics of file ".expand('%')
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
	echom "Drawing section overview of file ".expand('%')
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
"																		PARSING					                       "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:NavParsingStart()
endfunction

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

" TODO use patterns defined in `s:pat_...`
function! s:IsLineTask(line)
	let l:pattern = '\v^\s*-\s\[.*\]\s.*$'
	return a:line =~# l:pattern
endfunction

function! s:IsLineNote(line)
	let l:pattern = '\v^\s*-\s[^[].[^]].*$'
	return a:line =~# l:pattern
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

function! s:ExtractDateExact(line)
	let l:pattern = '\v\{\zs\d{4}-\d{2}-\d{2}\ze\}'
	let l:date    = []
	call substitute(a:line, l:pattern, '\=add(l:date, submatch(0))', 'g')

	if len(l:date) == 0
		return '-1'
	else
		return trim(l:date[0])
	endif
endfunction

function! s:ExtractDateFull(line)
	let l:pattern = '\v\{.*\}'
	let l:datefull    = []
	call substitute(a:line, l:pattern, '\=add(l:datefull, submatch(0))', 'g')
	return trim(l:datefull[0])
endfunction

function! s:ExtractDateId(line)
	let l:pattern = '\v0x\x{8}\|\zs\d+\ze'
	let l:dateid    = []
	call substitute(a:line, l:pattern, '\=add(l:dateid, submatch(0))', 'g')
	return trim(l:dateid[0])
endfunction

function! s:ExtractTaskName(line)
	return substitute(a:line, '\v^\s*- \[.\]\s', '', '')
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

" TODO refactor using global Extract* and Has* functions
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
	
	" extract block flags ('$block')
	let l:pattern = '\v\$block'
	let l:normal    = []
	call substitute(l:line, l:pattern, '\=add(l:flags["block"], submatch(0))', 'g')
	let l:line = substitute(l:line, l:pattern, '', 'g')
	
	" extract waiting for block flags ('~42a4')
	let l:pattern = '\v\~\x{8}'
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
	if len(l:id) > 0
		let l:flags["id"] = l:id[0]
	endif
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

function! s:IsTaskDone(task)
	return a:task['status'] ==# 'done' ? v:true : v:false
endfunction

" TODO implement that everything inside `` is discarded 

let s:pat_indendation = '\s*'
let s:pat_note = s:pat_indendation.'-\s*'
let s:pat_task = s:pat_indendation.'- \[.\]\s*'
let s:pat_notetask = s:pat_note.'(\[.\])?\s*'
let s:pat_notetaskexc = s:pat_notetask.'(!*\s*)?'
let s:pat_id = '\x{8}(\|\d+)?'
let s:pat_weekday = '((Mon|Tue|Wed|Thu|Fri|Sat|Sun)|(Mo|Di|Mi|Do|Fr|Sa|So)): '
let s:pat_date = '\d{4}-\d{2}-\d{2}'
let s:pat_time = '\d{2}:\d{2}'
let s:pat_datetime = s:pat_date.'( '.s:pat_time.')?'
let s:pat_rep_operator = '(y|mo|w|d)'
let s:pat_rep_operand = '\d+'
let s:pat_rep = '\|'.s:pat_rep_operator.':'.s:pat_rep_operand
let s:pat_flags = '\s--\s'

let s:patterns = {
	\ 'id': '\v<0x\zs'.s:pat_id.'\ze(\s|$)',
	\ 'level': '\v^\zs'.s:pat_indendation.'\ze[^\t]',
	\ 'status': '\v^'.s:pat_indendation.'- \[\zs.\ze\]',
	\ 'date': '\v^'.s:pat_notetaskexc.'\{\zs('.s:pat_weekday.')?'.s:pat_datetime.'\ze\}',
	\ 'repetition': '\v^'.s:pat_notetaskexc.'\{\zs'.s:pat_datetime.s:pat_rep.'(\|'.s:pat_datetime.')?\ze\}',
	\ 'priority': '\v!',
	\ 'flags': '\v'.s:pat_flags.'\zs.*\ze$',
	\ 'tags': '\v#\zs.{-}\ze(\s|$)',
	\ 'waiting': '\v\~\zs'.s:pat_id.'\ze(\s|$)',
	\ 'blocking': '\v\$\zsblock\ze(\s|$)',
	\ }

function! s:ExtractPatternFromString(line, pat)
	let l:extract = []
	call substitute(a:line, a:pat, '\=add(l:extract, submatch(0))', 'g')
	return l:extract
endfunction

function! s:ExtractBaseId(line)
	let flags = s:ExtractFlags(a:line)
	if len(flags) == 0
		return -1
	else
		let l:id = s:ExtractPatternFromString(flags[0], s:patterns['id'])
		if len(l:id) == 0
			return -1
		endif
		
		return substitute(l:id[0], '\v\|.*', '', '')
	endif
endfunction

function! s:ExtractId(line)
	let flags = s:ExtractFlags(a:line)
	if len(flags) == 0
		return -1
	else
		let l:id = s:ExtractPatternFromString(flags[0], s:patterns['id'])
		return len(l:id) == 0 ? -1 : l:id[0]
	endif
endfunction

function! s:ExtractLevel(line)
	let l:level = s:ExtractPatternFromString(a:line, s:patterns['level'])
	return strlen(l:level[0])
endfunction

function! s:ExtractStatus(line)
	let l:status = s:ExtractPatternFromString(a:line, s:patterns['status'])
	if l:status[0] ==# ' '
		return 'todo'
	elseif l:status[0] ==# 'x'
		return 'done'
	elseif l:status[0] ==# 'F'
		return 'failed'
	elseif l:status[0] ==# '-'
		return 'cancelled'
	else
		echoe 'Unknown task-status in line: '.a:line
	endif
endfunction

function! s:ExtractText(line)
	let text = a:line
	" remove everything before text
	let text = substitute(text, '\v'.s:pat_notetask, '', '')
	" remove everything after text
	let text = substitute(text, '\v\s*'.s:pat_flags.'*.*$', '', '')
	" remove all exclamation marks
	let text = substitute(text, '\v!', '', 'g')
	" remove leading dates
	let text = substitute(text, '\v^\s*\{.{-}\}', '', '')
	return trim(text)
endfunction

function! s:ExtractDateData(str)

	function! s:ExtractDateAttr(str, pat)
		let res = s:ExtractPatternFromString(a:str, a:pat)
		return len(res) == 0 ? -1 : res[0]
	endfunction
	
	return {
			\ 'weekday': s:ExtractDateAttr(a:str, '\v^\zs'.s:pat_weekday.'\ze'),
			\ 'date': s:ExtractDateAttr(a:str, '\v'.s:pat_date.'\ze'),
			\ 'time': s:ExtractDateAttr(a:str, '\v'.s:pat_time.'\ze'),
	\ }
endfunction

function! s:ExtractDate(line)
	let date = s:ExtractPatternFromString(a:line, s:patterns['date'])	
	return len(date) == 0 ? {} : s:ExtractDateData(date[0])
endfunction

function! s:ExtractRepetitionData(str)

	function! s:ExtractRepetitionAttr(str, pat)
		let res = s:ExtractPatternFromString(a:str, a:pat)
		return len(res) == 0 ? -1 : res[0]
	endfunction
	
	return {
			\ 'startdate': s:ExtractRepetitionAttr(a:str, '\v^\zs'.s:pat_date.'\ze'),
			\ 'starttime': s:ExtractRepetitionAttr(a:str, '\v^'.s:pat_date.' \zs'.s:pat_time.'\ze'),
			\ 'operator':  s:ExtractRepetitionAttr(a:str, '\v^'.s:pat_datetime.'\|\zs'.s:pat_rep_operator.'\ze'),
			\ 'operand':	 s:ExtractRepetitionAttr(a:str, '\v^'.s:pat_datetime.'\|'.s:pat_rep_operator.':\zs'.s:pat_rep_operand.'\ze'),
			\ 'enddate':	 s:ExtractRepetitionAttr(a:str, '\v^'.s:pat_datetime.'\|[^|]*\|\zs'.s:pat_date.'\ze'),
			\ 'endtime':	 s:ExtractRepetitionAttr(a:str, '\v^'.s:pat_datetime.'\|[^|]*\|'.s:pat_date.' \zs'.s:pat_time.'\ze'),
	\ }
endfunction

function! s:ExtractRepetition(line)
	let repetition = s:ExtractPatternFromString(a:line, s:patterns['repetition'])	
	return len(repetition) == 0 ? {} : s:ExtractRepetitionData(repetition[0])
endfunction

function! s:ExtractPriority(line)
	let priority = s:ExtractPatternFromString(a:line, s:patterns['priority'])	
	return len(priority)
endfunction

function! s:ExtractFlags(line)
	let flags = s:ExtractPatternFromString(a:line, s:patterns['flags'])	
	return flags
endfunction

function! s:ExtractTags(line)
	let flags = s:ExtractFlags(a:line)
	if len(flags) == 0
		return []
	else
		return s:ExtractPatternFromString(flags[0], s:patterns['tags'])	
	endif
endfunction

function! s:ExtractWaiting(line)
	let flags = s:ExtractFlags(a:line)
	if len(flags) == 0
		return []
	else
		return s:ExtractPatternFromString(flags[0], s:patterns['waiting'])	
	endif
endfunction

function! s:ExtractBlocking(line)
	let flags = s:ExtractFlags(a:line)
	if len(flags) == 0
		return v:false
	else
		let block = s:ExtractPatternFromString(flags[0], s:patterns['blocking'])	
		return len(block) == 0 ? v:false : v:true
	endif
endfunction

function! s:ExtractDateAttributes(line)
	return s:ExtractPatternFromString(a:line, '\v\{.{-}\}')
endfunction

function! s:ExtractDiffInsertions(str)
	return s:ExtractPatternFromString(a:str, '\v;\zs\d+\ze')
endfunction

function! s:ExtractDiffDeletions(str)
	return s:ExtractPatternFromString(a:str, '\v:\zs\d+\ze')
endfunction
	
function! s:ExtractFromString(str, ...)
	" checking parameters
	if a:0 == 0
		let all = v:true
		let what = {}
	else
		let all = v:false
		let what = a:1
	endif

	" luts for what to parse
	let lut_data = [
		\ { 'id': 's:ExtractId(a:str)' },
		\ { 'baseid': 's:ExtractBaseId(a:str)' },
		\ { 'level': 's:ExtractLevel(a:str)' },
		\ { 'status': 's:ExtractStatus(a:str)' },
		\ { 'text': 's:ExtractText(a:str)' },
		\ { 'date': 's:ExtractDate(a:str)' },
		\ { 'repetition': 's:ExtractRepetition(a:str)' },
		\ { 'priority': 's:ExtractPriority(a:str)' },
		\ { 'tags': 's:ExtractTags(a:str)' },
		\ { 'waiting': 's:ExtractWaiting(a:str)' },
		\ { 'blocking': 's:ExtractBlocking(a:str)' },
		\ { 'date-attributes': 's:ExtractDateAttributes(a:str)' },
		\ { 'insertions': 's:ExtractDiffInsertions(a:str)' },
		\ { 'deletions': 's:ExtractDiffDeletions(a:str)' },
	\ ]
	
	let data = {}

	for i in lut_data
		let [type, fnc] = items(i)[0]
		if all == v:true || has_key(what, type) && what[type] == 1
			execute 'call extend(data, {"'.type.'" : '.fnc.' })'
		endif
	endfor
	
	return data
endfunction

function! s:ExtractLineData(line)
	if s:IsLineTask(a:line) == v:true
		return s:ExtractTaskData(a:line)
	elseif s:IsLineNote(a:line) == v:true
		return s:ExtractNoteData(a:line)
	else
		echoerr "Line is neigher task nor note: ".a:line
	endif
endfunction

function! s:ExtractTaskData(line)
	let data = s:ExtractFromString(a:line, {
		\ 'id' : 1,
		\ 'level' : 1,
		\ 'status' : 1,
		\ 'text' : 1,
		\ 'date' : 1,
		\ 'repetition' : 1,
		\ 'priority' : 1,
		\ 'tags' : 1,
		\ 'waiting' : 1,
		\ 'blocking' : 1,
		\ })
	let task = extend(s:DataNewTask(), data)
	return task
endfunction

function! s:ExtractNoteData(line)
	let data = s:ExtractFromString(a:line, {
		\ 'id' : 1,
		\ 'level' : 1,
		\ 'text' : 1,
		\ 'date' : 1,
		\ 'repetition' : 1,
		\ 'priority' : 1,
		\ 'tags' : 1,
		\ 'waiting' : 1,
		\ 'blocking' : 1,
		\ })
	let note = extend(s:DataNewNote(), data)
	return note
endfunction

function! s:ErrorLine(linenum)
	execute 'normal '.a:linenum.'gg0'
	execute 'syntax match VdoError "\v%'.a:linenum.'l.*"'
	highlight link VdoError Error
endfunction

function! s:SyntaxError(linenum, msg)
	let entry = {
				\'bufnr': bufnr(),
				\'filename': expand('%'),
				\'lnum': a:linenum,
				\'text': a:msg,
				\'type': 'E'
				\}
	call s:ErrorLine(a:linenum)
	call add(s:syntax_errors, entry)
endfunction

" TODO implement syntax check of other attributes
" currently implemented:
" - [x] check: only one date attribute per task/note
" - [x] check: for anything before the date, except `!` and whitespaces
" - [x] check: correct date format
" - [x] check: correct repetition format
" - [ ] check for matching characters: `"'<([{
" - [ ] check for any symbols before the first `-`
" - [ ] check for valid `- [ ]`
" - [ ] check for valid waiting
" - [ ] check for valid block
" - [ ] check for valid id
" - [ ] check for valid

function! s:CheckSyntaxSingle(line, linenu)
	
	" remove everything between ``
	let line = substitute(a:line, '\v`[^`]{-}`', '', 'g')

	" check if task/note has a valid indicator (`- …` or `- [ ]`)
	if line =~# '\v^\s*-\zs[^ -]\ze(\[.\])?'
		return 'Invalid task/note indicator (`- …` or `- [ ]`). Maybe you used tabs instead of spaces?'
	endif

	" extract date attributes
	let date_attributes = s:ExtractDateAttributes(line)
	
	" check if the task has multiple date-attributes (`{...}´)
	if len(date_attributes) > 1
		return "Multiple dates."
	" check if task has a date or repetition
	elseif len(date_attributes) == 1
		let pass = v:false
		
		" remove task/note indicator
		let line2 = substitute(line, '\v('.s:pat_task.'|'.s:pat_note.')', '', '')
		
		" check for any characters except `!` before the date-attribute
		" remove all `!` and spaces before date-attribute
		let line3 = substitute(line2, '\v(!|\s)', '', 'g')
		" check
		if line3 =~# '\v^\zs.+\ze\{.*\}'
			return "Forbidden characters before the date-attribute. Allowed characters: ! and whitespaces."
		endif

		" check if it is a valid date
		let date = date_attributes[0]
		if date =~# '\v\{\zs('.s:pat_weekday.')?'.s:pat_datetime.'\ze\}'
			let pass = v:true
		" check if it is a valid repetition
		elseif date =~# '\v^\{\zs'.s:pat_datetime.s:pat_rep.'(\|'.s:pat_datetime.')?\ze\}'
			let pass = v:true
		endif

		if pass == v:false
			return 'Invalid date or repetition.'
		endif
	endif

	return ''

endfunction

function! s:CheckSyntax(line, linenum)
	
	" remove everything between ``
	let line = substitute(a:line, '\v`[^`]{-}`', '', 'g')

	" check if task/note has a valid indicator (`- …` or `- [ ]`)
	if line =~# '\v^\s*-\zs[^ -]\ze(\[.\])?'
		call s:SyntaxError(a:linenum, 'Invalid task/note indicator (`- …` or `- [ ]`). Maybe you used tabs instead of spaces?')
		return
	endif

	" extract date attributes
	let date_attributes = s:ExtractDateAttributes(line)
	
	" check if the task has multiple date-attributes (`{...}´)
	if len(date_attributes) > 1
		call s:SyntaxError(a:linenum, "Multiple dates.")
		return
	" check if task has a date or repetition
	elseif len(date_attributes) == 1
		let pass = v:false
		
		" remove task/note indicator
		let line2 = substitute(line, '\v('.s:pat_task.'|'.s:pat_note.')', '', '')
		
		" check for any characters except `!` before the date-attribute
		" remove all `!` and spaces before date-attribute
		let line3 = substitute(line2, '\v(!|\s)', '', 'g')
		" check
		if line3 =~# '\v^\zs.+\ze\{.*\}'
			call s:SyntaxError(a:linenum, "Forbidden characters before the date-attribute. Allowed characters: ! and whitespaces.")
			return
		endif

		" check if it is a valid date
		let date = date_attributes[0]
		if date =~# '\v\{\zs('.s:pat_weekday.')?'.s:pat_datetime.'\ze\}'
			let pass = v:true
		" check if it is a valid repetition
		elseif date =~# '\v^\{\zs'.s:pat_datetime.s:pat_rep.'(\|'.s:pat_datetime.')?\ze\}'
			let pass = v:true
		endif

		if pass == v:false
			call s:SyntaxError(a:linenum, 'Invalid date or repetition.' )
			return
		endif
	endif

endfunction

" use like: `bufdo ParseFile`
" you should clear your quickfix list first
command! ParseFile :call s:ParseFileGlobal()
" this function should only be called from the user-command ParseFile
function! s:ParseFileGlobal()
	call s:ParseFile()
	if len(s:syntax_errors) > 0
		call setqflist(s:syntax_errors, 'a')
		echoerr "Syntax errors in ".expand('%').". See error list."
	endif

	if len(getqflist()) == 0
		" remove error highlights
		highlight link VdoError None
	endif
endfunction

function! s:ParseFile()

	let s:syntax_errors = []
	echom "Parsing file ".expand('%')

	call s:SaveLocation()
	call s:DataInit()
	
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
			call s:CheckSyntax(l:line, l:i)
			let l:task = s:ExtractTaskData(l:line)
			let l:task = extend(l:task, { 'linenum': l:i, 'line': l:line })
			call s:DataAddTask(l:task)
			let l:i += 1
			continue
		endif
		
		" is line a Note?	
		if s:IsLineNote(l:line) == v:true
			call s:CheckSyntax(l:line, l:i)
			let l:note = s:ExtractNoteData(l:line)
			let l:note = extend(l:note, { 'linenum': l:i })
			call s:DataAddNote(l:note)
			let l:i += 1
			continue
		endif

		let l:i += 1
	endwhile

	let l:last_section        = s:DataUpdateEndOfEachSection(s:project_tree["sections"])
	let l:last_section['end'] = line('$')

	call s:RestoreLocation()
endfunction

function! s:NavParsingEnd()
endfunction

function! s:IsDateFile()
	" check if this is a datefile
	let basename = expand('%:t:r')
	return basename =~# '\v\..*-date'
endfunction

function! s:IsUndoFile()
	" check if this is a datefile
	let basename = expand('%:p')
	return basename =~# '\v.*\.undo\/'
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                        Quickfix Manipulation                          "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:GetQfTitle()
	if exists("w:quickfix_title")
		return w:quickfix_title
	else
		copen
		return w:quickfix_title
	endif
endfunction

function! s:HasQfTitleKey(title, key)
	if a:title =~# '\v\| '.a:key.': .*'
		return v:true
	else
		return v:false
	endif
endfunction

function! s:ModifyQfTitle(title, action, key, value)

	if a:action ==# 'add'
		if s:HasQfTitleKey(a:title, a:key) == v:true
			" modify
			return substitute(a:title, '\v'.a:key.': .*($|\|)', a:key.': '.a:value, '')	
		else
			" append
			return a:title." | ".a:key.": ".a:value
		endif
	elseif a:action ==# 'remove'
		" remove
	endif
	
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                              Sorting                                  "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


function! s:SortQuickfix()
	let selections = [
				\ 'priority',
				\ 'project',
				\ 'date',
				\ 'due date (only projects)',
				\ 'start date (only projects)',
				\ 'completion date (only projects)',
				\ ]
	let selections_dialog = [
				\ '&priority',
				\ 'p&roject',
				\ '&date',
				\ 'd&ue date (only projects)',
				\ '&start date (only projects)',
				\ '&completion date (only projects)',
				\ ]
	let input = confirm('Sort Quickfix List by', join(selections_dialog, "\n"))
	
	let l:qf = getqflist()
	let title = s:GetQfTitle()

	if selections[input-1] ==# 'priority'
		echom "Sorting by Priority."
		call sort(l:qf, 's:CmpQfByPriority')
		let title = s:ModifyQfTitle(title, 'add', 'sort', 'priority')
	elseif selections[input-1] ==# 'project'
		call sort(l:qf, 's:CmpQfByProject')
		echom "Sorting by Project"
		let title = s:ModifyQfTitle(title, 'add', 'sort', 'project')
	elseif selections[input-1] ==# 'date'
		call sort(l:qf, 's:CmpQfByDate')
		echom "Sorting by Date"
		let title = s:ModifyQfTitle(title, 'add', 'sort', 'date')
	elseif selections[input-1] ==# 'due date (only projects)'
		if s:quickfix_type ==# 'project'
			call sort(l:qf, 's:CmpQfByDueDate')
			echom "Sorting by Due Date (Only Projects)"
			let title = s:ModifyQfTitle(title, 'add', 'sort', 'due date')
		else
			echoe "Quickfix List is not of type project."	
			return
		endif
	elseif selections[input-1] ==# 'start date (only projects)'
		if s:quickfix_type ==# 'project'
			call sort(l:qf, 's:CmpQfByStartDate')
			echom "Sorting by Start Date (Only Projects)"
			let title = s:ModifyQfTitle(title, 'add', 'sort', 'start date')
		else
			echoe "Quickfix List is not of type project."	
			return
		endif
	elseif selections[input-1] ==# 'completion date (only projects)'
		if s:quickfix_type ==# 'project'
			call sort(l:qf, 's:CmpQfByCompletionDate')
			echom "Sorting by Completion Date (Only Projects)"
			let title = s:ModifyQfTitle(title, 'add', 'sort', 'completion date')
		else
			echoe "Quickfix List is not of type project."	
			return
		endif
	endif
	
	" replace list
	call setqflist(l:qf, 'r')	
	
endfunction

function! s:GetNumExclamations(str)
	let l:pattern  = '\v!'
	let l:marks  = []
	call substitute(a:str, l:pattern, '\=add(l:marks, submatch(0))', 'g')
	return len(l:marks)
endfunction

function! s:CmpQfByPriority(e1, e2)
	" TODO use s:ExtractPriority
	let [t1, t2] = [s:GetNumExclamations(a:e1.text), s:GetNumExclamations(a:e2.text)]
	return t1 ># t2 ? -1 : t1 ==# t2 ? 0 : 1
endfunction

function! s:CmpQfByProject(e1, e2)
	let [t1, t2] = [bufname(a:e1.bufnr), bufname(a:e2.bufnr)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:GetDateOnly(str)
	let l:pattern  = '\v\{.*\zs(\d{4}-\d{2}-\d{2})\ze.*\}'
	let l:date  = []
	call substitute(a:str, l:pattern, '\=add(l:date, submatch(0))', 'g')

	if len(l:date) != 0
		return trim(l:date[0])
	else
		return v:false
	endif
endfunction

function! s:GetDateAndTime(str)
	let l:pattern  = '\v\{.*\zs(\d{4}-\d{2}-\d{2}).*(\d{2}:\d{2})?\ze\}'
	let l:date  = []
	call substitute(a:str, l:pattern, '\=add(l:date, submatch(0))', 'g')

	if len(l:date) != 0
		return trim(l:date[0])
	else
		return v:false
	endif
endfunction

function! s:CmpQfByDate(e1, e2)
	let [t1, t2] = [s:GetDateAndTime(a:e1.text), s:GetDateAndTime(a:e2.text)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:CmpQfById(e1, e2)
	let [t1, t2] = [s:ExtractId(a:e1.text), s:ExtractId(a:e2.text)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:GetDueDate(str)
	let l:pattern  = '\v\%\zs(\d{4}-\d{2}-\d{2})\ze'
	let l:date  = []
	call substitute(a:str, l:pattern, '\=add(l:date, submatch(0))', 'g')

	if len(l:date) != 0
		return trim(l:date[0])
	else
		return v:false
	endif
endfunction

function! s:CmpQfByDueDate(e1, e2)
	let [t1, t2] = [s:GetDueDate(a:e1.text), s:GetDueDate(a:e2.text)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:GetStartDate(str)
	let l:pattern  = '\v\^\zs(\d{4}-\d{2}-\d{2})\ze'
	let l:date  = []
	call substitute(a:str, l:pattern, '\=add(l:date, submatch(0))', 'g')

	if len(l:date) != 0
		return trim(l:date[0])
	else
		return v:false
	endif
endfunction

function! s:CmpQfByStartDate(e1, e2)
	let [t1, t2] = [s:GetStartDate(a:e1.text), s:GetStartDate(a:e2.text)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:GetCompletionDate(str)
	let l:pattern  = '\v\$\zs(\d{4}-\d{2}-\d{2})\ze'
	let l:date  = []
	call substitute(a:str, l:pattern, '\=add(l:date, submatch(0))', 'g')

	if len(l:date) != 0
		return trim(l:date[0])
	else
		return v:false
	endif
endfunction

function! s:CmpQfByCompletionDate(e1, e2)
	let [t1, t2] = [s:GetCompletionDate(a:e1.text), s:GetCompletionDate(a:e2.text)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                              Grepping                                 "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:GrepProjectsByTag(tag, path)

	call vimdoit_utility#SaveOptions()
	
	execute "cd ".a:path

	let &grepprg='rg --vimgrep --pre '.g:vimdoit_plugindir.'/scripts/pre-head.sh'
	
	if a:tag ==# 'all'
		let pattern = '"^.*$"'
		let title = "projects: all"
	elseif a:tag ==# 'not tagged'
		let pattern = '^\<.*\>[[:space:]]*$'
		let title = "projects: not tagged"
	elseif a:tag ==# 'not complete or cancelled or archived'
		let pattern = '"\#complete\|\#cancelled\|\#archived"'
		let &grepprg='rg --vimgrep --invert-match --pre '.g:vimdoit_plugindir.'/scripts/pre-head.sh'
		let title = "projects: not complete or cancelled or archived"
	else
		let pattern = '"^<.*>.*\#'.a:tag.'"'
		let title = "projects: #".a:tag
	endif

	" grep
	execute 'grep! --type-add '"vimdoit:*.vdo"' -t vimdoit '.pattern.' ' | copen
	
	" sort by priority
	let l:qf  = getqflist()
	call sort(l:qf, 's:CmpQfByPriority')
	let title = s:ModifyQfTitle(title, 'add', 'sort', 'priority')
	call setqflist(l:qf, 'r')	
	let s:quickfix_type = 'project'
	call s:SetQfSyntax()

	call vimdoit_utility#RestoreOptions()
endfunction
command! -nargs=? GrepFocused	:call s:GrepProjectsByTag()

function! s:GrepTasksWithInvalidDate(path)

	call vimdoit_utility#SaveCfStack()
	call vimdoit_utility#SaveOptions()

	" set grep format
	call s:SetGrep()
	
	if a:path ==# '%'
		let datefile = s:GetDatefileName()
		let file = '% '.datefile
	else
		let file = ''
		execute "cd ".a:path
	endif	
	
	" 1. grep all dates
	let pattern = "\\{.*\\}"
	execute 'silent! grep! --type-add '"vimdoit:*.vdo"' -t vimdoit "'.pattern.'" '.file
	let l:qf_all = getqflist()

	if len(l:qf_all) == 0
		call vimdoit_utility#RestoreCfStack()
		call vimdoit_utility#RestoreOptions()
		call s:RestoreGrep()
		return
	endif


	" 2. grep all valid dates
	let pattern = "\\{.*\\d{4}-\\d{2}-\\d{2}.*\\}"
	execute 'silent! grep! --type-add '"vimdoit:*.vdo"' -t vimdoit "'.pattern.'" '.file | copen
	let l:qf_valid = getqflist()

	if len(l:qf_valid) == 0
		call vimdoit_utility#RestoreCfStack()
		call vimdoit_utility#RestoreOptions()
		call s:RestoreGrep()
		return
	endif

	" 3. filter valid dates from all
	let l:qf_new = []
	for d in l:qf_all

		let l:found = v:false
		
		for e in l:qf_valid
			if e.text ==# d.text
				let l:found = v:true
			endif
		endfor

		if l:found == v:false
			call add(l:qf_new, d)
		endif

	endfor
	
	call vimdoit_utility#RestoreCfStack()
	
	" push new list
	" call setqflist(l:qf_new, 'a', {'title' : 'tasks: invalid date'})
	call setqflist(l:qf_new, 'a')
	
	call vimdoit_utility#RestoreOptions()
	call s:RestoreGrep()
endfunction

function! s:HasRange(text)
	if a:text =~# '\v\{.*\d{4}-\d{2}-\d{2}.*\}-\{.*\d{4}-\d{2}-\d{2}.*\}'		
		return v:true
	else
		return v:false
	endif
endfunction

function! s:NicenQfByDate(qf)
	
	let idx = 0
	let day_prev = ''
	let week_prev = ''
	let month_prev = ''
	let year_prev = ''
	while idx < len(a:qf)

		let date = s:ExtractDate(a:qf[idx].text)
		" TODO remove #cur
		" CHECK: syntax where the date is placed! Otherwise the following will
		" throw errors
		if empty(date) == v:true
			echom a:qf[idx].text
		endif
		
		let day = trim(system('date --date='.date['date'].' +%A'))
		let week = trim(system('date --date='.date['date'].' +%V'))
		let month = trim(system('date --date='.date['date'].' "+%B"'))
		let year = trim(system('date --date='.date['date'].' +%Y'))

		let inc = 1
		let insert = []

		if day_prev !=# day
			call add(insert, day.', '.date['date'].':')
			call add(insert, '')
		endif
		
		if week_prev !=# week
			call add(insert, '')
			call add(insert, '--------------------------------------')
			call add(insert, '-							Woche '.week.'	 					  -')
			call add(insert, '--------------------------------------')
			call add(insert, '')
		endif
		
		if month_prev !=# month
			call add(insert, '')
			call add(insert, '======================================')
			call add(insert, '=						'.month.' '.year.'						=')
			call add(insert, '======================================')
			call add(insert, '')
		endif
		
		for i in insert
			call insert(a:qf, {'text' : i}, idx)
			let inc = inc + 1
		endfor

		let idx = idx + inc
		let day_prev = day
		let week_prev = week
		let month_prev = month
		let year_prev = year
	endwhile
	
endfunction

function! s:GrepTasksByStatus(status, path)

	call vimdoit_utility#SaveOptions()
	call s:SetGrep()

	if a:path ==# '%'
		let datefile = s:GetDatefileName()
		if filereadable(datefile) == v:true
			let file = '% '.datefile
		else
			let file = '%'
		endif
	else
		let file = ''
		execute "cd ".a:path
	endif	
	
	let pattern = ""

	if a:status ==# 'all'
		let pattern = "\\- \\[.\\]"
		let title = 'tasks: all'
	elseif a:status ==# 'todo'
		let pattern = "\\- \\[ \\]" 
		let title = 'tasks: todo'
	elseif a:status ==# 'done'
		let pattern = "\\- \\[x\\]"
		let title = 'tasks: done'
	elseif a:status ==# 'failed'
		let pattern = "\\- \\[F\\]"
		let title = 'tasks: failed'
	elseif a:status ==# 'cancelled'
		let pattern = "\\- \\[-\\]"
		let title = 'tasks: cancelled'
	elseif a:status ==# 'next'
		let pattern = "[\\#]next"
		let title = 'tasks: #next'
	elseif a:status ==# 'current'
		let pattern = "[\\#]cur"
		let title = 'tasks: #cur'
	elseif a:status ==# 'waiting'
		let pattern = "~\\x{4}"
		let title = 'tasks: waiting'
	elseif a:status ==# 'block'
		let pattern = "[$]\\x{4}"
		let title = 'tasks: block'
	elseif a:status ==# 'scheduled'
		let pattern = "\\{.*\\}"
		let title = 'tasks: scheduled'
	elseif a:status ==# 'date'
		" let pattern = "\\{\\(\\(Mo\\|Di\\|Mi\\|Do\\|Fr\\|Sa\\|So\\):\\s\\)?\\d{4}-\\d{2}-\\d{2}(\\s*\\d{2}:\\d{2})?\\s*\\}"
		let pattern = '\{.*\}'
		" let pattern = "\\{.*?\\}"
		" let pattern = escape(s:patterns['date'], '{\}(|)')
		let title = 'tasks: date'
	elseif a:status ==# 'repetition'
		let pattern = "\\{\\s*\\d{4}-\\d{2}-\\d{2}\\\\|[a-z]{1,2}:.*\\}"
		let title = 'tasks: repetition'
	endif
	
	execute 'silent! grep! --pre '.g:vimdoit_plugindir.'/scripts/pre-project.sh --type-add '"vimdoit:*.vdo"' -t vimdoit '.shellescape(pattern).' '.file | copen

	let l:qf = getqflist()

	if a:status ==# 'date'
		" sort by date
		call sort(l:qf, 's:CmpQfByDate')
		let title = s:ModifyQfTitle(title, 'add', 'sort', 'date')
		let s:quickfix_type = 'date'
	else
		" sort by priority
		call sort(l:qf, 's:CmpQfByPriority')
		let title = s:ModifyQfTitle(title, 'add', 'sort', 'priority')
		let s:quickfix_type = 'task'
	endif
	
	" push list
	call setqflist(l:qf, 'r')	
	call s:SetQfSyntax()

	call vimdoit_utility#RestoreOptions()
	call s:RestoreGrep()
endfunction

function! s:GrepProjects(all)

	if a:all == v:true
		let path = g:vimdoit_projectsdir
	else
		let path = getcwd()
	endif

	let path_nicened = substitute(path, '\v'.g:vimdoit_projectsdir, '', '')

	if path_nicened ==# ''
		let path_nicened = '/'
	endif

	let selections = [
				\ 'all',
				\ 'active',
				\ 'focus',
				\ 'complete',
				\ 'cancelled',
				\ 'archived',
				\ 'not complete or cancelled or archived',
				\ 'not tagged',
				\ ]
	let selections_dialog = [
				\ '&all',
				\ 'ac&tive',
				\ '&focus',
				\ '&complete',
				\ 'ca&ncelled',
				\ 'a&rchived',
				\ 'not co&mplete or cancelled or archived',
				\ 'n&ot tagged',
				\ ]
	
	let input  = confirm('Searching Projects in '.shellescape(path_nicened).'', join(selections_dialog, "\n"))
	call s:GrepProjectsByTag(selections[input-1], path)
	
endfunction

function! s:GrepTasks(where)
	
	if a:where ==# 'project'
		let path = '%'
	elseif a:where ==# 'area'
		let path = getcwd()
	else
		let path = g:vimdoit_projectsdir
	endif
	
	let path_nicened = substitute(path, '\v'.g:vimdoit_projectsdir, '', '')

	if path_nicened ==# ''
		let path_nicened = '/'
	endif

	let selections = [
				\ 'all',
				\ 'todo',
				\ 'done',
				\ 'failed',
				\ 'cancelled',
				\ 'next',
				\ 'current',
				\ 'waiting',
				\ 'block',
				\ 'scheduled',
				\ 'date',
				\ 'repetition',
				\ 'invalid date',
				\ ]
	let selections_dialog = [
				\ '&all',
				\ '&todo',
				\ '&done',
				\ '&failed',
				\ '&cancelled',
				\ '&next',
				\ 'cu&rrent',
				\ '&waiting',
				\ '&block',
				\ '&scheduled',
				\ 'dat&e',
				\ 're&petition',
				\ '&invalid date',
				\ ]
	
	let input = confirm('Searching Tasks in '.shellescape(path_nicened).'', join(selections_dialog, "\n"))

	if selections[input-1] ==# 'invalid date'
		call s:GrepTasksWithInvalidDate(path)
	else
		call s:GrepTasksByStatus(selections[input-1], path)
	endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                               Filtering                               "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:SetQfSyntax()
	
	if exists('w:quickfix_title') == v:false
		return
	endif
	
	" :set conceallevel=2 concealcursor=nc
	syntax match qfFileName "\v^.{-}\|\d+\scol\s\d+\|" conceal
	syntax match Bars "\v^\|\|" conceal

	syntax match CalendarDateAndTime "\v\w*, \d{4}-\d{2}-\d{2}:"
	highlight link CalendarDateAndTime Operator

	syntax match CalendarText "\v(\s{3,}\w+\s\d+\s{3,})" contained
	highlight link CalendarText Operator
	syntax match CalendarWeek "\v(-{38}|\={38})"
	syntax match CalendarWeek "\v\s(-|\=)(\s{3,}\w+\s\d+\s{3,})(-|\=)$" contains=CalendarText
	highlight link CalendarWeek Identifier
	
	syntax match SectionHeadlineDelimiter "\v\<" contained conceal
	syntax match SectionHeadlineDelimiter "\v\>" contained conceal
	syntax match SectionHeadline "\v\<[^\>]*\>" contains=SectionHeadlineDelimiter
	highlight link SectionHeadline Operator
	highlight link SectionHeadlineDelimiter Comment
	syntax region FlagRegionHeadline start="\v\<[^\>]*\>" end="$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagInProgress,FlagSprint,FlagTag,FlagID,SectionHeadline
	
	" Percentages
	syntax match Percentages "\v\[.*\%\]"
	highlight link Percentages Comment
	" Exclamation Mark
	syntax match ExclamationMark "\v!+"
	highlight link ExclamationMark Tag
	" Info
	syntax match Info "\v\u+[?!]*(\s\u+[?!]*)*:"
	highlight link Info Todo
	" Code
	syntax match Code "\v`.{-}`"
	highlight link Code Comment
	" Strings
	syntax match VimdoitString "\v[ \t]\zs['"].{-}['"]\ze[ \t,.!:\n]" contains=SingleSinglequote
	highlight link VimdoitString String
	" Time
	syntax match Date "\v\{.{-}\}"
	highlight link Date Constant
	" URLs
	syntax match URL `\v<(((https?|ftp|gopher)://|(mailto|file|news):)[^' 	<>"]+|(www|web|w3)[a-z0-9_-]*\.[a-z0-9._-]+\.[^' 	<>"]+)[a-zA-Z0-9/]`
	highlight link URL String
	" Flag Delimiter ('--')
	syntax match FlagDelimiter "\v\s--\s" contained
	highlight link FlagDelimiter Comment
	" Flag Normal ('-flag')
	syntax match Flag "\v\zs-.*\ze\s" contained
	highlight link Flag Comment
	" Flag Sprint ('@sprint')
	syntax match FlagSprint '\v\@[^ \t]+'
	syntax match FlagSprint "\v\@today" contained
	syntax match FlagSprint "\v\@week" contained
	highlight link FlagSprint Constant
	" Flag Block ('$23')
	syntax match FlagBlock "\v\$\d+" contained
	highlight link FlagBlock Orange
	" Flag Waiting For Block ('~23')
	syntax match FlagWaiting "\v\~\d+" contained
	highlight link FlagWaiting String
	" Flag ID ('0x8c3d19d5')
	syntax match FlagID "\v0x\x{8}(\|\d+)?" contained conceal
	highlight link FlagID NerdTreeDir
	" Flag ordinary tag ('#SOMESTRING')
	syntax match FlagTag "\v#[^ \t]*" contained
	highlight link FlagTag Identifier
	" Flag Region
	syntax region FlagRegion start="\v\s--\s" end="$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagInProgress,FlagSprint,FlagTag,FlagID
	highlight link FlagRegion NerdTreeDir
	" Task Block
	syntax match TaskBlock "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*\$\d+" contains=ExclamationMark,Info,Date
	highlight link TaskBlock Orange
	" Task Waiting
	syntax match TaskWaiting "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*\~\d+" contains=ExclamationMark,Info,Date
	highlight link TaskWaiting String
	" Task Done
	syntax region TaskDone start="\v- \[x\]+" skip="\v^\t{1,}" end="^" contains=FlagID
	" Task Failed	
	syntax match TaskFailedMarker "\v\[F\]" contained
	highlight link TaskFailedMarker Error
	syntax region TaskFailed start="\v- \[F\]+" skip="\v^\t{1,}" end="^" contains=TaskFailedMarker,FlagID
	" Task Cancelled
	syntax match TaskCancelledMarker "\v\[-\]" contained
	syntax region TaskCancelled start="\v- \[-\]+" skip="\v^\t{1,}" end="^" contains=TaskCancelledMarker,FlagID
	" ... 
	highlight link TaskDone NerdTreeDir
	highlight link TaskFailed NerdTreeDir
	highlight link TaskCancelled NerdTreeDir

endfunction
command! -nargs=0 VdoSetQfSyntax	:call s:SetQfSyntax()

" TODO USE: ExtractFromLine()
function! s:FilterQuickfix()

	function! Todo(idx, val)
		if a:val["text"] !~# '\v\- \[ \]'
			return v:false
		else
			return v:true
		endif
	endfunction
	
	function! Done(idx, val)
		if a:val["text"] !~# '\v\- \[x\]'
			return v:false
		else
			return v:true
		endif
	endfunction
	
	function! Failed(idx, val)
		if a:val["text"] !~# '\v\- \[F\]'
			return v:false
		else
			return v:true
		endif
	endfunction
	
	function! Cancelled(idx, val)
		if a:val["text"] !~# '\v\- \[-\]'
			return v:false
		else
			return v:true
		endif
	endfunction

	function! HasSameID(e1, e2)
		let [t1, t2] = [s:ExtractId(a:e1.text), s:ExtractId(a:e2.text)]
		return t1 ==# t2 ? 0 : 1
	endfunction

	function! Today(idx, val)
		let date  = s:GetDateOnly(a:val.text)
		let today = strftime("%Y-%m-%d")
		if date ==# today
			return v:true
		else
			return v:false
		endif
	endfunction

	function! Tomorrow(idx, val)
		let date     = s:GetDateOnly(a:val.text)
		let today    = strftime("%Y-%m-%d")
		let tomorrow = trim(system('dateadd '.shellescape(today).' +1d'))
		if date ==# tomorrow
			return v:true
		else
			return v:false
		endif
	endfunction

	function! ThisWeek(idx, val)
		let date   = s:GetDateOnly(a:val.text)
		let today  = strftime("%Y-%m-%d")
		let monday = trim(system('dround '.shellescape(today).' -- -Mon'))
		let sunday = trim(system('dround '.shellescape(today).' -- Sun'))
		if date >=# monday && date <=# sunday
			return v:true
		else
			return v:false
		endif
	endfunction

	function! NextWeek(idx, val)
		let date           = s:GetDateOnly(a:val.text)
		let today          = strftime("%Y-%m-%d")
		let todayinoneweek = trim(system('dateadd '.shellescape(today).' +7d'))
		let nextmonday     = trim(system('dround '.shellescape(todayinoneweek).' -- -Mon'))
		let nextsunday     = trim(system('dround '.shellescape(todayinoneweek).' -- Sun'))
		if date >=# nextmonday && date <=# nextsunday
			return v:true
		else
			return v:false
		endif
	endfunction
	
	function! ThisMonth(idx, val)
		let date             = s:GetDateOnly(a:val.text)
		let today            = strftime("%Y-%m-%d")
		let firstofmonth     = trim(system('dround '.shellescape(today).' /-1mo'))
		let firstofnextmonth = trim(system('dround '.shellescape(today).' /1mo'))
		if date >=# firstofmonth && date <# firstofnextmonth
			return v:true
		else
			return v:false
		endif
	endfunction
	
	function! Upcoming(idx, val)
		let date = s:GetDateAndTime(a:val.text)
		let now = strftime('%Y-%m-%d')
		if date <# now
			return v:false
		else
			return v:true
		endif
	endfunction
	
	function! Past(idx, val)
		let upcoming = Upcoming(a:idx, a:val)
		if upcoming == v:true
			return v:false
		else
			return v:true
		endif
	endfunction

	" get qf list
	let l:qf = getqflist()
	
	" abort if no entries
	if len(l:qf) == 0
		echoe "Empty Quickfix List."
		return
	endif
	
	let selections = [
				\ 'todo',
				\ 'done',
				\ 'failed',
				\ 'cancelled',
				\ 'unique',
				\ 'today*',
				\ 'tomorrow*',
				\ 'this week*',
				\ 'next week*',
				\ 'this month*',
				\ 'upcoming*',
				\ 'past*',
				\ 'nicen',
				\ 'syntax',
				\ ]
	let selections_dialog = [
				\ '&todo',
				\ '&done',
				\ '&failed',
				\ '&cancelled',
				\ '&unique',
				\ 't&oday*',
				\ 'to&morrow*',
				\ 't&his week*',
				\ 'n&ext week*',
				\ 'th&is month*',
				\ 'u&pcoming*',
				\ 'p&ast*',
				\ '&nicen',
				\ 'synta&x',
				\ ]
	let input  = confirm('Filter Quickfix List by', join(selections_dialog, "\n"))

	if selections[input-1] ==# 'todo'
		call filter(l:qf, function('Todo'))
	elseif selections[input-1] ==# 'done'
		call filter(l:qf, function('Done'))
	elseif selections[input-1] ==# 'failed'
		call filter(l:qf, function('Failed'))
	elseif selections[input-1] ==# 'cancelled'
		call filter(l:qf, function('Cancelled'))
	elseif selections[input-1] ==# 'unique'
		call sort(l:qf, function('s:CmpQfById'))
		call uniq(l:qf, function('HasSameID'))
		if s:quickfix_type ==# 'date'
			call sort(l:qf, function('s:CmpQfByDate'))
		else
			call sort(l:qf)
		endif
	elseif selections[input-1] ==# 'today*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('Today'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'tomorrow*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('Tomorrow'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'this week*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('ThisWeek'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'next week*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('NextWeek'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'this month*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('ThisMonth'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'upcoming*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('Upcoming'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'past*'
		if s:quickfix_type ==# 'date'
			call filter(l:qf, function('Past'))
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'nicen'
		if s:quickfix_type ==# 'date'
			call s:NicenQfByDate(l:qf)
		else
			echoe "Quickfix List is not of type date."
			return
		endif
	elseif selections[input-1] ==# 'syntax'
		call s:SetQfSyntax()
	endif
	
	" push list
	call setqflist(l:qf)
	call s:SetQfSyntax()
	
endfunction

function! s:JumpToToday()

	if s:quickfix_type !=# 'date'
		echoe "Quickfix List is not of type date."
		return
	endif
	
	" jump to today
	let today = strftime('%Y-%m-%d')
	while search('\v'.today) == 0 
		let today = trim(system('dateadd '.shellescape(today).' +1d'))
	endwhile

	execute "normal! 0"
		
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                           Modyifing Tasks                             "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:PrependSelectionWithNumbers(selection)
	let new = []
	let num = 1
	for i in a:selection
		call add(new, '['.num.'] '.i)	
		let num = num + 1
	endfor
	return new
endfunction

function! s:ModifyTaskWaitingRemove(lines)
	for i in a:lines
		let blocks = s:ExtractFromString(getline(i), {'waiting' : 1})
		let blocks_selection = s:PrependSelectionWithNumbers(blocks)
		let blocks_selection = extend(blocks_selection, ['all'], 0)
		let input = confirm('Select ID(s) for "'.getline(i).'": ', join(blocks_selection, "\n"))

		if blocks_selection[input-1] ==# 'all'
			" remove all
			execute i.'substitute/\v \~\x{8}//g'
		else
			" remove specific
			execute i.'substitute/\v \~'.blocks[input-2].'//'
		endif
	endfor
endfunction

function! s:AddTaskBlocking(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task             = s:ExtractLineData(line)
		let task['blocking'] = v:true
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:AddTaskWaiting(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task = s:ExtractLineData(line)
		call add(task['waiting'], @+)
		call sort(task['waiting'])
		call uniq(task['waiting'])
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:Input(msg)
	let input = ''
	
	let char = ''
	" 13 = Enter
	while char != 13
		
		" 8 = <C-Bs>
		if char ==# 8
			let input = input[0:-2]
		else
			let input = input . nr2char(char)
		endif
		
		redraw | echom a:msg." ".input
		
		let char = getchar()
	endwhile
	
	return input
endfunction

function! s:ModifyTaskType(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task = s:ExtractLineData(line)
		
		if task['type'] ==# 'task'
			let task['type'] = 'note'
		elseif task['type'] ==# 'note'
			let task['type'] = 'task'
		endif
		
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:ModifyTaskTime(lines)
	let time = s:Input("Enter time: ")
	if trim(time) ==# ''
		let time = -1
	endif
		
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task = s:ExtractLineData(line)
		let task['date']['time'] = time
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:ModifyTaskDate(lines)
	let input = s:Input("Enter date: ")

	if input =~# '\v[+-]\d+(d|w|mo|y)'
		let today = strftime('%Y-%m-%d')
		let date  = {'date' : trim(system('dateadd '.today.' '.input))}
	else
		let date = s:ExtractDateData(input)
		if date['date'] == -1 && date['time'] == -1 && date['weekday'] == -1
			let date = {}
		endif
	endif
		
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task = s:ExtractLineData(line)
		if empty(date)
			let task['date'] = {}
		else
			let task['date']['date'] = date['date']
		endif
		
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:ModifyTaskPriority(lines)
	
	echom "Enter priority ([0-9]): "
	let char = nr2char(getchar())
	if char !~# '\v\d+'
		echoerr char." is not a number!"
		return
	endif
		
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task = s:ExtractLineData(line)
		let task['priority'] = char+0
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:ModifyTaskStatus(what, lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
		
		let task = s:ExtractLineData(line)

		if a:what ==# 'done'
		\|| a:what ==# 'todo'
		\|| a:what ==# 'failed'
		\|| a:what ==# 'cancelled'
			let task['status'] = a:what
		else
			echoerr "Wrong argument(what):".a:what
			return
		endif

		call s:ReplaceLineWithTask(task, lnum)
		
	endfor
endfunction

function! s:RemoveTaskDate(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task         = s:ExtractLineData(line)
		let task['date'] = {}
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:RemoveTaskTime(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task         = s:ExtractLineData(line)
		let task['date']['time'] = -1
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:RemoveTaskBlocking(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task             = s:ExtractLineData(line)
		let task['blocking'] = v:false
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:RemoveTaskId(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task       = s:ExtractLineData(line)
		let task['id'] = -1
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
endfunction

function! s:RemoveTaskWaiting(lines)
	for lnum in a:lines
		let line = getline(lnum)
		
		" check if line is task or note
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			echoerr "No line or task in line ".lnum
			return
		endif
	
		let task = s:ExtractLineData(line)
		
		if len(task['waiting']) == 0
			return
		endif
		
		let blocks           = s:PrependSelectionWithNumbers(task['waiting'])
		let blocks_selection = extend(blocks, ['[a]ll'], 0)
		
		echom 'Select ID(s): '.join(blocks_selection, ', ')
		let char = nr2char(getchar())

		if char ==# 'a'
			let task['waiting'] = []
		else
			call remove(task['waiting'], char-1)
		endif
		
		call s:ReplaceLineWithTask(task, lnum)
	
	endfor
	
endfunction

function! s:RemoveTaskPrompt(type)
	echom 'Remove from Task(s):    d[a]te    ti[m]e    [w]aiting    [b]locking    [i]d'
	let char = nr2char(getchar())
	
	if a:type ==# 'V'
		let start = line("'<")
		let end   = line("'>")
		let lines = range(start, end)
	elseif a:type ==# 'char'
		let lines = [ line(".") ]
	endif
	
	if char ==# 'a'
		call s:RemoveTaskDate(lines)
	elseif char ==# 'm'
		call s:RemoveTaskTime(lines)
	elseif char ==# 'w'
		call s:RemoveTaskWaiting(lines)
	elseif char ==# 'b'
		call s:RemoveTaskBlocking(lines)
	elseif char ==# 'i'
		call s:RemoveTaskId(lines)
	endif
endfunction

function! s:ChangeTaskPrompt(type)
	echom 'Change Task(s):    [d]one    [t]odo    [f]ailed    [c]ancelled    [p]riority    d[a]te    ti[m]e    act[i]on    t[y]pe'
	let char = nr2char(getchar())
	
	if a:type ==# 'V'
		let start = line("'<")
		let end   = line("'>")
		let lines = range(start, end)
	elseif a:type ==# 'char'
		let lines = [ line(".") ]
	endif
	
	if char ==# 'd'
		call s:ModifyTaskStatus('done', lines)
	elseif char ==# 't'
		call s:ModifyTaskStatus('todo', lines)
	elseif char ==# 'f'
		call s:ModifyTaskStatus('failed', lines)
	elseif char ==# 'c'
		call s:ModifyTaskStatus('cancelled', lines)
	elseif char ==# 'p'
		call s:ModifyTaskPriority(lines)
	elseif char ==# 'a'
		call s:ModifyTaskDate(lines)
	elseif char ==# 'm'
		call s:ModifyTaskTime(lines)
	elseif char ==# 'i'
		call s:ModifyTaskAction(lines)
	elseif char ==# 'y'
		call s:ModifyTaskType(lines)
	endif
endfunction

function! s:AddTaskPrompt(type)
	echom 'Add to Task(s):    act[i]on    [w]aiting    [b]locking'
	let char = nr2char(getchar())
	
	if a:type ==# 'V'
		let start = line("'<")
		let end   = line("'>")
		let lines = range(start, end)
	elseif a:type ==# 'char'
		let lines = [ line(".") ]
	endif
	
	if char ==# 'i'
		call s:AddTaskAction(lines)
	elseif char ==# 'w'
		call s:AddTaskWaiting(lines)
	elseif char ==# 'b'
		call s:AddTaskBlocking(lines)
	endif
endfunction

function! s:YankTaskPrompt()
	let selections = [
				\ 'id',
				\ ]
	let selections_dialog = [
				\ '&id',
				\ ]
	let input = confirm('Yank Task Properties: ', join(selections_dialog, "\n"))
	if selections[input-1] ==# 'id'
		let @+ = s:ExtractId(getline('.'))
		silent echom "ID yanked to \" register."
	endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"												String/Line Manipulation 												"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:CompileTaskString(task)
	let str = ''
	let t   = deepcopy(a:task)
	let lut = {
		\'done' : 'x',
		\'todo' : ' ',
		\'failed' : 'F',
		\'cancelled' : '-',
		\ }

	" indendation / level
	let i = 0
	while i < t['level']
		let str = str.'	'
		let i = i + 1
	endwhile

	" task or note
	if t['type'] ==# 'note'
		let str = str.'-'
	elseif t['type'] ==# 'task'
		if t['status'] == -1
			let t['status'] = 'todo'
		endif
		let str = str.'- ['.lut[t['status']].']'
	endif

	" priority
	if t['priority'] != 0
		let exclamations = ''
		let i = 0
		while i < t['priority']
			let exclamations = exclamations.'!'
			let i = i + 1
		endwhile
		let str = str.' '.exclamations
	endif

	" date
	if empty(t['date']) == v:false
		let date = t['date']
		let time = '{'
		
		" weekday
		let dayofweek = trim(system('date +%a --date='.date['date']))
		let time = time.dayofweek.": "

		" date
		if date['date'] != -1
			let time = time.date['date']
		endif
		" time
		if date['time'] != -1
			let time = time.' '.date['time']
		endif

		let time = time.'}'
		let str = str.' '.time
	" repetition
	elseif empty(t['repetition']) == v:false
		let rep = t['repetition']	
		let time = '{'

		" startdate
		if rep['startdate'] != -1
			let time = time.rep['startdate']
		endif

		" starttime
		if rep['starttime'] != -1
			let time = time.' '.rep['starttime']
		endif

		" operator & operand
		let time = time.'|'.rep['operator'].':'.rep['operand']

		" enddate
		if rep['enddate'] != -1
			let time = time.'|'.rep['enddate']
		endif

		" endtime
		if rep['endtime'] != -1
			let time = time.' '.rep['endtime']
		endif
		
		let time = time.'}'
		let str = str.' '.time
	endif

	" text
	let str = str.' '.t['text']
	
	" flag delimiter
	let str = str.' --'
	
	" id	
	let str = str.' 0x'.t['id']

	" waiting
	if len(t['waiting']) >  0
		let str = str.' '.join(map(t['waiting'], '"~".v:val'), ' ')
	endif

	" blocking
	if t['blocking'] != v:false
		let str = str.' $block'
	endif
	
	" tags
	if len(t['tags']) > 0
		let str = str.' '.join(map(t['tags'], '"#".v:val'), ' ')
	endif
	
	return str
endfunction

function! s:ExtendLineWithTask(t1, dates, lnum)
	" skip if datefile
	if s:IsDateFile() == v:true | return | endif
	
	let line = getline(a:lnum)
	" check if date is in datelist
	let t2       = s:ExtractLineData(line)
	let datetime = {}
	let idx      = 0
	while idx < len(a:dates)
		if a:dates[idx]['date'] ==# t2['date']['date']
			let datetime = a:dates[idx]
			call add(s:used_dates, a:dates[idx])
			call add(s:used_ids, t2['id'])
			break
		endif
		let idx = idx + 1
	endwhile
	" abort if date is not in datelist
	if empty(datetime) == v:true
		return
	endif
	" extend & set
	let tnew['text']         = t2['text']
	let tnew['date']['time'] = datetime['time']
	let str                  = s:CompileTaskString(tnew)
	call setline(a:lnum, str)
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                             References                                "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:UpdateReferences(lines)
	echom "Updating references."
	" save location
	call s:SaveLocation()
	for lnum in a:lines
		let line = getline(lnum)
		" check if line is task or note
		if s:IsLineTask(line) == v:false && s:IsLineNote(line) == v:false
			continue
		endif
		" get data
		let task = s:ExtractLineData(line)
		" check if line has an id
		if task['id'] == -1 | continue | endif
		" escape id
		let id = escape(task['id'], '|')
		" updating of references
		" both base and extended ids
		execute 'silent! bufdo global/\v<0x'.id.'(\s|$)/call s:ReplaceLineWithTask(task, line("."))'
	endfor
	" restore original location
	call s:RestoreLocation()
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																Dates				                            "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:DatesGetIndexOfValue(haystack, needle)
	let idx = 0
	while idx < len(a:haystack)
		if a:needle ==# a:haystack[idx]['date']
			return idx 
		endif
		let idx = idx + 1
	endwhile
	return v:false
endfunction

function! s:IsDateInList(haystack, needle)
	for i in a:haystack
		if a:needle ==# i['date']
			return v:true
		endif
	endfor
	return v:false
endfunction

function! s:SortDateFile()
	let save_cursor = getcurpos()
	let save_file = expand('%')
	let datefile = s:GetDatefileName()
	execute 'edit! '.datefile
	execute '%sort'
	execute 'write!'
	let buf = bufnr()
	execute 'edit '.save_file
	call setpos('.', save_cursor)
	execute buf.'bdelete!'
endfunction

function! s:UpdateFirstLineOfDateFile()
	echom "Updating first line datefile of file ".expand('%')
	" check if project has any tags
	if has_key(s:project_tree['flags'], 'tag') == v:false
		return
	endif
	" only continue if there is already a datefile
	if filereadable(s:GetDatefileName()) == v:false
		return
	endif
	call s:SaveLocation()
	execute 'edit! '.s:GetDatefileName()
	call setline('1', join(s:project_tree['flags']['tag'], " "))
	update!
	let buf = bufnr()
	call s:RestoreLocation()
endfunction

" TODO rewrite or remove
function! s:CleanupAllDatefiles()
	" save
	call s:SaveLocation()
	let buffers_save = s:SaveBuffers()
	" TODO this might also blow up?
	execute 'args ./**/*\.vdo'
	execute 'bufdo call s:CleanUpDatefile()'
	execute 'bufdo update!'
	" restore 
	call s:RestoreLocation()
	call s:RestoreBuffers(buffers_save)
endfunction
command! -nargs=0 VdoCleanDatefiles	:call s:CleanupAllDatefiles()

function! s:UpdateDates(lines)
	echom "Updating dates."
	" skip if datefile
	if s:IsDateFile() == v:true | return | endif
	" save location
	call s:SaveLocation()
	" get datefile for later
	let datefile = s:GetDatefileName() 

	for lnum in a:lines
		let line = getline(lnum)
		" check if line is task or note
		if s:IsLineTask(line) == v:false && s:IsLineNote(line) == v:false
			continue
		endif
		
		let s:used_dates = []
		let s:used_ids   = []
		" get data
		let task = s:ExtractLineData(line)
		" check if line has a repetition
		if empty(task['repetition']) == v:true
			continue
		endif
		" generate list of dates from repetition
		let dates = s:GenerateDatesFromRepetition(task)
		" update references of auto-generated tasks in arglist
		execute 'silent! bufdo global/\v<0x'.task['id'].'(\|\d+)>/call s:ExtendLineWithTask(task, dates, line("."))'
		" update the dates in the datefile
		call s:UpdateDatefile(datefile, task, dates)
	endfor

	" restore location
	call s:RestoreLocation()
endfunction

function! s:UpdateDatefile(datefile, task, dates)
	" delete all dates from datefile with same id as current repetition
	execute 'edit! '.a:datefile
	execute 'silent! global/\v0x'.a:task['id'].'/delete'
	
	" insert all not already existing dates into to datefile
	call sort(map(s:used_ids, "substitute(v:val, '.*\|', '', '')"))
	let sid = max(s:used_ids)+1

	for d in a:dates
		if s:IsDateInList(s:used_dates, d['date']) == v:true
			continue
		endif
		
		let new         = deepcopy(a:task)
		let new['id']   = a:task['id'].'|'.sid
		let new['date'] = { 'date': d['date'], 'weekday': -1, 'time': d['time']}
		let str         = s:CompileTaskString(new)
		call append(line('$'), str)
		
		let sid = sid + 1
	endfor
endfunction

function! s:DeleteFromDatefile(id)
	
	" skip if there is not a datefile
	if filereadable(s:GetDatefileName()) == v:false
		return
	endif

	" save location
	call s:SaveLocation()
	" edit datefile
	execute "edit! ".s:GetDatefileName()
	" deletion
	execute 'silent! global/\v<0x'.a:id.'\|\d+(\s|$)/delete'
	" restore location
	call s:RestoreLocation()
endfunction

" deletes all parent-less auto-generated dates with `id`
function! s:CheckDeletionFromDatefile(id)
	
	" skip if there is not a datefile
	if filereadable(s:GetDatefileName()) == v:false
		return
	endif

	" save location
	call s:SaveLocation()
	" edit datefile
	execute "edit! ".s:GetDatefileName()
	
	if s:GetNumOccurences('\v<0x'.a:id.'>(\s|$)') == 0
		" note: the following pattern is ok and won't delete tasks in regular files,
		" because we are not using `bufdo global`
		execute 'silent! global/\v<0x'.a:id.'\|\d+(\s|$)/delete'
	endif
	
	" restore location
	call s:RestoreLocation()
endfunction

" remove all auto-generated dates where there is no parent anymore
function! s:CleanUpDatefile()
	echom "Cleaning datefile of file ".expand('%')
	
	" skip if datefile
	if s:IsDateFile() == v:true | return | endif

	" skip if there is not datefile
	if filereadable(s:GetDatefileName()) == v:false
		return
	endif

	" save location
	call s:SaveLocation()
	" edit datefile
	execute "edit! ".s:GetDatefileName()
	
	" get list of ids
	let cur   = 2 " first line only has tags
	let total = line('$')
	let ids   = []
	while cur <= total
		let baseid = s:ExtractFromString(getline(cur), {'baseid':1})['baseid']
		call add(ids, baseid)
		let cur = cur + 1
	endwhile

	call uniq(sort(ids))

	for id in ids
		" only base ids
		if s:GetNumOccurences('\v<0x'.id.'>(\s|$)') == 0
			" note: the following pattern is ok and won't delete tasks in regular files,
			" because we are not using `bufdo global`
			execute 'silent! global/\v<0x'.id.'\|\d+(\s|$)/delete'
		endif
	endfor

	" not in use, because of speed
	" call s:SortDateFile()
	
	" restore location
	call s:RestoreLocation()
endfunction

function! s:GenerateDatesFromRepetition(task)
	let dates = []
	let rep   = a:task['repetition']

	if rep['starttime'] != -1
		call add(dates, {'date':rep['startdate'], 'time' : rep['starttime']})
		let start = trim(system('dateadd '.shellescape(rep['startdate']).' +'.rep['operand'].''.rep['operator']))
	else
		let start = rep['startdate']
	endif
		
	" Add repetitions into the future, but limit how many.
	" We don't want do flood the datefiles with too much data, otherwise
	" grepping will be slowed down.
	if rep['enddate'] == -1
		let today = strftime('%Y-%m-%d')

		if rep['operator'] ==# 'd'
			let limit = trim(system('dateadd '.shellescape(today).' +3mo'))
		elseif rep['operator'] ==# 'w'
			let limit = trim(system('dateadd '.shellescape(today).' +6mo'))
		elseif rep['operator'] ==# 'mo'
			let limit = trim(system('dateadd '.shellescape(today).' +2y'))
		elseif rep['operator'] ==# 'y'
			let limit = trim(system('dateadd '.shellescape(today).' +30y'))
		else
			let limit = trim(system('dateadd '.shellescape(today).' +3mo'))
		endif
	else
		let limit = rep['enddate']
	endif
	
	let cur = start
	while cur <=# limit
		if rep['endtime'] == -1 && rep['starttime'] != -1
			call add(dates, {'date': cur, 'time': rep['starttime']})
		else
			call add(dates, {'date': cur, 'time': -1})
		endif
		" date addition
		let cur = trim(system('dateadd '.shellescape(cur).' +'.rep['operand'].rep['operator']))	
	endwhile
		
	if rep['endtime'] != -1 && s:IsDateInList(dates, rep['enddate']) == v:true
		let idx = s:DatesGetIndexOfValue(dates, rep['enddate'])
		let dates[idx]['time'] = rep['endtime']
	endif
	
	return dates
endfunction


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                             Validation                                "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:GetDiff()
	
	redir => l:changedlines
	silent execute 'w !diff --unchanged-line-format="" --old-line-format=":\%dn" --new-line-format=";\%dn" % -'
	redir END
	
	let l:split = split(l:changedlines, '')
	if len(l:split) == 0
		let s:changedlines = []
		return { 'insertions':[], 'deletions':[], 'changes':[] }
	endif

	let dif = s:ExtractFromString(l:split[0], { 'insertions':1, 'deletions': 1 })
	let dif = extend(dif, { 'changes':[] })
	
	"find modified	
	for d in dif['deletions']
		if s:InList(dif['insertions'], d) == v:true
			call add(dif['changes'], d)
			call filter(dif['insertions'], 'v:val != '.d)
			call filter(dif['deletions'], 'v:val != '.d)
		endif
	endfor

	return dif
endfunction

function! s:GetLinesOfDiskfile(lines)
	echom "Reading lines from disk"
	let read = []
	for i in a:lines
		call add(read, {'lnum': i, 'line': trim(system('sed -n '.i.'p '.expand('%')))})
	endfor
	return read
endfunction

function! s:ValidateSyntax(lines)
	
	let s:local_syntax_errors = []
	
	" check if line is task/note
	for lnum in a:lines
		let line = getline(lnum)
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			call filter(a:lines, 'v:val !=# '.lnum)
		endif
	endfor

	" syntax check
	for lnum in a:lines
		let line = getline(lnum)
		
		" check syntax
		let res = s:CheckSyntaxSingle(line, lnum)
		if res !=# ''
			call add(s:local_syntax_errors, { 'msg' : res, 'lnum' : lnum  })
		endif
	endfor

	" throw possible syntax errors
	if len(s:local_syntax_errors) > 0
		throw "syntax-error"
	endif
	
endfunction

function! s:ValidateId(lines)
	for lnum in a:lines
		let line = getline(lnum)
		let item = s:ExtractLineData(line)
		if item['id'] == -1
			let item['id'] = s:NewID()
			call s:ReplaceLineWithTask(item, lnum)
		endi
	endfor
endfunction

function! s:ValidateRebuilt(lines)
	for lnum in a:lines
		let line = getline(lnum)
		let item = s:ExtractLineData(line)
		call s:ReplaceLineWithTask(item, lnum)
	endfor
endfunction

function! s:ValidateChanges(changes)
	echom "Validating changes."
	" syntax check
	call s:ValidateSyntax(a:changes)
	" id check
	call s:ValidateId(a:changes)
	" re-build line
	call s:ValidateRebuilt(a:changes)
	" update references
	call s:UpdateReferences(a:changes)
	" update dates
	call s:UpdateDates(a:changes)
endfunction

function! s:ValidateInsertions(insertions)
	echom "Validating insertions."
	" syntax check
	call s:ValidateSyntax(a:insertions)
	" id check
	call s:ValidateId(a:insertions)
	" re-build line
	call s:ValidateRebuilt(a:insertions)
	" update references
	call s:UpdateReferences(a:insertions)
	" update dates
	call s:UpdateDates(a:insertions)
endfunction
function! s:ValidateDeletions(deletions)
	echom "Validating deletions."
endfunction

function! s:TextChangedWrapper()
	try
		undojoin | call s:TextChanged()
	catch /^Vim\%((\a\+)\)\=:E790/
		" execute 'normal! g-'
		" execute 'normal! g-'
		undo 
		undo
		" call s:TextChanged()
	endtry
endfunction

function! s:TextChanged()
	" echom "Event: TextChanged in buffer ".bufname(bufnr())
	
	if b:undo_event == v:true
		let b:undo_event = v:false
		return
	endif

	if exists('b:text_changed_event') == v:true && b:text_changed_event == v:true
		echom "Abort due to b:text_changed_event"
		let b:text_changed_event = v:false
		return
	endif
	
	" check if datefile
	if s:IsDateFile() == v:true
		echom "Pushing from datefile.."
		" only save undo file
		silent write
		call s:SaveUndo(bufnr())
		call s:StackPush(s:undo_stack, [bufnr()])
		" skip
		return
	endif
	
	" get diff
	let changes = s:GetDiff()
	" check if there is anything to do
	if len(changes['insertions']) == 0
				\ && len(changes['deletions']) == 0
				\ && len(changes['changes']) == 0
		" nothing to do
		echom "return, nothing to do"
		return
	endif
	" reset matches set by previous syntax checks
	match none
	
	try 

		if len(changes['insertions']) > 0
			call s:ValidateInsertions(changes['insertions'])
		endif
		
		if len(changes['deletions']) > 0
			let deleted = s:GetLinesOfDiskfile(changes['deletions'])
			call s:ValidateDeletions(changes['deletions'])
		endif
		
		if len(changes['changes']) > 0
			let changed = s:GetLinesOfDiskfile(changes['changes'])
			call s:ValidateChanges(changes['changes'])
		endif
		
		" check if deleted lines have a repetition, update datefile accordingly
		if len(changes['deletions']) > 0 
			" get deleted lines
			for line in deleted
				" check if the deleted line has a repetition
				let rep = s:ExtractRepetition(line['line'])
				if empty(rep) == v:false
					" yes, check auto-generated dates for deletion
					call s:CheckDeletionFromDatefile(s:ExtractId(line['line']))
				endif
			endfor
		endif
		
		" check if changed lines had a repetition before the change,
		" update datefile accordingly
		if len(changes['changes']) > 0
			for line in changed
				" check if the changed line does still have a repetition
				let rep_1 = s:ExtractRepetition(getline(line['lnum']))
				if empty(rep_1) == v:false
					echom "skipping because current line still has a repetition."
					" yes
					continue
				endif
				" check if the old line has a repetition
				let rep_2 = s:ExtractRepetition(line['line'])
				if empty(rep_2) == v:false
					" yes, delete
					call s:DeleteFromDatefile(s:ExtractId(line['line']))
				endif
			endfor
		endif

		call s:UpdateFirstLineOfDateFile()
		" call s:ParseFile()
		" call s:DataComputeProgress()
		" call s:DrawSectionOverview()
		" call s:DrawProjectStatistics()

		" get list of changed buffers
		let buffers = deepcopy(getbufinfo({'buflisted':1, 'bufmodified':1}))
		" write all changed buffers
		silent wall
		" save undo-files of changed buffers
		call s:UpdateUndoFiles(buffers)
		echom "Writing file. Done."
		
	catch /syntax-error/
		" highlight syntax errors
		let lines = map(s:local_syntax_errors, 'v:val["lnum"]')
		let lines = map(lines, '"%".v:val."l"')
		let pat   = "(".join(lines, '|').").*$"
		execute 'match Error "\v'.pat.'"'
		highlight link VdoError Error
		" display error message
		echoerr "Syntax errors in line(s) ".join(lines, ', ')
	catch /.*/
		echoerr v:exception." in ".v:throwpoint
	endtry
	
	" update buffer list
	call s:UpdateBufferlist()
	
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                              Undo/Redo                                "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:undo_dir  = '.undo'
let s:undo_stack = []
let s:redo_stack = []

function! s:InitUndo()

	" check if this is a undo file
	if s:IsUndoFile() == v:true
		return
	endif
	
	if exists('b:undo_pointer') == v:true
		return
	else
		echom "Init undo in ".bufname(bufnr())
		let b:undo_pointer = -1
		call s:SaveUndo(bufnr())

		if s:StackLen(s:undo_stack) == 0
			call s:StackPush(s:undo_stack, [bufnr()])
		else
			call extend(s:StackBottom(s:undo_stack), [bufnr()])
		endif
		
		let b:undo_event = v:false
	endif
endfunction

function! s:FormatPointer(ptr)
	return trim(system('printf "%04d" '.a:ptr))
endfunction

function! s:GetFilename(pointer)
	return expand('%:p:h').'/.undo/'.s:FormatPointer(a:pointer).'-'.expand('%:t')
endfunction

function! s:CheckExistenceUndoDir()
	let dirname = expand('%:p:h')	.'/.undo/'
	if isdirectory(dirname) == v:false
		call system('mkdir '.dirname)
	endif
endfunction

function! s:UpdateUndoFiles(buffers)

	" push modified buffers onto `s:undo_stack`
	if b:undo_event == v:false
		let mod = []
		for b in a:buffers
			call add(mod, b['bufnr'])
			if b['bufnr'] != bufnr()
				call setbufvar(b['bufnr'], "text_changed_event", v:true)
			endif
		endfor
		call s:StackPush(s:undo_stack, mod)
	endif

	" save undo-files of modified buffers
	for b in a:buffers
		echom "Trying to save ".bufname(b['bufnr'])
		call s:SaveUndo(b['bufnr'])
	endfor
endfunction

function! s:SaveUndo(bufnr)

	echom "Saving undo of ".bufname(a:bufnr)

	if exists('b:undo_event') == v:false
		let b:undo_event = v:false
	endif

	if b:undo_event == v:true
		let b:undo_event = v:false
		return
	endif
		
	call s:SaveLocation()
	execute "buffer ".a:bufnr
	
	call s:CheckExistenceUndoDir()

	let file           = s:GetFilename(b:undo_pointer + 1)
	let b:undo_pointer = b:undo_pointer + 1
	" reset redo_list
	let s:redo_stack    = []
	echom "Saving undo-file of buffer ".bufname(a:bufnr)
	call system('cp '.expand('%').' '.file)

	call s:RestoreLocation()
endfunction

function! s:DeleteUndofiles()	
	echom "Deleting undo-files"
	execute 'args '.g:vimdoit_projectsdir.'/**/.undo/*.vdo'
	silent argdo !rm %
endfunction

command! -nargs=0 VdoUndo	:call s:Undo()
function! s:Undo()
	echom "Undoing"
	
	if b:undo_pointer == 0 || s:StackLen(s:undo_stack) == 0
		echom "Already at oldest change"
		return
	endif

	call s:SaveLocation()
	
	let buffers = s:StackPop(s:undo_stack)
	call s:StackPush(s:redo_stack, buffers)
	
	for bufnr in buffers
		execute "buffer ".bufnr

		let file = s:GetFilename(b:undo_pointer - 1)
		
		if filereadable(file) == v:false
			echoerr "Undo file ".file." not found!"
			return
		endif

		silent execute ':%!cat '.file
		let b:undo_pointer = b:undo_pointer - 1
		let b:undo_event   = v:true
	endfor

	silent wall
	call s:RestoreLocation()

endfunction

" command! -nargs=0 VdoRedo	:call s:Redo()
function! s:Redo()

	echom "Redoing"

	if s:StackLen(s:redo_stack) == 0
		echom "Already at newest change"
		return
	endif

	call s:SaveLocation()
	let buffers = s:StackPop(s:redo_stack)
	call s:StackPush(s:undo_stack, buffers)
	
	for bufnr in buffers
		execute "buffer ".bufnr

		let file = s:GetFilename(b:undo_pointer + 1)
		
		if filereadable(file) == v:false
			echoerr "Undo file ".file." not found!"
			return
		endif

		silent execute ':%!cat '.file
		let b:undo_pointer = b:undo_pointer + 1
		let b:undo_event   = v:true
	endfor
	
	silent wall
	call s:RestoreLocation()

endfunction

function! s:PrintStacks()
	echom "-------------"
	echom "Undo List:"
	echom s:undo_stack
	echom "Redot List:"
	echom s:redo_stack
	echom "Undo Pointer:"
	echom b:undo_pointer
endfunction
command! -nargs=0 VdoStack	:call s:PrintStacks()


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                               Mappings                                "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

if exists("g:vimdoit_did_load_mappings") == v:false
		" Grep projects in cwd
		nnoremap <leader>p	:<c-u>call <SID>GrepProjects(v:false)<cr>
		" Grep projects in root
		nnoremap <leader>P	:<c-u>call <SID>GrepProjects(v:true)<cr>
		" Grep tasks in project
		nnoremap <leader>tt	:<c-u>call <SID>GrepTasks("project")<cr>
		" Grep tasks in cwd
		nnoremap <leader>t.	:<c-u>call <SID>GrepTasks("area")<cr>
		" Grep tasks in root
		nnoremap <leader>t/	:<c-u>call <SID>GrepTasks("all")<cr>
		" Sort quickfix list
		nnoremap <leader>qs	:<c-u>call <SID>SortQuickfix()<cr>
		" Filter quickfix list
		nnoremap <leader>qf	:<c-u>call <SID>FilterQuickfix()<cr>
		" Modify Task Prompt (Normal)
		nnoremap M	:<c-u>call <SID>ChangeTaskPrompt('char')<cr>
		" Modify Task Prompt (Visual)
		vnoremap M	:<c-u>call <SID>ChangeTaskPrompt(visualmode())<cr>
		" Remove Task Prompt (Normal)
		nnoremap R	:<c-u>call <SID>RemoveTaskPrompt('char')<cr>
		" Remove Task Prompt (Visual)
		vnoremap R	:<c-u>call <SID>RemoveTaskPrompt(visualmode())<cr>
		" Add Task Prompt (Normal)
		nnoremap <leader>A	:<c-u>call <SID>AddTaskPrompt('char')<cr>
		" Add Task Prompt (Visual)
		vnoremap <leader>A	:<c-u>call <SID>AddTaskPrompt(visualmode())<cr>
		" Jump in Quickfix List to Today
		nnoremap <leader>qj	:<c-u>call <SID>JumpToToday()<cr>
		" Yank Task Prompt (Normal)
		nnoremap Y	:<c-u>call <SID>YankTaskPrompt()<cr>
		" Remap undo/redo to custom `Redo()` function
		nnoremap g+ :<c-u>call <SID>Redo()<cr>
		nnoremap U  :<c-u>call <SID>Redo()<cr>
		nnoremap g- :<c-u>call <SID>Undo()<cr>
		nnoremap u  :<c-u>call <SID>Undo()<cr>
		" nnoremap g+ <nop>
		" nnoremap U  <nop>
		" nnoremap g- <nop>
		" nnoremap u  <nop>
		let g:vimdoit_did_load_mappings = 1
endif


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                             Autocommands                              "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
augroup VimDoit
	autocmd!
	autocmd ShellCmdPost * call s:UpdateBufferlist()
	autocmd TextChanged *.vdo call s:TextChanged()
	autocmd VimLeave *.vdo call s:DeleteUndofiles()
	autocmd BufEnter *.vdo call s:InitUndo()

	if v:vim_did_enter
		call s:InitBufferlist()
	else
		autocmd VimEnter * call s:InitBufferlist()
	endif
augroup END

" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo
