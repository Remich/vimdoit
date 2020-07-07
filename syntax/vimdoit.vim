if exists("b:current_syntax")
    finish
endif

let b:current_syntax = "vimdoit"

syntax match Section "^\===.*===$"
syntax match Section "^\---.*--$"
highlight link Section Identifier

syntax match SectionHeading "\v^((\u|\d){1,}(\s|\-)*)+"
highlight link SectionHeading Operator

syntax match ExclamationMark "\v!+"
highlight link ExclamationMark Tag

syntax match Info "\v(\u|\s)+:"
highlight link Info Todo

syntax match Code "\v`.*`"
highlight link Code Comment

" syntax match Status "\v\(.*\)"
" highlight link Status String

syntax match URL `\v<(((https?|ftp|gopher)://|(mailto|file|news):)[^' 	<>"]+|(www|web|w3)[a-z0-9_-]*\.[a-z0-9._-]+\.[^' 	<>"]+)[a-zA-Z0-9/]`
highlight link URL String

" Task
" syntax region Task start="\v\s*-\s\[.*\]\s\zs" end="\ze\s--" end="$" contains=ExclamationMark,Info
" highlight link Task Ignore

syntax match FlagDelimiter "\v\s--\s" contained
highlight link FlagDelimiter Comment

syntax match Flag "\v-.*[^\s]" contained conceal
highlight link Flag Function
	
syntax region FlagRegion start="\v\s--\s" end="$" contains=FlagsStart,Flag
highlight link FlagRegion Comment

syntax region TaskDone start="\v\s*\zs-\s\[x\]\s" end="\ze\s--" end="$" contains=ExclamationMark
highlight link TaskDone NerdTreeDir

syntax match TaskScheduledWeek "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-week" contains=ExclamationMark
highlight link TaskScheduledWeek Constant

syntax match TaskScheduledToday "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-today" contains=ExclamationMark
highlight link TaskScheduledToday Statement

syntax match TaskDueToday "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-due\=today" contains=ExclamationMark
highlight link TaskDueToday Error

syntax match TaskOverdue "\v\s*-\s\[.{1}\]\s\zs.*\ze\s--\s.*-overdue" contains=ExclamationMark
highlight link TaskOverdue Error

syntax region TaskInProgress start="\v\s*-\s\[-\]\s\zs" end="\ze\s--" end="$" contains=ExclamationMark
highlight link TaskInProgress Todo

