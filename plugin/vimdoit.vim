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

" check if necessary tools are installed
let s:tools = ['diff', 'date', 'dateadd', 'dround', 'rg', 'sed', 'figlet' ]

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

let s:changedlines  = []
let s:syntax_errors = []
let s:parse_runtype = 'single'

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
	call s:RestoreLocation()
endfunction

" afer running `mv`, `rm`, `cp`, etc. we have to make sure 
" that the bufferlist is always up to date
function! s:UpdateBufferlist()
	" unload buffers where the corresponding file doesn't exist anymore
	let buffers = getbufinfo({'buflisted':1})	 
	
	for b in buffers
		" wipe not existing files
		if filereadable(bufname(b['bufnr'])) == v:false
			echom "wiping buffer :".bufname(b['bufnr'])
			execute "bwipeout!".b['bufnr']
		endif
	endfor
	
	" load files which are not existing
	call s:SaveLocation()
	execute 'args! '.g:vimdoit_projectsdir.'/**/*.vdo '.g:vimdoit_projectsdir.'/**/.*.vdo'
	call s:RestoreLocation()
endfunction

function! s:CheckDirAndCreate(path)
	if isdirectory(a:path) == v:false
		let cmd = "mkdir -p ".shellescape(a:path)
		echom cmd
		call system(cmd)
	endif
endfunction

function! s:CheckProjectAndCreate(project)
	if filereadable(a:project) == v:false
		let tpl = g:vimdoit_projectsdir.'/templates/project.vdo'
		let cmd = 'cp '.shellescape(tpl).' '.shellescape(a:project) 
		echom cmd
		call system(cmd)
	endif
endfunction

function! s:Symlink(target, source)
	let cmd1 = 'rm '.shellescape(a:source)
	echom cmd1
	call system(cmd1)
	let cmd2 = 'ln -s '.shellescape(a:target).' '.shellescape(a:source)
	echom cmd2
	call system(cmd2)
endfunction

function! s:NewProject()
	let filename = s:Input('Enter filename: ')
	if filename ==# ''
		echoerr "No filename supplied. Abort."
		return
	endif

	if filereadable(getcwd().'/'.filename.'.vdo') == v:true
		echoerr 'Project '.getcwd().'/'.filename.'.vdo already exists!'
		return
	endif

	call s:CreateProject(getcwd(), filename.'.vdo', 'New Project')
	execute 'edit! '.filename.'.vdo'
endfunction


command! -nargs=0 CreateProject	:call s:CreateProject('./', 'dummy.vdo', 'Dummy')
function! s:CreateProject(path, filename, title)
	call s:SaveLocation()
	
	" check if path exists, if not create it
	if isdirectory(a:path) == v:false
		echom "creating directory ".a:path
		call system('mkdir -p '.a:path)
	endif
	
	" don't overwrite existing ones
	let file = a:path.'/'.a:filename
	if filereadable(file) == v:true
		return
	endif

	echom "Creating empty project ".file
	
	execute "edit! ".file
	let lines = [
				\'<'.a:title.'>',
				\'',
				\'														 I am a template vision',
				\'',
				\'==============================================================================',
				\'<Tasks>',
				\'',
				\'- [ ] Dummy task of '.a:title,
				\]
	call append(0, lines)
	silent write!
	call s:RestoreLocation()
endfunction

function! s:AutoCreateDays(start, end)
	echom "Autocreating daily projects from ".a:start." to ".a:end
	let cur  = a:start
	while cur <=# a:end
		let year    = trim(system('date +%Y --date '.cur))
		let weekday = trim(system('date +%A --date '.cur))
		call s:CreateProject(g:vimdoit_projectsdir.'/todo/'.year, cur.'.vdo', weekday.' '.cur)
		let cur = trim(system('dateadd '.shellescape(cur).' +1d'))
	endwhile
endfunction

function! s:AutoCreateWeeks(start, end)
	echom "Autocreating weekly projects from ".a:start." to ".a:end
	let cur     = a:start
	while cur <=# a:end
		let year  = trim(system('date +%Y --date '.cur))
		let week  = trim(system('date +%V --date '.cur))
		echom "cur:".cur
		echom "year:".year
		echom "week:".week
		echom "===="
		call s:CreateProject(g:vimdoit_projectsdir.'/todo/'.year, 'kw-'.week.'.vdo', 'KW-'.week.' '.year)
		let cur = trim(system('dateadd '.shellescape(cur).' +1w'))
	endwhile
endfunction

function! s:AutoCreateMonths(start, end)
	echom "Autocreating monthly projects from ".a:start." to ".a:end
	let cur  = a:start
	while cur <=# a:end
		let year      = trim(system('date +%Y --date '.cur))
		let monthname = trim(system('date +%B --date '.cur))
		let monthnum  = trim(system('date +%m --date '.cur))
		call s:CreateProject(g:vimdoit_projectsdir.'/todo/'.year, monthnum.'-'.tolower(monthname).'.vdo', monthname.' '.year)
		let cur = trim(system('dateadd '.shellescape(cur).' +1mo'))
	endwhile
endfunction

function! s:SymlinkProjects()
	" heute
	let name   = 'heute'
	let date   = strftime('%Y-%m-%d')
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" gestern
	let name   = 'gestern'
	let date   = trim(system('dateadd today -1d'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" vorgestern
	let name   = 'vorgestern'
	let date   = trim(system('dateadd today -2d'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" morgen
	let name   = 'morgen'
	let date   = trim(system('dateadd today +1d'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" übermorgen
	let name   = 'uebermorgen'
	let date   = trim(system('dateadd today +2d'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" montag
	let name   = 'montag'
	let date   = trim(system('dateround today monday'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" dienstag
	let name   = 'dienstag'
	let date   = trim(system('dateround today dienstag'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" mittwoch
	let name   = 'mittwoch'
	let date   = trim(system('dateround today wednesday'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" donnerstag
	let name   = 'donnerstag'
	let date   = trim(system('dateround today thursday'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" freitag
	let name   = 'freitag'
	let date   = trim(system('dateround today friday'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" samstag
	let name   = 'samstag'
	let date   = trim(system('dateround today saturday'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" sonntag
	let name   = 'sonntag'
	let date   = trim(system('dateround today sunday'))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/'.tolower(date).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" diese woche
	let name   = 'diese-woche'
	let week   = strftime('%V')
	let year   = trim(system('date +%Y'))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/kw-'.tolower(week).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" letzte woche
	let name   = 'letzte-woche'
	let date   = trim(system('dateadd today -1w'))
	let week   = trim(system('date +%V --date '.shellescape(date)))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/kw-'.tolower(week).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" naechste woche
	let name   = 'naechste-woche'
	let date   = trim(system('dateadd today +1w'))
	let week   = trim(system('date +%V --date '.shellescape(date)))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/kw-'.tolower(week).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" dieser monat
	let name   = 'dieser-monat'
	let month   = strftime('%B')
	let year   = trim(system('date +%Y'))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/kw-'.tolower(month).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" naechster monat
	let name   = 'naechster-monat'
	let date   = trim(system('dateadd today +1mo'))
	let month   = trim(system('date +%B --date '.shellescape(date)))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/kw-'.tolower(month).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
	" letzter monat
	let name   = 'letzter-monat'
	let date   = trim(system('dateadd today -1mo'))
	let month   = trim(system('date +%B --date '.shellescape(date)))
	let year   = trim(system('date +%Y --date '.shellescape(date)))
	let source = g:vimdoit_projectsdir.'/todo/'.year.'/kw-'.tolower(month).'.vdo'
	let target = g:vimdoit_projectsdir.'/todo/'.name.'.vdo'
	call s:Symlink(source, target)
endfunction

function! s:AutocreateProjects()
	echom "Auto-creating projects"

	" did we do this already this year?
	let year = strftime("%Y")
	if isdirectory(g:vimdoit_projectsdir.'/todo/'.year) == v:true
		echom "Already done this year."
		return
	endif

	let today = strftime('%Y-%m-%d')
	" let start = trim(system('dateadd '.shellescape(today).' -3mo'))
	let start = strftime('%Y').'-01-01'
	" let end   = trim(system('dateadd '.shellescape(today).' +3mo'))
	let end = strftime('%Y').'-12-31'
	call s:AutoCreateDays(start, end)
	call s:AutoCreateWeeks(start, end)
	call s:AutoCreateMonths(start, end)
	call s:SymlinkProjects()
endfunction

function! s:PrepareLayout()
	execute 'edit ./todo/heute.vdo'
	setfiletype vimdoit
	call s:LoadMappings()
	vsplit
	execute 'edit ./todo/diese-woche.vdo'
	setfiletype vimdoit
	call s:LoadMappings()
	1 wincmd w
	normal! G
endfunction

function! s:Init()
	echom "Initializing..."
	call s:InitBufferlist()
	call s:AutocreateProjects()
	call s:PrepareLayout()
	echom "Initializing finished, vimdoit ready"
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

" TODO merge the two functions below
function! s:DataAddTask(task)
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
	echom "Generating new id..."
	" generate ID
	let l:id = s:GenerateID(8)
	" check if ID is already in use
	while s:GetNumOccurences('\v<0x'.l:id.'(\|\d+)?>') > 0
		let l:id = trim(system('echo '.l:id.' | sha256sum'))[0:7]
	endwhile 
	echom "...done"
	return l:id
endfunction
command! -nargs=? NewID	:call s:NewID()

function! s:GetExtendedIds(dates)
	let ids = []
	for d in a:dates
		let l:id = s:GenerateID(4)
		while s:InList(ids, l:id) == v:true
			let l:id = trim(system('echo '.l:id.' | sha256sum'))[0:3]
		endwhile 
		call add(ids, l:id)
	endfor
	return ids
endfunction

function! s:ReplaceLineWithTask(task, lnum)
	" change the level accordingly
	let a:task['level'] = s:ExtractFromString(getline(a:lnum), {'level':1})['level']
	call setline(a:lnum, s:TaskToStr(a:task))
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
let s:pat_id = '\x{8}(\|\x{4})?'
let s:pat_id_deprecated = '\x{8}(\|\d+)?'
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

	if empty(l:status) == v:true
		return -1
	endif
	
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
	" execute 'normal '.a:linenum.'gg0'
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
" TODO split into syntax-check and semantics-check
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
" - [x] check: repetitions can't have an extended-id

function! s:HasLineRepetition(line)
	return empty(s:ExtractRepetition(a:line)) ? v:false : v:true
endfunction

" Does use the global syntax list `s:syntax_errors`
function! s:CheckSyntax(line, linenum)
	
	" remove everything between ``
	let line = substitute(a:line, '\v`[^`]{-}`', '', 'g')

	" check if task/note has a valid indicator (`- …` or `- [ ]`)
	if line =~# '\v^\s*-\zs[^ -]\ze(\[.\])?'
		call s:SyntaxError(a:linenum, 'Invalid task/note indicator (`- …` or `- [ ]`). Maybe you used tabs instead of spaces?')
		return
	endif

	" check if a repetition does not have an extended id
	if s:HasLineRepetition(line)
		let baseid = s:ExtractBaseId(line)
		let id     = s:ExtractId(line)
		" baseid and id should now be the same
		if baseid !=# id
			call s:SyntaxError(a:linenum, "A repetition can't have an extended id!")
			return
		endif
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

function! s:SortPrompt()

	if len(getqflist()) == 0
		echom "Empty quickfix list. Nothing to do."
		return
	endif

	echom 'Sort quickfix list by:    [p]riority    [d]ate    p[r]oject    [i]d'
	
	try 
		let char = nr2char(getchar())
	catch /^Vim:Interrupt$/
		mode | return
	endtry

	mode

	if char ==# 'p'
		" sort by priority
		echom "Sorting by priority..."
		let qf = getqflist()
		call sort(qf, 's:CmpQfByPriority')
		echom "...done"
	elseif char ==# 'd'
		" sort by date
		echom "Sorting by date..."
		call s:FilterByHasDate()
		let qf = getqflist()
		call sort(qf, 's:CmpQfByDate')
		echom "...done"
	elseif char ==# 'r'
		" sort by project
		echom "Sorting by project..."
		let qf = getqflist()
		call sort(qf, 's:CmpQfByProject')
		echom "...done"
	elseif char ==# 'i'
		" sort by id
		echom "Sorting by id..."
		let qf = getqflist()
		call sort(qf, 's:CmpQfById')
		echom "...done"
	endif

	call setqflist(qf, 'r')
	" set syntax
	call s:SetQfSyntax()
endfunction

function! s:CmpQfByPriority(e1, e2)
	let [t1, t2] = [s:ExtractPriority(a:e1['text']), s:ExtractPriority(a:e2['text'])]
	return t1 ># t2 ? -1 : t1 ==# t2 ? 0 : 1
endfunction

function! s:CmpQfByProject(e1, e2)
	let [t1, t2] = [bufname(a:e1['bufnr']), bufname(a:e2['bufnr'])]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:CmpQfByDate(e1, e2)
	let [d1, d2] = [s:ExtractDate(a:e1['text']), s:ExtractDate(a:e2['text']) ]
	if d1['date'] ># d2['date']
		return 1
	elseif d1['date'] ==# d2['date']

		if d1['time'] ># d2['time']
			return 1
		elseif d1['time'] ==# d2['time']
			return 0
		else
			return -1
		endif

	else
		return -1	
	endif
endfunction

function! s:CmpQfById(e1, e2)
	let [t1, t2] = [s:ExtractId(a:e1.text), s:ExtractId(a:e2.text)]
	return t1 ># t2 ? 1 : t1 ==# t2 ? 0 : -1
endfunction

function! s:CmpQfByBacklog(e1, e2)	
	let filename1 = expand("#".a:e1['bufnr'].":t:r")
	let filename2 = expand("#".a:e2['bufnr'].":t:r")
	let filename_rel1 = substitute(expand("#".a:e1['bufnr'].":p"), '\v'.g:vimdoit_projectsdir.'/todo/', '', '')
	let filename_rel2 = substitute(expand("#".a:e2['bufnr'].":p"), '\v'.g:vimdoit_projectsdir.'/todo/', '', '')

	" is the filename in the form of a daily-project?
	if filename1 =~# '\v'.s:pat_date
		let date1 = filename1
	endif
	if filename2 =~# '\v'.s:pat_date
		let date2 = filename2
	endif

	" is the filename in the form a weekly-project?
	if filename1 =~# '\vkw\-\d{2}'
		let f1_week = substitute(filename1, '\vkw\-', '', '')
		let f1_year = substitute(filename_rel1, '\v^\d{4}\zs.*\ze', '', '')
		let date1   = trim(system('dateconv -f "%Y-%m-%d" -i "%Y-%V" '.shellescape(f1_year.'-'.f1_week)))
	endif
	if filename2 =~# '\vkw\-\d{2}'
		let f2_week = substitute(filename2, '\vkw\-', '', '')
		let f2_year = substitute(filename_rel2, '\v^\d{4}\zs.*\ze', '', '')
		let date2   = trim(system('dateconv -f "%Y-%m-%d" -i "%Y-%V" '.shellescape(f2_year.'-'.f2_week)))
 	endif

	" is the filename in the form of a monthly-project?
	if filename1 =~# '\v\d{2}\-(januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember)'
		let f1_month = substitute(filename1, '\v^\d{2}\zs.*\ze', '', '')
		let f1_year  = substitute(filename_rel1, '\v^\d{4}\zs.*\ze', '', '')
		let date1    = f1_year."-".f1_month."-00"
	endif
	if filename2 =~# '\v\d{2}\-(januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember)'
		let f2_month = substitute(filename2, '\v^\d{2}\zs.*\ze', '', '')
		let f2_year  = substitute(filename_rel2, '\v^\d{4}\zs.*\ze', '', '')
		let date2    = f2_year."-".f2_month."-00"
	endif
	
	return date1 ># date2 ? 1 : date1 ==# date2 ? 0 : -1
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                              Grepping                                 "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:grep = {
			\ 'mode'   : 'new',
			\ 'invert' : v:false,
			\ 'preprocessor' : '',
			\ }

function! s:GrepModeMsg()
	return '|    [m]ode: '.s:grep['mode'].'    [i]nvert: '.s:grep['invert']	
endfunction

function! s:ToggleGrepOptions(char)
	if a:char ==# 'm'
		" toggle mode
		if s:grep['mode'] ==# 'new'
			let s:grep['mode'] = 'add'
		elseif s:grep['mode'] ==# 'add'
			let s:grep['mode'] = 'new'
		endif
	elseif a:char ==# 'i'
		" toggle invert
		if s:grep['invert'] ==# v:false
			let s:grep['invert'] = v:true
		elseif s:grep['invert'] ==# v:true
			let s:grep['invert'] = v:false
		endif
	endif
endfunction

function! s:GrepPrompt(where)

	" check for modified buffers
	if len(getbufinfo({'buflisted':1, 'bufmodified':1})) > 0
		echom "You have modified buffers. Save all changes before proceeding."
		return
	endif
	
	if a:where ==# 'project'
		let where_msg = expand('%')
	elseif a:where ==# 'area'
		let where_msg = getcwd()
	elseif a:where ==# 'root'
		let where_msg = g:vimdoit_projectsdir
	elseif a:where ==# 'quickfix'
		let where_msg = 'quickfix'
	endif
	
	echom 'Grepping in '.shellescape(where_msg).':    [p]rojects    [t]asks    [n]otes    [d]ates    [r]epetitions    b[a]cklog    '.s:GrepModeMsg()

	try 
		let char = nr2char(getchar())
	catch /^Vim:Interrupt$/
		mode | return
	endtry

	if char ==# 'm' || char ==# 'i'
		call s:ToggleGrepOptions(char)
		mode | call s:GrepPrompt(a:where)	| return
	endif

	mode

	if char ==# 'p'
		" grep projects
		call s:GrepThings(a:where, 'projects')
	elseif char ==# 't'
		" grep tasks
		call s:GrepThings(a:where, 'tasks')
	elseif char ==# 'n'
		" grep notes
		call s:GrepThings(a:where, 'notes')
	elseif char ==# 'd'
		" grep dates
		call s:GrepThings(a:where, 'dates')
	elseif char ==# 'r'
		" grep repetitions
		call s:GrepThings(a:where, 'repetitions')
	elseif char ==# 'a'
		" grep backlog
		call s:GrepThings(a:where, 'backlog')
	endif

endfunction

function! s:Grep(pattern, files)
	
	" save options
	call vimdoit_utility#SaveOptions()
	" invert?
	let invert = s:grep['invert'] == v:true ? '--invert-match' : ''
	" mode: add or new?
	let cmd = s:grep['mode'] == 'new' ? 'grep!' : 'grepadd!'
	" modify grep-program
	let &grepprg='rg --vimgrep '.s:grep['preprocessor'].' --type-add "vimdoit:*.vdo" -t vimdoit '.invert
	" modify grep format
	set grepformat^=%f:%l:%c:%m
	" execute
	silent execute cmd.' '.shellescape(a:pattern).' '.a:files | copen
	" restore options
	call vimdoit_utility#RestoreOptions()
	" return
	return getqflist()
	
endfunction

function! s:GrepThings(where, what)

	" save cwd
	let cwd_save = getcwd()
	
	if a:where ==# 'project'
		let where_msg = expand('%')
	elseif a:where ==# 'area'
		let where_msg = getcwd()
	elseif a:where ==# 'root'
		let where_msg = g:vimdoit_projectsdir
	elseif a:where ==# 'quickfix'
		let where_msg = 'quickfix'
	endif

	" create a list of files where to grep 
	" and change working directories if necessary
	if a:where ==# 'project'
		let files        = shellescape(expand('%'))
		let s:grep['preprocessor'] = ''
	elseif a:where ==# 'area'
		let files        = ''
		let s:grep['preprocessor'] = '--pre '.g:vimdoit_plugindir.'/scripts/pre-project.sh'
	elseif a:where ==# 'root'
		let files        = ''
		let s:grep['preprocessor'] = '--pre '.g:vimdoit_plugindir.'/scripts/pre-project.sh'
		execute	'cd '.g:vimdoit_projectsdir
	elseif a:where ==# 'quickfix'
		let files        = join(map(s:GetFilesOfQfList(), 'shellescape(v:val)'), ' ')
		let s:grep['preprocessor'] = ''
	endif

	"""""""""""""""""
	" grep projects "
	"""""""""""""""""
	if a:what ==# 'projects'

		echom 'Grepping projects in '.shellescape(where_msg).':    [A]ll    [a]ctive    [f]ocus    [c]omplete    ca[n]celled    a[r]chived    [t]agged    '.s:GrepModeMsg()

		try 
			let char = nr2char(getchar())
		catch /^Vim:Interrupt$/
			mode
			" restore cwd
			execute 'cd '.cwd_save
			return
		endtry

		if char ==# 'm' || char ==# 'i'
			call s:ToggleGrepOptions(char)
			mode | call s:GrepProjects(a:where)	
			" restore cwd
			execute 'cd '.cwd_save
			return
		endif

		" in projects: always use the `pre-head.sh` preprocessor 
		let s:grep['preprocessor'] = '--pre '.g:vimdoit_plugindir.'/scripts/pre-head.sh'

		" which pattern?
		if char ==# 'A'
			let pattern = '^.*$'
		elseif char ==# 'a'
			let pattern = '^<.*>.*\#active'
		elseif char ==# 'f'
			let pattern = '^<.*>.*\#focus'
		elseif char ==# 'c'
			let pattern = '^<.*>.*\#complete'
		elseif char ==# 'n'
			let pattern = '^<.*>.*\#cancelled'
		elseif char ==# 'r'
			let pattern = '^<.*>.*\#archived'
		elseif char ==# 't'
			let pattern = '^<.*>.*\#[^\s]+'
		else
			" restore cwd
			execute 'cd '.cwd_save
			mode | return
		endif

	""""""""""""""
	" grep tasks "
	""""""""""""""
	elseif a:what ==# 'tasks'

		echom 'Grepping tasks in '.shellescape(where_msg).':    [A]ll    [t]odo    [d]one    [f]ailed    ca[n]celled '.s:GrepModeMsg()

		try 
			let char = nr2char(getchar())
		catch /^Vim:Interrupt$/
			" restore cwd
			execute 'cd '.cwd_save
			mode | return
		endtry

		if char ==# 'm' || char ==# 'i'
			call s:ToggleGrepOptions(char)
			mode | call s:GrepThings(a:where, a:what)	
			" restore cwd
			execute 'cd '.cwd_save
			return
		endif

		" which pattern?
		if char ==# 'A'
			let pattern = '\- \[.\]'
		elseif char ==# 't'
			let pattern = '\- \[ \]'
		elseif char ==# 'd'
			let pattern = '\- \[x\]'
		elseif char ==# 'f'
			let pattern = '\- \[F\]'
		elseif char ==# 'n'
			let pattern = '\- \[\-\]'
		else
			" restore cwd
			execute 'cd '.cwd_save
			mode | return
		endif
		
	""""""""""""""
	" grep notes "
	""""""""""""""
	elseif a:what ==# 'notes'
		
		" message
		echom 'Grepping notes in '.shellescape(where_msg).':'
		" pattern
		let pattern = '^\s*\- [^\[]'
		
	""""""""""""""
	" grep dates "
	""""""""""""""
	elseif a:what ==# 'dates'
		
		" message
		echom 'Grepping dates in '.shellescape(where_msg).'...'
		" save cfstack
		call vimdoit_utility#SaveCfStack()
		" grep regular dates
		let pat_dates_regular = '\{('.s:p_days.')?'.s:p_date.'('.s:p_hour.')?\}'
		let dates_regular = s:Grep(pat_dates_regular, files)
		" grep dates with extended-ids
		let pat_extended_ids = '\b'.s:p_id.s:p_id_ext.'\b'
		let extended_ids = s:Grep(pat_extended_ids, files)
		" grep repetitions
		let pat_repetitions = '\{'.s:p_date.'('.s:p_hour.')?\\|'.s:p_rep.'(\\|'.s:p_date.'('.s:p_hour.')?)?\}'
		let repetitions = s:Grep(pat_repetitions, files)
		" restore cfstack
		call vimdoit_utility#RestoreCfStack()
		" expand repetitions
		let gen = s:ExpandRepetitions(repetitions, extended_ids, '')
		" merge lists
		let all = []
		call extend(all, dates_regular)
		" filter false-positives
		call filter(all, function('s:FilByHasDate'))
		" extend by auto-generated dates
		call extend(all, gen)
		" sort by date
		call sort(all, 's:CmpQfByDate')
		" setting list
		call setqflist(all)
		echom "...done"
		" set syntax
		call s:SetQfSyntax()
		" restore cwd
		execute 'cd '.cwd_save
		return
		
	""""""""""""""""""""
	" grep repetitions "
	""""""""""""""""""""
	elseif a:what ==# 'repetitions'
		" message
		echom 'Grepping repetitions in '.shellescape(where_msg).'...'
		" pattern
		let pattern = '\{'.s:p_date.'('.s:p_hour.')?\\|'.s:p_rep.'(\\|'.s:p_date.'('.s:p_hour.')?)?\}'
		" grep
		let qf = s:Grep(pattern, files)
		" filter false-positives
		call filter(qf, function('s:FilByHasRepetition'))
		" set qf
		call setqflist(qf, 'r')
		" set syntax
		call s:SetQfSyntax()
		" restore cwd
		execute 'cd '.cwd_save
		return
	""""""""""""""""""""
	" grep backlog "
	""""""""""""""""""""
	elseif a:what ==# 'backlog'
		" message
		echom 'Grepping backlog in '.shellescape(where_msg).'...'
		" TODO remove completely
		" in backlog: never use any preprocessor
		" let s:grep['preprocessor'] = ''
		" pattern
		let pattern = '\- \[ \]'
		" grep
		call s:Grep(pattern, files)
		" filter by backlog
		call s:FilterByBacklog()
		" set syntax
		call s:SetQfSyntax()
		" restore cwd
		execute 'cd '.cwd_save
		echom "...done"
		return
	endif

	call s:Grep(pattern, files)
	" set syntax
	call s:SetQfSyntax()
	echom "...done"

	" restore cwd
	execute 'cd '.cwd_save
endfunction

function! s:GenerateTasks(dates, line)
	let t            = s:ExtractLineData(a:line)
	let list         = []
	let id_extension = s:GetExtendedIds(a:dates)
	let idx          = 0
	for d in a:dates
		let tmp                    = deepcopy(t)
		let tmp['date']['date']    = d['date']
		let tmp['date']['time']    = d['time']
		let tmp['date']['weekday'] = -1
		let tmp['id']              = tmp['id'].'|'.id_extension[idx]
		let idx                    = idx + 1
		call add(list, s:TaskToStr(tmp))
	endfor
	return list
endfunction

function! s:ExpandRepetitions(repetitions, extended_ids, limit)
	let list = []

	for rep in a:repetitions
		" no false positives, because our grep pattern is not 100% correct
		if s:HasLineRepetition(rep['text']) == v:false
			continue
		endif
		
		" generate the possible dates
		let dates = s:GenerateDatesFromRepetition(rep['text'], a:limit)
		
		" filter already existing dates
		let rep_id = s:ExtractId(rep['text'])
		
		for id in a:extended_ids
			let ext_id = s:ExtractBaseId(id['text'])
			if rep_id ==# ext_id
				let date = s:ExtractDate(id['text'])
				call filter(dates, "v:val['date'] !=# ".shellescape(date['date']))
			endif
		endfor

		" generate tasks from remaining dates
		let tasks = s:GenerateTasks(dates, rep['text'])
		
		" extend by qf attributes
		for t in tasks
			let tmp         = copy(rep)
			let tmp['text'] = t
			call add(list, tmp)
		endfor
	endfor

	return list
endfunction

command! -nargs=0 GrepDeprecatedIds	:call s:GrepTasksWithDeprecatedIds()
function! s:GrepTasksWithDeprecatedIds()
	let pat_extended_ids_deprecated = '\b'.s:p_id.s:p_id_ext_deprecated.'\b'
	let extended_ids = s:GetQfList(pat_extended_ids_deprecated, g:vimdoit_projectsdir)
	call setqflist(extended_ids)
endfunction

command! -nargs=0 ReplaceDeprecatedIds	:call s:ReplaceDeprecatedIds()
function! s:ReplaceDeprecatedIds()
	let list = getqflist()
	let ext_ids = s:GetExtendedIds(list)
	let idx = 0
	for i in list
		echom "processing task: ".i['text']
		let task = s:ExtractLineData(i['text'])
		let id_old = escape(task['id'], '|')
		let task['id'] = s:ExtractBaseId(i['text']).'|'.ext_ids[idx]
		execute 'cfdo global/\v<0x'.id_old.'(\s|$)/call s:ReplaceLineWithTask(task, line("."))'
		let idx = idx + 1
	endfor
endfunction

function! s:GetFilesOfQfList()
	let qf = getqflist()
	
	" empty quickfix-list
	if len(qf) == 0
		return []
	endif

	let list = []
	for i in qf
		call add(list, bufname(i['bufnr']))
	endfor
	
	return uniq(sort(list))
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"																		Views																"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:NicenQfByDate()

	call s:FilterByHasDate()
	let qf         = getqflist()
	call sort(qf, 's:CmpQfByDate')
	let idx        = 0
	let day_prev   = ''
	let week_prev  = ''
	let month_prev = ''
	let year_prev  = ''
	
	while idx < len(qf)

		let date = s:ExtractDate(qf[idx].text)
		if empty(date) == v:true
			echom qf[idx].text
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
			call insert(qf, {'text' : i}, idx)
			let inc = inc + 1
		endfor

		let idx        = idx + inc
		let day_prev   = day
		let week_prev  = week
		let month_prev = month
		let year_prev  = year
	endwhile

	call setqflist(qf)
	" set syntax
	call s:SetQfSyntax()
	mode | echom "Showing calendar view"
endfunction

let s:p_date   = '\d{4}-\d{2}-\d{2}'
let s:p_days   = '(Mo\|Di\|Mi\|Do\|Fr\|Sa\|So): '
let s:p_hour   = ' \d{2}:\d{2}'
let s:p_rep    = '(y\|mo\|w\|d):\d+'
let s:p_id     = '0x[[:xdigit:]]{8}'
let s:p_id_ext_deprecated = '\\|\d+'
let s:p_id_ext = '\\|[[:xdigit:]]{4}'

function! s:GetQfList(pattern, path)
	call vimdoit_utility#SaveOptions()
	call s:SetGrep()
	call vimdoit_utility#SaveCfStack()

	if a:path ==# '%'
		let file = shellescape(expand('%'))
	else
		let file = ''
		execute "cd ".a:path
	endif	

	execute 'silent grep! --pre '.g:vimdoit_plugindir.'/scripts/pre-project.sh --type-add '"vimdoit:*.vdo"' -t vimdoit '.shellescape(a:pattern).' '.file | copen

	let list = getqflist()
	
	call vimdoit_utility#RestoreCfStack()
	call vimdoit_utility#RestoreOptions()
	call s:RestoreGrep()

	return list
endfunction

function! s:JumpToToday()
	" jump to today
	let today = strftime('%Y-%m-%d')
	while search('\v'.today) == 0 
		let today = trim(system('dateadd '.shellescape(today).' +1d'))
	endwhile
	execute "normal! 0"
endfunction

function! s:SetQfSyntax()
	
	if exists('w:quickfix_title') == v:false
		return
	endif
	
	" :set conceallevel=2 concealcursor=nc
	" syntax match qfFileName "\v^.{-}\|\d+\scol\s\d+\|" conceal
	" syntax match Bars "\v^\|\|" conceal

	syntax match CalendarDateAndTime "\v\w*, \d{4}-\d{2}-\d{2}:"
	highlight link CalendarDateAndTime Operator

	syntax match CalendarText "\v(\s{3,}\w+\s\d+\s{3,})" contained
	highlight link CalendarText Operator
	syntax match CalendarWeek "\v(-{38}|\={38})"
	syntax match CalendarWeek "\v\s(-|\=)(\s{3,}\w+\s\d+\s{3,})(-|\=)$" contains=CalendarText
	highlight link CalendarWeek Identifier
	
	" Section Headings
	syntax match SectionHeadlineDelimiter "\v\<" contained conceal
	syntax match SectionHeadlineDelimiter "\v\>" contained conceal
	syntax match SectionHeadline "\v^\t*\zs\<[^\>]*\>\ze" contains=SectionHeadlineDelimiter
	highlight link SectionHeadline Operator
	highlight link SectionHeadlineDelimiter Comment
	syntax region FlagRegionHeadline start="\v^\t*\<[^\>]*\>" end="$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagSprint,FlagTag,FlagID,SectionHeadline

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
	syntax match Appointment "\v\{.{-}\}"
	highlight link Appointment Constant

	" Inner Headline
	syntax match InnerHeadline "\v^\s*#+.*$"
	highlight link InnerHeadline Orange

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

	" Flag Block ('#block')
	syntax match FlagBlock "\v\$<block>" contained
	highlight link FlagBlock Orange

	" Flag Waiting For Block ('~a42a')
	syntax match FlagWaiting "\v\~\x{8}" contained
	highlight link FlagWaiting String

	" Flag ID ('0x8c3d19d5')
	syntax match FlagID "\v0x\x{8}(\|\x{4})?(\s+)?" contained conceal
	highlight link FlagID NerdTreeDir

	" Flag ordinary tag ('#SOMESTRING')
	syntax match FlagTag "\v#[^ \t]*" contained
	highlight link FlagTag Identifier

	" Flag Region
	syntax region FlagRegion start="\v\s--\s" end="$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagSprint,FlagTag,FlagID
	highlight link FlagRegion NerdTreeDir

	" Task Block
	syntax match TaskBlock "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*\$block" contains=ExclamationMark,Info,Appointment,Code,Percentages
	highlight link TaskBlock Orange

	" Task Waiting
	syntax match TaskWaiting "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*\~\x{8}" contains=ExclamationMark,Info,Appointment,Code,Percentages
	highlight link TaskWaiting String

	" Task Done, also all of it's subtasks.
	syntax region TaskDone start="\v^\t{0}- \[x\]+" skip="\v^\t{1,}" end="^" contains=FlagID

	syntax match TaskFailedMarker "\v\[F\]" contained
	highlight link TaskFailedMarker Error
	syntax region TaskFailed start="\v^\t{0}- \[F\]+" skip="\v^\t{1,}" end="^" contains=TaskFailedMarker,FlagID

	syntax match TaskCancelledMarker "\v\[-\]" contained
	highlight link TaskCancelledMarker NerdTreeDir
	syntax region TaskCancelled start="\v^\t{0}- \[-\]+" skip="\v^\t{1,}" end="^" contains=TaskCancelledMarker,FlagID

	" highlight invalid task/note indicator
	syntax match InvalidTaskNoteIndicator "\v^-\zs[^ -]\ze(\[.\])?"
	highlight link InvalidTaskNoteIndicator Error

	highlight link TaskDone NerdTreeDir
	highlight link TaskFailed NerdTreeDir
	highlight link TaskCancelled NerdTreeDir

endfunction
command! -nargs=0 VdoSetQfSyntax	:call s:SetQfSyntax()

function! s:GTDView(where)
	
	" save cwd
	let cwd_save = getcwd()
	" save cfstack
	call vimdoit_utility#SaveCfStack()
	" save filter option
	let filter_save        = s:filter['invert']
	let s:filter['invert'] = v:false
	
	if a:where ==# 'project'
		let where_msg = expand('%')
	elseif a:where ==# 'area'
		let where_msg = getcwd()
	elseif a:where ==# 'root'
		let where_msg = g:vimdoit_projectsdir
	elseif a:where ==# 'quickfix'
		let where_msg = 'quickfix'
	endif

	echom "Building GTD-View of ".shellescape(where_msg)."..."
	
	" create a list of files where to grep 
	" and change working directories if necessary
	if a:where ==# 'project'
		let files        = shellescape(expand('%'))
		let s:grep['preprocessor'] = ''
	elseif a:where ==# 'area'
		let files        = ''
		let s:grep['preprocessor'] = '--pre '.g:vimdoit_plugindir.'/scripts/pre-project.sh'
	elseif a:where ==# 'root'
		let files        = ''
		let s:grep['preprocessor'] = '--pre '.g:vimdoit_plugindir.'/scripts/pre-project.sh'
		execute	'cd '.g:vimdoit_projectsdir
	elseif a:where ==# 'quickfix'
		let files        = join(map(s:GetFilesOfQfList(), 'shellescape(v:val)'), ' ')
		let s:grep['preprocessor'] = ''
	endif

	let list = []
	
	function! QfAdd(list, text)
		call add(a:list, {'text':a:text})
	endfunction
	
	let headline = trim(system('figlet '.shellescape(where_msg)))
	let headline = split(headline, '\n')
	for i in headline
		call QfAdd(list, i)
	endfor


	" grep current actions
	call QfAdd(list, '')
	call QfAdd(list, '=====================================')
	call QfAdd(list, '=			    	Current Actions	 		   =')
	call QfAdd(list, '=====================================')
	call QfAdd(list, '')
	
	echom "Building list of current actions..."
	let pattern = '\- \[ \]'
	let qf      = s:Grep(pattern, files)
	let current = s:FilterByTag('cur', copy(qf))
	call sort(current, 's:CmpQfByPriority')
	call extend(list, current)
	echom "...done"

	" grep next actions
	call QfAdd(list, '')
	call QfAdd(list, '=====================================')
	call QfAdd(list, '=			    	  Next Actions  		   =')
	call QfAdd(list, '=====================================')
	call QfAdd(list, '')
	
	echom "Building list of next actions..."
	let next = s:FilterByTag('next-?(\d+)?', copy(qf))
	call sort(next, 's:CmpQfByPriority')
	call extend(list, next)
	echom "...done"
	
	" grep most important actions
	call QfAdd(list, '')
	call QfAdd(list, '======================================')
	call QfAdd(list, '=	 	    Most important Actions  	  =')
	call QfAdd(list, '======================================')
	call QfAdd(list, '')
	
	echom "Building list most important actions..."
	let most = copy(qf)
	call sort(most, 's:CmpQfByPriority')
	call extend(list, most[0:9])
	echom "...done"
	
	" grep backlog actions
	call QfAdd(list, '')
	call QfAdd(list, '======================================')
	call QfAdd(list, '=								Backlog				  	  =')
	call QfAdd(list, '======================================')
	call QfAdd(list, '')
	
	echom "Building list of backlog..."
	let backlog = s:FilterByBacklog(copy(qf))
	call sort(backlog, 's:CmpQfByPriority')
	call extend(list, backlog)
	echom "...done"
	
	" grep upcoming dates
	call QfAdd(list, '')
	call QfAdd(list, '======================================')
	call QfAdd(list, '=						Upcoming Dates		  	  =')
	call QfAdd(list, '======================================')
	call QfAdd(list, '')
	
	echom "Building list of upcoming dates..."
	" grep regular dates
	let pat_dates_regular   = '\{('.s:p_days.')?'.s:p_date.'('.s:p_hour.')?\}'
	let dates_regular       = s:Grep(pat_dates_regular, files)
	let dates_regular_notes = s:FilterByNote(copy(dates_regular))
	let dates_regular_tasks = s:FilterByStatus('todo', copy(dates_regular))
	" grep dates with extended-ids
	let pat_extended_ids = '\b'.s:p_id.s:p_id_ext.'\b'
	let extended_ids     = s:Grep(pat_extended_ids, files)
	" grep repetitions
	let pat_repetitions   = '\{'.s:p_date.'('.s:p_hour.')?\\|'.s:p_rep.'(\\|'.s:p_date.'('.s:p_hour.')?)?\}'
	let repetitions       = s:Grep(pat_repetitions, files)
	let repetitions_notes = s:FilterByNote(copy(repetitions))
	let repetitions_tasks = s:FilterByStatus('todo', copy(repetitions))
	let repetitions       = extend(repetitions_notes, repetitions_tasks)
	" expand repetitions
	let gen = s:ExpandRepetitions(repetitions, extended_ids, '+2w')
	" merge lists
	let updates = []
	call extend(updates, dates_regular_notes)
	call extend(updates, dates_regular_tasks)
	" filter false-positives
	call filter(updates, function('s:FilByHasDate'))
	" extend by auto-generated dates
	call extend(updates, gen)
	" sort by date
	call sort(updates, 's:CmpQfByDate')
	let updates = s:FilterByDate('NextTwoWeeks', updates)
	call extend(list, updates)
	echom "...done"
	
	" restore cfstack
	call vimdoit_utility#RestoreCfStack()
	" set final list
	call setqflist(list)
	call s:SetQfSyntax()
	" restore cwd
	execute 'cd '.cwd_save
	" restore filter option
	let s:filter['invert'] = filter_save
	echom "...done"
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                               Filtering                               "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:filter = {
			\ 'invert' : v:false,
			\ 'status' : -1,
			\ 'tag'		 : -1,
			\ }

function! s:FilterModeMsg()
	return '|    [i]nvert: '.s:filter['invert']	
endfunction

function! s:ToggleFilterOptions(char)
	if a:char ==# 'i'
		" toggle invert
		if s:filter['invert'] ==# v:false
			let s:filter['invert'] = v:true
		elseif s:filter['invert'] ==# v:true
			let s:filter['invert'] = v:false
		endif
	endif
endfunction

function! s:FilterByStatus(status, ...)
	
	" checking parameters
	if a:0 == 0
		let qf = getqflist()
	elseif a:0 == 1
		let qf = a:1
	else
		echoerr "Invalid number of arguments in s:FilterByStatus()!"
	endif	

	let s:filter['status'] = a:status
	function! ByStatus(idx, val)
		let status = s:ExtractStatus(a:val['text'])
		if status ==# s:filter['status']
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	call filter(qf, function('ByStatus'))
	
	if a:0 == 0
		call setqflist(qf)
	else
		return qf
	endif
endfunction

function! s:FilterByWaiting()
	function! Waiting(idx, val)
		let waiting = s:ExtractWaiting(a:val['text'])
		if len(waiting) > 0
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	let qf = getqflist()
	call filter(qf, function('Waiting'))
	call setqflist(l:qf)
endfunction

function! s:FilterByBlocking()
	function! Blocking(idx, val)
		let blocking = s:ExtractBlocking(a:val['text'])
		if blocking == v:true
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	let qf = getqflist()
	call filter(qf, function('Blocking'))
	call setqflist(l:qf)
endfunction

function! s:FilterByBacklog(...)
	
	" checking parameters
	if a:0 == 0
		let qf = getqflist()
	elseif a:0 == 1
		let qf = a:1
	else
		echoerr "Invalid number of arguments in s:FilterByBacklog()!"
	endif	
	
	function! ByStatus(idx, val)
		let status = s:ExtractStatus(a:val['text'])
		if status !=# 'todo'
			return v:false
		else
			return v:true
		endif
	endfunction
	
	" filter all tasks which are not in projects in ./todo
	let fil_1 = []
	for i in qf
		let full = expand("#".i['bufnr'].":p")
		let full_relative = substitute(full, '\v^'.g:vimdoit_projectsdir.'/', '', '')
		if full_relative =~# '\v^todo'
			call add(fil_1, i)
		endif
	endfor

	" filter tasks with status `done`, `failed`, `cancelled`
	" this will also filter notes, ...
	call filter(fil_1, function('ByStatus'))

	let fil_2     = []
	let today     = strftime("%Y-%m-%d")
	let thisweek  = strftime('%V')
	let thismonth = strftime('%m')
	let thisyear  = strftime('%Y')
	
	for j in fil_1
		let filename     = expand("#".j['bufnr'].":t:r")
		let filename_rel = substitute(expand("#".j['bufnr'].":p"), '\v'.g:vimdoit_projectsdir.'/todo/', '', '')
		let yearnum  = substitute(filename_rel, '\v^\d{4}\zs.*\ze', '', '')
		
		" check if the task is in a weekly-project and filter the current week
		if filename =~# '\vkw\-\d{2}'
			let weeknum = substitute(filename, '\vkw\-', '', '')
			if weeknum <# thisweek && yearnum <=# thisyear
				call add(fil_2, j)
			endif
		endif
		
		" check if the task is in a monthly-project and filter the current month
		if filename =~# '\v\d{2}\-(januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember)'
			let monthnum = substitute(filename, '\v^\d{2}\zs.*\ze', '', '')
			if monthnum <# thismonth && yearnum <=# thisyear
				call add(fil_2, j)
			endif
		endif
		
		" check if the task is in a daily-project and filter the current day
		if filename =~# '\v'.s:pat_date && filename <# today
			call add(fil_2, j)
		endif
	endfor

	" sort by backlog date
	call sort(fil_2, 's:CmpQfByBacklog')
	
	if a:0 == 0
		call setqflist(fil_2)
	else
		return fil_2
	endif
endfunction

function! s:FilterByTag(tag, ...)
	
	" checking parameters
	if a:0 == 0
		let list = getqflist()
	elseif a:0 == 1
		let list = a:1
	else
		echoerr "Invalid number of arguments in s:FilterByTag()!"
	endif	
			
	let s:filter['tag'] = a:tag
	
	function! Tag(idx, val)

		let tags = s:ExtractTags(a:val['text'])
		
		if len(tags) == 0
			return s:filter['invert'] == v:true ? v:true : v:false
		endif

		let pat = '\v'.s:filter['tag']

		if s:filter['invert'] == v:false
			for t in tags
				execute "if '".t."' =~# '".pat."' | return v:true | endif"
			endfor
			return v:false
		else
			for t in tags
				execute "if '".t."' =~# '".pat."' | return v:false | endif"
			endfor
			return v:true
		endif
	endfunction
	
	call filter(list, function('Tag'))
	
	if a:0 == 0
		call setqflist(list)
	else
		return list
	endif
		
endfunction

function! s:FilterByUnique()
	
	function! HasSameID(e1, e2)
		let [t1, t2] = [s:ExtractId(a:e1.text), s:ExtractId(a:e2.text)]
		if t1 ==# t2 
			return s:filter['invert'] == v:true ? v:true : v:false
		else
			return s:filter['invert'] == v:true ? v:false : v:true
		endif
	endfunction
	
	let qf = getqflist()
	call sort(qf, function('s:CmpQfById'))
	call uniq(qf, function('HasSameID'))
	call setqflist(l:qf)
endfunction

function! s:FilterByTask()
	function! ByTask(idx, val)
		let res = s:IsLineTask(a:val['text'])
		if res == v:true
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	let qf = getqflist()
	call filter(qf, function('ByTask'))
	call setqflist(l:qf)
endfunction

function! s:FilterByNote(...)
	" checking parameters
	if a:0 == 0
		let qf = getqflist()
	elseif a:0 == 1
		let qf = a:1
	else
		echoerr "Invalid number of arguments in s:FilterByNote()!"
	endif	
	
	function! ByNote(idx, val)
		let res = s:IsLineNote(a:val['text'])
		if res == v:true
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	call filter(qf, function('ByNote'))
	
	if a:0 == 0
		call setqflist(qf)
	else
		return qf
	endif
endfunction

function! s:FilByHasDate(idx, val)
	let date = s:ExtractDate(a:val['text'])
	return empty(date) == v:true ? v:false : v:true
endfunction

function! s:FilByHasRepetition(idx, val)
	let rep = s:ExtractRepetition(a:val['text'])
	return empty(rep) == v:true ? v:false : v:true
endfunction

function! s:FilterByHasDate()
	function! ByDate(idx, val)
		let date = s:ExtractDate(a:val['text'])
		if empty(date) == v:false
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	let qf = getqflist()
	call filter(qf, function('ByDate'))
	call setqflist(l:qf)
endfunction

function! s:FilterByRepetition()
	function! ByRepetition(idx, val)
		let rep = s:ExtractRepetition(a:val['text'])
		if empty(rep) == v:false
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	let qf = getqflist()
	call filter(qf, function('ByRepetition'))
	call setqflist(l:qf)
endfunction

function! s:FilterByDate(date, ...)
	
	" checking parameters
	if a:0 == 0
		let qf = getqflist()
	elseif a:0 == 1
		let qf = a:1
	else
		echoerr "Invalid number of arguments in s:FilterByDate()!"
	endif	
	
	function! Today(idx, val)
		let date  = s:ExtractDate(a:val.text)
		if empty(date) == v:true
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
		
		let today = strftime("%Y-%m-%d")
		if date['date'] ==# today
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction

	function! Tomorrow(idx, val)
		let date     = s:ExtractDate(a:val.text)
		if empty(date) == v:true
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
		let today    = strftime("%Y-%m-%d")
		let tomorrow = trim(system('dateadd '.shellescape(today).' +1d'))
		if date['date'] ==# tomorrow
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction

	function! ThisWeek(idx, val)
		let date   = s:ExtractDate(a:val.text)
		if empty(date) == v:true
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
		let today  = strftime("%Y-%m-%d")
		let monday = trim(system('dround '.shellescape(today).' -- -Mon'))
		let sunday = trim(system('dround '.shellescape(today).' -- Sun'))
		if date['date'] >=# monday && date['date'] <=# sunday
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction

	function! NextWeek(idx, val)
		let date           = s:ExtractDate(a:val.text)
		if empty(date) == v:true
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
		let today          = strftime("%Y-%m-%d")
		let todayinoneweek = trim(system('dateadd '.shellescape(today).' +7d'))
		let nextmonday     = trim(system('dround '.shellescape(todayinoneweek).' -- -Mon'))
		let nextsunday     = trim(system('dround '.shellescape(todayinoneweek).' -- Sun'))
		if date['date'] >=# nextmonday && date['date'] <=# nextsunday
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	function! ThisMonth(idx, val)
		let date             = s:ExtractDate(a:val.text)
		if empty(date) == v:true
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
		let today            = strftime("%Y-%m-%d")
		let firstofmonth     = trim(system('dround '.shellescape(today).' /-1mo'))
		let firstofnextmonth = trim(system('dround '.shellescape(today).' /1mo'))
		if date['date'] >=# firstofmonth && date['date'] <# firstofnextmonth
			return s:filter['invert'] == v:true ? v:false : v:true
		else
			return s:filter['invert'] == v:true ? v:true : v:false
		endif
	endfunction
	
	function! Upcoming(idx, val)
		let date = s:ExtractDate(a:val['text'])
		if empty(date) == v:true
			return v:false
		endif
		let now = strftime('%Y-%m-%d')
		if date['date'] <# now
			return s:filter['invert'] == v:true ? v:true : v:false
		else
			return s:filter['invert'] == v:true ? v:false : v:true
		endif
	endfunction
	
	function! Past(idx, val)
		let date = s:ExtractDate(a:val['text'])
		if empty(date) == v:true
			return v:false
		endif
		let upcoming = Upcoming(a:idx, a:val)
		if upcoming == v:true
			return v:false
		else
			return v:true
		endif
	endfunction

	function! NextTwoWeeks(idx, val)
		let date = s:ExtractDate(a:val['text'])
		if empty(date) == v:true
			return v:false
		endif
		let now_in_two_weeks = trim(system('dateadd today +2w'))
		let now              = strftime('%Y-%m-%d')
		if date['date'] >=# now && date['date'] <=# now_in_two_weeks
			return v:true
		else
			return v:false
		endif
	endfunction
	
	call filter(qf, function(a:date))
	" sort by date
	call sort(qf, 's:CmpQfByDate')
	
	if a:0 == 0
		call setqflist(qf)
	else
		return qf
	endif
endfunction


function! s:FilterPrompt()

	if len(getqflist()) == 0
		echom "Empty quickfix list. Nothing to do."
		return
	endif
		
	echom 'Filter quickfix by:    [t]odo    [d]one    [c]ancelled    [f]ailed    [w]aiting    [b]locking    b[a]cklog    [u]nique    [n]ext    cu[r]rent    ta[s]k    n[o]te    dat[e]    [R]epetition    toda[y]    t[h]is week    ne[x]t week    this [m]onth    [p]ast    upcomin[g]    '.s:FilterModeMsg()

	try 
		let char = nr2char(getchar())
	catch /^Vim:Interrupt$/
		mode | return
	endtry

	if char ==# 'i'
		call s:ToggleFilterOptions(char)
		mode | call s:FilterPrompt()	| return
	endif

	mode

	if char ==# 't'
		echom 'Filtering by "todo"...'
		call s:FilterByStatus('todo')
		echom '...done'
	elseif char ==# 'd'
		echom 'Filtering by "done"...'
		call s:FilterByStatus('done')
		echom '...done'
	elseif char ==# 'c'
		echom 'Filtering by "cancelled"...'
		call s:FilterByStatus('cancelled')
		echom '...done'
	elseif char ==# 'f'
		echom 'Filtering by "failed"...'
		call s:FilterByStatus('failed')
		echom '...done'
	elseif char ==# 'w'
		echom 'Filtering by "waiting"...'
		call s:FilterByWaiting()
		echom '...done'
	elseif char ==# 'b'
		echom 'Filtering by "blocking"...'
		call s:FilterByBlocking()
		echom '...done'
	elseif char ==# 'a'
		echom 'Filtering by "backlog"...'
		call s:FilterByBacklog()
		echom '...done'
	elseif char ==# 'u'
		echom 'Removing duplicates...'
		if s:filter['invert'] == v:true
			echoerr "Removing duplicates with option 'invert' not implemented! Abort."
			return
		endif
		call s:FilterByUnique()
		echom '...done'
	elseif char ==# 'n'
		echom "Filtering by next..."
		call s:FilterByTag('next-?(\d+)?')
		echom '...done'
	elseif char ==# 'r'
		echom "Filtering by current..."
		call s:FilterByTag('cur')
		echom '...done'
	elseif char ==# 's'
		echom "Filtering by tasks..."
		call s:FilterByTask()
		echom '...done'
	elseif char ==# 'o'
		echom "Filtering by notes..."
		call s:FilterByNote()
		echom '...done'
	elseif char ==# 'e'
		echom 'Filtering by "has date"...'
		call s:FilterByHasDate()
		echom '...done'
	elseif char ==# 'R'
		echom 'Filtering by "has repetition"...'
		call s:FilterByRepetition()
		echom '...done'
	elseif char ==# 'y'
		echom 'Filtering by "today"...'
		call s:FilterByDate('Today')
		echom '...done'
	elseif char ==# 'h'
		echom 'Filtering by "this week"...'
		call s:FilterByDate('ThisWeek')
		echom '...done'
	elseif char ==# 'x'
		echom 'Filtering by "next week"...'
		call s:FilterByDate('NextWeek')
		echom '...done'
	elseif char ==# 'm'
		echom 'Filtering by "this month"...'
		call s:FilterByDate('ThisMonth')
		echom '...done'
	elseif char ==# 'p'
		echom 'Filtering by "past"...'
		call s:FilterByDate('Past')
		echom '...done'
	elseif char ==# 'g'
		echom 'Filtering by "upcoming"...'
		call s:FilterByDate('Upcoming')
		echom '...done'
	endif

	" set syntax
	call s:SetQfSyntax()
	
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

function! s:TaskToStr(task)
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

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                             Changes                                 "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:PropagateChanges()
	echom "Propagating changes"
	" get diff
	let diff = s:GetDiff()
	" get all lines
	let lines = extend([], extend(diff['changes'], diff['insertions']))
	call map(lines, 'getline(v:val)')
	" save location
	call s:SaveLocation()
	
	for line in lines
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

function! s:GenerateDatesFromRepetition(line, limit)
	
	let dates = []
	let rep   = s:ExtractRepetition(a:line)

	if rep['starttime'] != -1
		call add(dates, {'date':rep['startdate'], 'time' : rep['starttime']})
		let start = trim(system('dateadd '.shellescape(rep['startdate']).' +'.rep['operand'].''.rep['operator']))
	else
		let start = rep['startdate']
	endif
		
	" Add repetitions into the future, but limit how many.
	" We don't want to have too many dates in the lists, otherwise
	" greping will be slowed down.

	let today = strftime('%Y-%m-%d')
	if a:limit ==# ''
			
		if rep['enddate'] == -1
			if rep['operator'] ==# 'd'
				let limit = trim(system('dateadd today +3mo'))
			elseif rep['operator'] ==# 'w'
				let limit = trim(system('dateadd today +6mo'))
			elseif rep['operator'] ==# 'mo'
				let limit = trim(system('dateadd today +2y'))
			elseif rep['operator'] ==# 'y'
				let limit = trim(system('dateadd today +30y'))
			else
				let limit = trim(system('dateadd today +3mo'))
			endif
		else
			let limit = rep['enddate']
		endif
		
	else
		let limit = trim(system('dateadd today '.a:limit))
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
	echom "Validating syntax"
	let s:syntax_errors = []
	
	" reset matches set by previous syntax checks
	match none
	
	" TODO remove, once we also check the syntax of other items
	" filter not lines/notes
	for lnum in a:lines
		let line = getline(lnum)
		if s:IsLineNote(line) == v:false && s:IsLineTask(line) == v:false
			call filter(a:lines, 'v:val !=# '.lnum)
		endif
	endfor

	" syntax check
	for lnum in a:lines
		let line = getline(lnum)
		call s:CheckSyntax(line, lnum)
	endfor

	" throw possible syntax errors
	if len(s:syntax_errors) > 0
		call setqflist(s:syntax_errors, 'a')
		let lines = map(s:syntax_errors, 'v:val["lnum"]')
		let lines = map(lines, '"%".v:val."l"')
		let pat   = "(".join(lines, '|').").*$"
		execute 'match Error "\v'.pat.'"'
		highlight link VdoError Error
		echoerr "Syntax errors in ".expand('%').". See error list."
	endif
	
endfunction


function! s:ValidateId(lines)
	echom "Validating ids"
	for lnum in a:lines
		let line = getline(lnum)
		let item = s:ExtractLineData(line)
		if item['id'] == -1
			let item['id'] = s:NewID()
			call s:ReplaceLineWithTask(item, lnum)
		endi
	endfor
endfunction

function! s:RebuiltLine(lines)
	echom "Rebuilding lines"
	for lnum in a:lines
		let line = getline(lnum)
		let item = s:ExtractLineData(line)
		call s:ReplaceLineWithTask(item, lnum)
	endfor
endfunction

function! s:ProcessChanges(changes)
	echom "Processing changes"
endfunction

function! s:ProcessInsertions(insertions)
	echom "Processing insertions"
endfunction

function! s:ProcessDeletions(deletions)
	echom "Processing deletions"
endfunction

" process every line of the file
command! ProcessFile :call s:ProcessFile('all')
function! s:ProcessFile(what)
	" decide which lines should be processed
	if a:what ==# 'all'
		" all lines of file
		let lines = range(1, line('$')) 
		echom "Processing file ".expand('%')
	elseif a:what ==# 'visual'
		" lines of current visual selection
		let lines = range(line("'<"), line("'>"))
		echom "Processing line ".join(lines, ',')." of file ".expand('%')
	elseif a:what ==# 'current'
		" only current line
		let lines = [ line('.') ]
		echom "Processing line ".join(lines, ',')." of file ".expand('%')
	else
		echoerr "Unknown argument for `a:what` :".a:what
	endif

	try
		" syntax check
		call s:ValidateSyntax(lines)
		" id check
		call s:ValidateId(lines)
		" re-build line
		call s:RebuiltLine(lines)
		" propagate changes
		call s:PropagateChanges()
	catch /.*/
		echoerr v:exception." in ".v:throwpoint
	endtry

endfunction

command! -nargs=0 Change	:call s:TextChanged()
function! s:TextChanged()
	echom "Event: TextChanged in buffer ".bufname(bufnr())
	
	" get diff
	let changes = s:GetDiff()
	" check if there is anything to do
	if len(changes['insertions']) == 0
				\ && len(changes['deletions']) == 0
				\ && len(changes['changes']) == 0
		" nothing to do
		echom "Diff found no changes"
		return
	endif
	
	" reset matches set by previous syntax checks
	match none
	
	try 

		if len(changes['insertions']) > 0
			call s:ProcessInsertions(changes['insertions'])
		endif
		
		if len(changes['deletions']) > 0
			call s:ProcessDeletions(changes['deletions'])
		endif
		
		if len(changes['changes']) > 0
			call s:ProcessChanges(changes['changes'])
		endif
		
		" call s:ParseFile()
		" call s:DataComputeProgress()
		" call s:DrawSectionOverview()
		" call s:DrawProjectStatistics()

		" get list of changed buffers
		let buffers = deepcopy(getbufinfo({'buflisted':1, 'bufmodified':1}))
		" write all changed buffers
		silent wall
		echom "Writing file. Done."
		
	catch /.*/
		echoerr v:exception." in ".v:throwpoint
	endtry
		
	" update buffer list
	call s:UpdateBufferlist()
	
endfunction

function! s:DeleteUndofiles()	
	echom "Deleting undo-files"
	execute 'args '.g:vimdoit_projectsdir.'/**/.undo/*.vdo'
	argdo !rm %
endfunction
command! -nargs=0 RmUndo	:call s:DeleteUndofiles()

function! s:DeleteDatefiles()
	echom "Deleting date-files"
	execute 'args '.g:vimdoit_projectsdir.'/**/.*-dates.vdo'
	argdo !rm %
endfunction
command! -nargs=0 RmDates	:call s:DeleteDatefiles()

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                               Mappings                                "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:LoadMappings()

	if exists("b:vimdoit_did_load_mappings") == v:false
		echom "Loading mappings"
		
		" Grepping prompt
		nnoremap <leader>gg	:<c-u>call <SID>GrepPrompt('project')<cr>
		nnoremap <leader>g.	:<c-u>call <SID>GrepPrompt('area')<cr>
		nnoremap <leader>gr	:<c-u>call <SID>GrepPrompt('root')<cr>
		nnoremap <leader>gq	:<c-u>call <SID>GrepPrompt('quickfix')<cr>
		
		" Sort quickfix list
		nnoremap <leader>qs	:<c-u>call <SID>SortPrompt()<cr>
		" Filter quickfix list
		nnoremap <leader>qf	:<c-u>call <SID>FilterPrompt()<cr>
		" Nicen Quickfix
		nnoremap <leader>qn	:<c-u>call <SID>NicenQfByDate()<cr>
		" Set Quickfix set
		nnoremap <leader>qm :<c-u>call <SID>SetQfSyntax()<cr>
		
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

		" process current line
		nnoremap <leader>v	:<c-u>call <SID>ProcessFile('current')<cr>
		" process visual selection
		vnoremap <leader>v	:<c-u>call <SID>ProcessFile('visual')<cr>
		" process whole file
		nnoremap <leader>V	:<c-u>call <SID>ProcessFile('all')<cr>

		" create empty project in current directory
		nnoremap <leader>np	:<c-u>call <SID>NewProject()<cr>

		" gtd-view
		nnoremap <leader>oo	:<c-u>call <SID>GTDView('project')<cr>
		nnoremap <leader>o.	:<c-u>call <SID>GTDView('area')<cr>
		nnoremap <leader>or	:<c-u>call <SID>GTDView('root')<cr>
		nnoremap <leader>oq	:<c-u>call <SID>GTDView('quickfix')<cr>
		
		echom "Mappings loaded"
		let b:vimdoit_did_load_mappings = 1
	endif

endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                             Autocommands                              "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
augroup VimDoit
	autocmd!
	" autocmd ShellCmdPost * call s:UpdateBufferlist()
	" autocmd TextChanged *.vdo call s:TextChanged()
	autocmd BufWritePre *.vdo call s:ProcessFile('all')
	autocmd BufEnter *.vdo call s:LoadMappings()

	if v:vim_did_enter
		call s:Init()
	else
		autocmd VimEnter * call s:Init()
	endif
augroup END

" Restore user's options.
let &cpo = s:save_cpo
unlet s:save_cpo
