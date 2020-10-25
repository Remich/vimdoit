# vimdoit

# NOTES

- every action in the scheduled-directory (./todo) should be be a task
	- notes and everything else will be ignored when calculating backlog-/scheduled items
- dates will only be expanded when they are specifically being grepped for
	- filtering won't expand dates
- it is advised to copy expanded dates from the quickfix list into the actual projects

## auto-generated dates

- always keep a copy of a auto-generated date within the project/area in which it was created
	- e.g. having an auto-generated date from ./career/myproject.vdo only in ./todo/2020/kw-42.vdo
		- cd into ./career and grep for dates
		- the resulting list of dates will contain a duplicate of the auto-generated date, which actually is in ./todo/2020/kw-42.vdo, but with a different extended id!
