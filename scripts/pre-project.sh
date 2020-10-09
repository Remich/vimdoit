#!/bin/bash

line="$(head -n 1 "$1")"
if [[ $line =~ \#complete|\#cancelled|\#archived ]]; then
	exit 0
else
	cat "$1"
fi

exit 0
