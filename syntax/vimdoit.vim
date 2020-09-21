if exists("b:current_syntax")
    finish
endif

let b:current_syntax = "vimdoit"

" Project Vision
syntax region Vision start="\%2l\zs.*" end="\ze^\==="
highlight link Vision Comment

" Section Header
" syntax region SectionHeader start="^\===.*===$" start="^\---.*--$" end="^$" contains=SectionDelimiter,SectionHeadline,FlagRegion
" highlight link SectionHeader Operator

" Section Delimiter
syntax match SectionDelimiter "^\===.*===$"
syntax match SectionDelimiter "^\---.*--$"
highlight link SectionDelimiter Identifier

" Section Headings
syntax match SectionHeadlineDelimiter "\v\<" contained conceal
syntax match SectionHeadlineDelimiter "\v\>" contained conceal
syntax match SectionHeadline "\v^\t*\zs\<[^\>]*\>\ze" contains=SectionHeadlineDelimiter
highlight link SectionHeadline Operator
highlight link SectionHeadlineDelimiter Comment

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
" syntax match SingleSinglequote "\v[^ \t]\zs'\ze[^ \t]" contained
syntax match VimdoitString "\v[ \t]\zs['"].{-}['"]\ze[ \t,.!:\n]" contains=SingleSinglequote
highlight link VimdoitString String

" Time & Timespan
syntax match Appointment "\v\{.*\}"
" syntax match Appointment "\v\<\d{2}:\d{2}\>"
" syntax match Appointment "\v\<\d{2}:\d{2}-\d{2}:\d{2}\>"
" syntax match Appointment "\v\<\d{4}-\d{2}-\d{2} \d{2}:\d{2}\>"
highlight link Appointment Constant

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

" Flag Block ('-block#23')
" syntax match FlagBlock "\v-block#\d+" contained
syntax match FlagBlock "\v\$\d+" contained
highlight link FlagBlock Delimiter

" Flag Waiting For Block ('-waiting=block#23')
" syntax match FlagWaiting "\v-waiting\=block#\d+" contained
syntax match FlagWaiting "\v\~\d+" contained
" Flag Waiting For Date ('-waiting=2020-07-08')
syntax match FlagWaiting "\v-waiting\=\d{4}-\d{2}-\d{2}" contained
highlight link FlagWaiting String

" Flag ID ('-id=2323234234')
syntax match FlagID "\v-id\=[^ \t]+" contained conceal
highlight link FlagID NerdTreeDir

" Flag ordinary tag ('#SOMESTRING')
syntax match FlagTag "\v#[^ \t]*" contained
highlight link FlagTag Identifier

" Flag Region
syntax region FlagRegion start="\v\s--\s" end="$" contains=Flag,FlagDelimiter,FlagBlock,FlagWaiting,FlagInProgress,FlagSprint,FlagTag,FlagID
highlight link FlagRegion NerdTreeDir

" Task (not used)
" syntax region Task start="\v\s*-\s\[.*\]\s\zs" end="\ze\s--" end="$" contains=ExclamationMark,Info
" te
"
" highlight link Task Ignore


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
highlight link TaskDueToday Orange

" Task overdue
syntax match TaskOverdue "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-overdue" contains=ExclamationMark,Info
highlight link TaskOverdue Orange

" Task Done, also all of it's subtasks.
syntax region TaskDone start="\v^\t{0}- \[x\]+" skip="\v^\t{1,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{1}- \[x\]+" skip="\v^\t{2,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{2}- \[x\]+" skip="\v^\t{3,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{3}- \[x\]+" skip="\v^\t{4,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{4}- \[x\]+" skip="\v^\t{5,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{5}- \[x\]+" skip="\v^\t{6,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{6}- \[x\]+" skip="\v^\t{7,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{7}- \[x\]+" skip="\v^\t{8,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{8}- \[x\]+" skip="\v^\t{9,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{9}- \[x\]+" skip="\v^\t{10,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{10}- \[x\]+" skip="\v^\t{11,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{11}- \[x\]+" skip="\v^\t{12,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{12}- \[x\]+" skip="\v^\t{13,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{13}- \[x\]+" skip="\v^\t{14,}" end="^" contains=FlagID
syntax region TaskDone start="\v^\t{14}- \[x\]+" skip="\v^\t{15,}" end="^" contains=FlagID

syntax match TaskFailedMarker "\v\[F\]" contained
highlight link TaskFailedMarker Error

syntax region TaskFailed start="\v^\t{0}- \[F\]+" skip="\v^\t{1,}" end="^" contains=TaskFailedMarker,FlagID
syntax region TaskFailed start="\v^\t{1}- \[F\]+" skip="\v^\t{2,}" end="^" contains=TaskFailedMarker,FlagID
highlight link TaskDone NerdTreeDir
highlight link TaskFailed NerdTreeDir
