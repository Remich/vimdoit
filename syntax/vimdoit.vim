if exists("b:current_syntax")
    finish
endif

let b:current_syntax = "vimdoit"

" Project Vision
syntax region Vision start="\%2l\zs.*" end="\ze^\==="
highlight link Vision Comment

" Section Delimiter
syntax match Section "^\===.*===$"
syntax match Section "^\---.*--$"
highlight link Section Identifier

" Section Headings
syntax match SectionHeadingDelimiter "\v\<" contained conceal
syntax match SectionHeadingDelimiter "\v\>" contained conceal
syntax match SectionHeading "\v^\t*\<.*\>" contains=SectionHeadingDelimiter
syntax match SectionHeadingFlagRegion "\v\t*\<.*\>.*$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagInProgress,FlagSprint,SectionHeading
highlight link SectionHeading Operator
highlight link SectionHeadingDelimiter Comment

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
" syntax match SingleSinglequote "\v[^ \t]\zs'\ze[^ \t]" contained
syntax match VimdoitString "\v[ \t]\zs['"].{-}['"]\ze[ \t,.!:]" contains=SingleSinglequote
highlight link VimdoitString String

" Time & Timespan
syntax match Appointment "\v\<\d{2}:\d{2}\>"
syntax match Appointment "\v\<\d{2}:\d{2}-\d{2}:\d{2}\>"
highlight link Appointment Constant

" URLs
syntax match URL `\v<(((https?|ftp|gopher)://|(mailto|file|news):)[^' 	<>"]+|(www|web|w3)[a-z0-9_-]*\.[a-z0-9._-]+\.[^' 	<>"]+)[a-zA-Z0-9/]`
highlight link URL String

" Flag Delimiter ('--')
syntax match FlagDelimiter "\v\s--\s" contained
highlight link FlagDelimiter Comment

" Flag Normal ('-flag')
syntax match Flag "\v\zs-.*ze\s" contained
highlight link Flag Comment

" Flag Sprint ('@sprint')
syntax match FlagSprint '\v\@[^ \t]+'
syntax match FlagSprint "\v\@today" contained
syntax match FlagSprint "\v\@week" contained
highlight link FlagSprint Constant

" Flag Block ('-block#23')
syntax match FlagBlock "\v-block#\d+" contained
highlight link FlagBlock Delimiter

" Flag Waiting For Block ('-waiting=block#23')
syntax match FlagWaiting "\v-waiting\=block#\d+" contained
" Flag Waiting For Datte ('-waiting=2020-07-08')
syntax match FlagWaiting "\v-waiting\=\d{4}-\d{2}-\d{2}" contained
highlight link FlagWaiting String

" Flag In-Progress ('-in-progress')
syntax match FlagInProgress "\v-in-progress" contained
highlight link FlagInProgress Identifier
	
" Flag Region
syntax region FlagRegion start="\v\s--\s" end="$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagInProgress,FlagSprint
highlight link FlagRegion NerdTreeDir

" Task (not used)
" syntax region Task start="\v\s*-\s\[.*\]\s\zs" end="\ze\s--" end="$" contains=ExclamationMark,Info
" highlight link Task Ignore

" Task Done
syntax region TaskDone start="\v\s*\zs-\s\[x\]\s" end="\v\ze-\s\[.{1}\]" end="\v^\s*$"
highlight link TaskDone NerdTreeDir

" syntax match TaskBlock "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-block" contains=ExclamationMark,Info
" highlight link TaskBlock Bold

" syntax match TaskWaiting "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-blocked" contains=ExclamationMark,Info
" highlight link TaskWaiting Delimiter

" syntax match TaskScheduledWeek "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-week" contains=ExclamationMark,Info
" highlight link TaskScheduledWeek Constant

" Task Scheduled for today
syntax match TaskScheduledToday "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*\@today" contains=ExclamationMark,Info,Appointment
highlight link TaskScheduledToday Orange

" Task due today
syntax match TaskDueToday "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-due\=today" contains=ExclamationMark,Info,Appointment
highlight link TaskDueToday Error

" Task overdue
syntax match TaskOverdue "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-overdue" contains=ExclamationMark,Info,Appointment
highlight link TaskOverdue Error
