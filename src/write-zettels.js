// load modules
const minimist = require('minimist')
const json2md = require("json2md")
const fs = require('fs')
const jq = require('node-jq')
const tree = require('./tree.js')

const jsonPath = '/home/pepe/archive/projects/data.json'
const filter   = '.'
const options  = {}

let dataTree

jq.run(filter, jsonPath, options)
	.then((output) => {

		dataTree   = JSON.parse(output)
		let mdTree     = []
		// let name       = dataTree['name']
		let nameZettel = `project-overview-all.md`

		generateMarkdownTreeOfActiveSprints(dataTree, mdTree)
		// return


		generateMarkdownTree(dataTree, mdTree, 1)
		writeZettel(nameZettel, mdTree)
	})
	.catch((err) => {
		console.error(err)
	})

json2md.converters.meta = function(input, json2md) {
	let str = '---\n'
	str += 'date: 2020-08-16\n'
	str += 'tags:\n- type/project-overview\n'
	str += '---'
	return str
}

let generateMarkdownTreeProject = function(section, mdTree, level) {

	// heading
	let heading

	if(level === 1)
		heading = { 'h1' : section['name']+" – Overview" }
	else if(level === 2)
		heading = { 'h2' : section['name'] }
	else if(level === 3)
		heading = { 'h3' : section['name'] }
	else if(level === 3)
		heading = { 'h3' : section['name'] }
	else if(level === 4)
		heading = { 'h4' : section['name'] }
	else if(level === 5)
		heading = { 'h5' : section['name'] }
	else
		heading = { 'h6' : section['name'] }

	mdTree.push( heading )

	// section
	if(section['sections'].length > 0) {
		for(let j=0; j<section['sections'].length; j++)
			generateMarkdownTreeProject(section['sections'][j], mdTree, level+1)
	}
}

let writeProjectOverview = function(project) {
	
	let mdTree     = []
	// let name       = dataTree['name']
	let nameZettel = `project-testoverview.md`
	generateMarkdownTreeProject(project, mdTree, 1)
	writeZettel(nameZettel, mdTree)
}

let generateMarkdownTreeOfActiveSprints = function(dataTree, mdTree) {

	mdTree.push({ 'meta' : '' })
	let activeSprints = []
	// // TODO hier weitermachen
	getActiveSprints(dataTree, activeSprints)
	for(let i=0; i<activeSprints.length; i++) {
		loadLinksIntoSprints(activeSprints[i])
		writeProjectOverview(activeSprints[i])
	}
	// console.log(JSON.stringify(activeSprints[0]))

	// console.log(active)

}


let findProject = function(area, name, find) {

	let { projects, areas } = area

	for(let i=0; i<projects.length; i++) {
		let pname = projects[i]['name']
		if(pname === name) {
			find.push(projects[i])
			return
		}
	}

	for(let j=0; j<areas.length; j++)
		findProject(areas[j], name, find)
}
let findLinksFromSection = function(sec) {

	for(let j=0; j<sec['tasks'].length; j++) {
		
		let task = sec['tasks'][j]	
		if(task['type'] === 'link') {
			// console.log("searchProject: " + task['project'])
			let pj = []
			findProject(dataTree, task['project'], pj)	
			// replace
			sec['sections'].push(pj[0])
			// sec['tasks'][j] = pj[0]
		}
			// console.log("link: ".task['link'])
	}
	
	for(let k=0; k<sec['sections'].length; k++)
		findLinksFromSection(sec['sections'][k])
}

let loadLinksIntoSprints = function(sprint) {
	for(let i=0; i<sprint['sections'].length; i++) {
		let sec = sprint['sections'][i]

		findLinksFromSection(sec)

	}
	// console.log(sprint['sections'])
}

let computeProgress = function(pj) {
	console.log(pj)
	jq.run('.', pj, { input: 'json' })
		.then((output) => {
			console.log(output) 
		})
}

let getActiveSprints = function(area, active) {

	let { projects, areas } = area

	for(let i=0; i<projects.length; i++) {
		let tags = projects[i]['flags']['tag']
		if(tags !== undefined)
			if(tags.includes("#active") && tags.includes("#sprint"))
				active.push(projects[i])
	}

	for(let j=0; j<areas.length; j++)
		getActiveSprints(areas[j], active)
}


let getStatsSection = function(sec, stats) {
	for(let j=0; j<sec['tasks'].length; j++)
		getStatsTask(sec['tasks'][j], stats)
	for(let i=0; i<sec['sections'].length; i++)
		getStatsSection(sec['sections'][i], stats)
}

let getStatsTask = function(obj, stats) {

	if(obj['type'] !== 'task')
		return

	stats['tasks']++

	if(obj['done'] === true) 
		stats['done']++
	if(obj['waiting'] == true)
		stats['waiting']++
	if(obj['failed'] == true)
		stats['failed']++

	for(let j=0; j<obj['tasks'].length; j++)
		getStatsTask(obj['tasks'][j], stats)
}


json2md.converters.projectItem = function(input, json2md) {

	let { name } = input
	let stats = {
		'tasks' : 0,
		'done' : 0,
		'failed' : 0,
		'waiting' : 0,
	}
	getStatsSection(input, stats)

	let done
	if(stats['tasks'] === 0 && stats['done'] === 0)
		done = 0
	else
		done = (stats['done'] / stats['tasks']) * 100

	let failed
	if(stats['tasks'] === 0 && stats['failed'] === 0)
		failed = 0
	else
		failed = (stats['failed'] / stats['tasks']) * 100


	// TODO move to function: renderProgressBar()
	let red
	if (failed === 0)
		red = ' '
	else
		red = `<div class="red bar" style="transition-duration: 300ms; display: block; width: ${failed}%; border-radius: 0px;"> <div class="progress">${failed.toFixed(0)}%</div> </div>`

	let str = `
<span class="text" style="font-weight: bold">
	${name}
</span>
<div class="ui small multiple progress" data-percent="${done},${failed}">
	<div class="bar" style="transition-duration: 300ms; display: block; width: ${done}%;">
		<div class="progress">${done.toFixed(0)}%</div>
	</div>${red}
</div>
`

	console.log(str)
	return str.trim()
}

let generateMarkdownTree = function(area, mdTree, level) {

	// heading
	let heading

	if(level === 1)
		heading = { 'h1' : area['name']+" – Overview" }
	else if(level === 2)
		heading = { 'h2' : area['name'] }
	else if(level === 3)
		heading = { 'h3' : area['name'] }
	else if(level === 3)
		heading = { 'h3' : area['name'] }
	else if(level === 4)
		heading = { 'h4' : area['name'] }
	else if(level === 5)
		heading = { 'h5' : area['name'] }
	else
		heading = { 'h6' : area['name'] }

	mdTree.push( heading )

	// projects
	if(area['projects'].length > 0) {
		let pjs = []
		for(let j=0; j<area['projects'].length; j++)
			mdTree.push({ 'projectItem' : area['projects'][j] })
	}

	// areas
	if(area['areas'].length > 0) {
		for(let j=0; j<area['areas'].length; j++)
			generateMarkdownTree(area['areas'][j], mdTree, level+1)
	}
}

let writeZettel = function(filename, tree) {
	fs.writeFile(`/home/pepe/zettelkasten/${filename}`, json2md(tree), function (err) {
		if (err) return console.log(err);
		console.log(`${filename} written.`);
	});
}

// fs.readFile('/home/pepe/projects-new/data.json', 'utf8', function (err,data) {
//   if (err) {
//     return console.log(err);
//   }
// 	data = JSON.parse(data)
// 	console.log(data.areas[4])
// });
//
// console.log(data)
