const json2md = require("json2md")
const { Tree } = require('./Tree.js')

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

const ProjectTree = function() {

	const that  = new Tree()

	that.tree         = undefined
	that.jsonFile     = undefined
	that.treeMd       = [ {'meta': ''} ]
	that.baseFilename = undefined
	that.stats        = undefined

	that.setJSONFile = function(file) {
		that.jsonFile = file
		that.generateBaseFilename()
	}

	that.getName = function() {
		return that.tree['name']
	}

	that.setTree = function(tree) {
		that.tree = tree
		that.jsonFile = tree['jsonFile']
		that.generateBaseFilename()
	}

	that.getTree = function() {
		return that.tree
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

	that.foobar = function() {
		for(let i=0; i<that.tree['areas'].length; i++)
			console.log(that.tree['areas'][i]['name'])
	}
	
	that.getStats = function() {
		if(that.stats === undefined)
			that.calculateStats(that.getRoot())
		
		return that.stats
	}

	// computes the progress of the entire Tree
	that.calculateStats = function(node) {

		let stats = {
			'tasks' : 0,
			'remaining' : 0,
			'done' : 0,
			'failed' : 0,
			'waiting' : 0,
			'blocking' : 0,
			'sections' : 0,
		}

		that.traverse(['section'], node, (node) => {
			stats['sections']++
		})

		that.traverse(['task'], node, (node) => {

			stats['tasks']++

			if(node['done'] === true) 
				stats['done']++
			if(node['waiting'] === true)
				stats['waiting']++
			if(node['failed'] === true)
				stats['failed']++
			if(node['blocking'] === true)
				stats['blocking']++
		})

		stats['remaining'] = stats['tasks'] - stats['done'] - stats['failed']
		
		that.stats = stats
	}

	that.addProgressBar = function(size) {
		that.treeMd.push( {'progressBar' : [ size, that.getStats() ]} )
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

	that.generateBaseFilename = function() {
		let filename = that.jsonFile.replace('/home/pepe/archive/projects/', '');	
		filename = filename.replace(/\//g, '-');	
		filename = filename.replace(/\./g, '');	
		filename = filename.replace('json', '');	
		that.baseFilename = 'projects-'+filename+'-overview'
	}

	that.getFilenameMD = function() {
		return that.baseFilename+'.md'
	}
	
	that.getFilenameHTML = function() {
		return that.baseFilename+'.html'
	}

	that.writeZettel = function() {
		const fs = require('fs')
		fs.writeFile(`/home/pepe/zettelkasten/${that.getFilenameMD()}`, json2md(that.treeMd), function (err) {
			if (err) return console.log(err);
			console.log(`${that.getFilenameMD()} written.`);
		});
	}


	that.currentSegment = undefined

	that.startSegment = function() {
		that.currentSegment = []
	}

	that.addToSegment = function(seg) {
		that.currentSegment.push(seg)	
	}

	that.endSegment = function() {
		const { ProgressBar } = require('./ProgressBar')

		let str = '<div class="ui segments">'
		let curlevel = 2
		for(let i=0; i<that.currentSegment.length; i++) {
			let {level, name, stats} = that.currentSegment[i]

			let top = ''
			
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

			let Bar = new ProgressBar('small', stats)
			let progress = Bar.getBar()
			str += `<h${level} class="ui ${top} attached header">${name}${progress}</h${level}>`
			
		}

		while(curlevel-- > 2)
			str += '</div>'
		
		str += '</div>'

		that.treeMd.push({ 'dom' : str })
	}

	return that
}

exports.ProjectTree = ProjectTree
