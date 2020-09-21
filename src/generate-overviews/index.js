/*
 * # Usage:
 * index.js -p foobar.vdo
 * index.js -a area
 * index.js -overview
 *
 * # Functions
 * writeOverview (displays all areas with stats)
 * writeAreaOverview (displays all projects of area with stats)
 *	- support for option '#pinned', those will be at the top
 * writeProject (displays single project)
 *	- collect data from links
 *	- no difference between sprint or project
 */

const minimist = require('minimist')
const jq       = require('node-jq')
const { ProjectTree } = require('./ProjectTree.js')
const { AreaTree } = require('./AreaTree')

let argv = minimist(process.argv.slice(2));
console.log(argv)
console.log(argv['s'])

/*
 * index.js -p PROJECT
 * Write overview of single project.
 */
if(argv['p'] !== undefined && argv['p'] !== '') {
	console.log(argv['p'])

	const myTree  = new ProjectTree('foobar')
	
	// load JSON
	const filter  = '.'
	const options = {}
	jq.run(filter, argv['p'], options)
		.then((output) => {
			let tree = JSON.parse(output)
			tree['jsonFile'] = argv['p']
			myTree.setTree(tree)
			
			// project
			myTree.traverse( ['project'], myTree.getRoot(), function(node) { 
				// add project heading
				myTree.addHeading(node.name)
				// add statistics
				myTree.addStats(myTree.getStats(node))
				// add progress bar of whole project
				myTree.addProgressBar(
					'standard'
				)
			})

			// // sections
			// myTree.traverse( ['section'], myTree.getRoot(), (node) => {
			// 	// add section heading
			// 	myTree.addHeading(node.name, node.level+1)
			// 	// add progress bar of section
			// 	myTree.addProgressBar(
			// 		'small',
			// 		myTree.getStats(node)
			// 	)
			// })

			// sections
			myTree.traverse( ['section' ], myTree.getRoot(), (node) => {

				if(node.level !== 1)
					return

				myTree.startSegment()

				// add section heading
				myTree.addToSegment({ 'level': node.level+1, 'name': node.name, 'stats': myTree.getStats(node) })
				
				myTree.traverse( ['section'], node, (node) => {
					if(node.level < 2)
						return
					myTree.addToSegment({ 'level': node.level+1, 'name': node.name, 'stats': myTree.getStats(node) })
				})	


				myTree.endSegment()
				// add progress bar of section
				// myTree.addProgressBar(
					// 'small',
					// myTree.getStats(node)
				// )
			})

			
			
			myTree.writeZettel()
			
			return
			// myTree.traverse(['section'], function(node) { console.log("section name: "+node.name) }, {})
			// myTree.traverse(['section', 'name', 'Misc'], function(node) { console.log("section misc: "+node.name) }, {})
			
			myTree.traverse(['task'], function(node) { console.log("tasks: "+node.name) }, {})

			// all tasks of section 'Currently Reading'
			// myTree.traverse(['section', 'name', 'Currently Reading'], (node) => {
			// 	console.log(node.name)
			// 	myTree.traverse(['task'], (node2) => { console.log("tasks: "+node2.name) }, {}, node)
			// }, {})
		})

} else if(argv['s'] !== undefined) {
	console.log("Computing Area Tree")

	let myTree = new AreaTree()
	myTree.setPath('/home/pepe/archive/projects')
	myTree.buildTree()
	// console.log(myTree.tree)
	// iterate recursively through project root and create object
	// if dir: recurse
	// if project: calculate statistics
	// after: recursing
	//		calculate area statistics from all project statistics and all subarea statistics
	// myTree.writeAreaTree()
}




// computing progress of secton
// section = new Tree()
// section.computeProgress()
