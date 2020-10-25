#!/bin/bash

filename="$1"
curdate="$(date +%Y-%m-%d)"
curweek="$(date +%V)"
curmonth="$(date +%m)"

# check if the filename is of type daily-project
if [[ $filename =~ [[:digit:]]{4}\-[[:digit:]]{2}\-[[:digit:]]{2} ]]; then
	date="${BASH_REMATCH[0]}"
	if [[ $date < $curdate ]]; then
		cat "$1"
		exit 0
	fi
fi

# check if the filename is of type weekly-project
if [[ $filename =~ kw\-([[:digit:]]{2}) ]]; then
	week="${BASH_REMATCH[1]}"
	if [[ $week < $curweek ]]; then
		cat "$1"
		exit 0
	fi
fi

# check if the filename is of type monthly-project
if [[ $filename =~ ([[:digit:]]{2})\-(januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember) ]]; then
	month="${BASH_REMATCH[1]}"
	if [[ $month < $curmonth ]]; then
		cat "$1"
		exit 0
	fi
fi

exit 0
