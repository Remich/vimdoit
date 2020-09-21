const json2md = require("json2md")

json2md.converters.meta = function(input, json2md) {
	let str = '---\n'
	str += 'date: 2020-08-16\n'
	str += 'tags:\n- type/project-overview\n'
	str += '---'
	return str
}
json2md.converters.progressBar = function(input, json2md) {
	let [ size, stats ]   = input
	const { ProgressBar } = require('./ProgressBar')
	let Bar               = new ProgressBar(size, stats)
	return Bar.getBar()
}
json2md.converters.dom = function(input, json2md) {
	return input
}

json2md.converters.blockHeader = function(input, json2md) {
	let [ level, text ] = input
	let str = `
<h${level} class="ui block header">
	${text}
</h${level}>
	`
	return str.trim()
}

const MarkdownTree = function() {

	const that  = {}
	
	that.treeMd   = [ {'meta': ''} ]
	that.filename = 'unnamed-zettel.md'

	that.setFilename = function(name) {
		that.filename = name
	}

	that.addHeading = function(str, level = 1) {

		let heading

		if(level === 1)
			heading = { 'h1' : str }
		else if(level === 2)
			heading = { 'blockHeader' : [ 2, str ] }
		else if(level === 3)
			heading = { 'h3' : str }
		else if(level === 3)
			heading = { 'h3' : str }
		else if(level === 4)
			heading = { 'h4' : str }
		else if(level === 5)
			heading = { 'h5' : str }
		else
			heading = { 'h6' : str }

		that.treeMd.push( heading )
	}

	that.addProgressBar = function(size, stats) {
		that.treeMd.push( {'progressBar' : [ size, stats ]} )
	}

	that.addDescription = function(str) {
		that.treeMd.push( {'blockquote' : `*${str}*`} )
	}

	that.getStatsStr = function(stats) {
		let { sections, tasks, done, failed, waiting, blocking, remaining } = stats
		let str = `**Sections:** ${sections}, **Tasks:** ${tasks}, **Done:** ${done}, **Failed:** ${failed}, **Waiting:** ${waiting}, **Blocking:** ${blocking}, **Remaining:** ${remaining}`
		return str
	}

	that.addStats = function(stats) {
		let str = that.getStatsStr(stats)	
		that.treeMd.push({ 'p' : str })
	}

	that.writeZettel = function() {
		const fs = require('fs')
		fs.writeFile(`/home/pepe/zettelkasten/${that.filename}`, json2md(that.treeMd), function (err) {
			if (err) return console.log(err);
			console.log(`${that.filename} written.`);
		});
	}

	that.currentSegment = undefined

	that.startSegment = function() {
		that.currentSegment = []
	}

	that.addToSegment = function(seg) {
		that.currentSegment.push(seg)	
	}

	that.addHeaderToSegment = function(str, lvl) {
		let seg = {
			"level" : lvl,
			"name" : str,
			"stats" : undefined
		}
		
		that.addToSegment(seg)
	}
	
	that.endSegment = function() {
		const { ProgressBar } = require('./ProgressBar')

		let str = '<div class="ui segments">'
		let curlevel = 2
		for(let i=0; i<that.currentSegment.length; i++) {
			let {level, name, stats} = that.currentSegment[i]

			let top      = ''
			let progress = ''
			
			if(level > curlevel) {
				str += '<div class="ui secondary attached segment">'
				curlevel = level
				top = 'top'
			} else if(level < curlevel) {
				while(curlevel-- > level)
					str += '</div>'
				curlevel = level
				top = ''
			}

			if(stats !== undefined) {
				let Bar = new ProgressBar('small', stats)
				progress = Bar.getBar()
			} else {
				top = 'top'
			}
			
			str += `<h${level} class="ui ${top} attached header">${name}${progress}</h${level}>`
			
		}

		while(curlevel-- > 2)
			str += '</div>'
		
		str += '</div>'

		that.treeMd.push({ 'dom' : str })
	}

	return that
}

exports.MarkdownTree = MarkdownTree
