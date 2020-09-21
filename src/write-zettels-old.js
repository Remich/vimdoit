// load modules
const minimist = require('minimist')
const json2md = require("json2md")
const fs = require('fs')

let data
console.log('hi')

fs.readFile('/home/pepe/projects-new/data.json', 'utf8', function (err,data) {
  if (err) {
    return console.log(err);
  }
	console.log(data)
	data = JSON.parse(data)
});

// console.log(data)

process.exit(0)

// parse arguments
let argv = minimist(process.argv.slice(2));

// log results to console as a stringified JSON object
let returnResult = function(obj) {
	console.log(JSON.stringify(obj))
}

// get project-tree
if(argv['d'] !== undefined) {
	project = JSON.parse(argv['d'])
	console.log(project['name'])
	console.log(project['type'])
} else {
	console.log("ERROR: No Data supplied.")
}

let mdTree = []

json2md.converters.meta = function (input, json2md) {
	let str = '---\n'
	str += 'date: 2020-08-15\n'
	str += 'tags:\n- type/project/test\n'
	str += '---'
	return str
}

mdTree.push( { 'meta' : "" } )
mdTree.push( { 'h1' : project['name'] + " ("+project['progress']*100+"%)" } )
let handle = project['sections']
for(const key in handle) {
	console.log(handle[key])
	
	mdTree.push( { 'h2': handle[key]['name'] } )
	
	if(handle[key]['tasks'].length > 0)
		for(const task of handle[key]['tasks'])
			mdTree.push( { 'p' : '- [ ] '+ task['name'] } )
	
}

// mdTree.push( { 'p' : 'This is a test' } )
// mdTree.push( { 'h2' : project['name']+'foobar' } )
// mdTree.push( { 'p' : 'This is a test' } )

console.log(mdTree)
console.log(json2md(mdTree))
// write
fs.writeFile('/home/pepe/zettelkasten/project-test.md', json2md(mdTree), function (err) {
	if (err) return console.log(err);
	console.log('Write successful.');
});
