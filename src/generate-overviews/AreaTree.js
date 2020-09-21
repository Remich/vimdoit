const fs               = require('fs')
const path             = require('path');
const json2md          = require("json2md")
const { Tree }         = require('./Tree.js')
const { ProjectTree }  = require('./ProjectTree.js')
const { MarkdownTree } = require('./MarkdownTree.js')

const AreaTree = function() {

	const that = {}

	that.tree = {
		'name' : 'Unnamed Area',
		'type' : 'area',
		'root' : true,
		'stats' : undefined,
		'path' : undefined,
		'areas' : [],
		'projects' : []
	}

	that.nodes = []	
	that.nodes.push(that.tree)

	that.setPath = function(path) {
		that.tree.path = path
	}

	that.getCurNode = function() {
		return that.nodes[that.nodes.length-1]
	}

	that.setNodeName = function(name) {
		let cur = that.getCurNode()
		cur['name'] = name
	}

	that.addNodeProject = function(jsonFile) {
		// console.log("Loading JSON file from :" + jsonFile)
		let cur  = that.getCurNode()
		let tree = JSON.parse(fs.readFileSync(jsonFile, 'utf8'))
		tree['jsonFile'] = jsonFile
		cur['projects'].push(tree)
	}

	that.addNodeArea = function(areaPath) {
		let area = {
			'name' : that.getAreaName(areaPath),
			'path' : areaPath,
			'type' : 'area',
			'stats' : undefined,
			'areas' : [],
			'projects' : []
		}
		
		let cur = that.getCurNode()
		cur['areas'].push(area)
		that.nodes.push(area)
	}

	that.getAreaName = function(dir) {
		let infoFile = path.resolve(dir, '.info.json')
		let info = JSON.parse(fs.readFileSync(infoFile, 'utf8'));
		return info['name']
	}

	that.buildTree = function() {

		var walk = function(dir, done) {

			fs.readdir(dir, function(err, list) {
				if (err) return done(err)

				var i = 0;
				(function next() {
					var file = list[i++];
					if (!file) { 
						that.nodes.pop()
						return done(null, undefined);
					}

					if(file.match(/gitignore/g) !== null) {
						next()
						return
					}

					file = path.resolve(dir, file);

					fs.stat(file, function(err, stat) {
						if (stat && stat.isDirectory()) {

							if( file.match(/.*\/\.git.*/g) !== null) {
								next();
							} else {
								that.addNodeArea(file)
								walk(file, function(err, res) {
									next()
								});
							}
						} else {

							if( file.match(/.*\.json$/g) === null) {
								next()
								return
							}
							if( file.match(/.*\.info\.json$/g) !== null) {
								next()
								return
							}

							that.addNodeProject(file)
							next();
						}
					});
				})();
			});
		}


		walk(that.tree.path, (err, results) => {
			that.tree['name'] = that.getAreaName(that.tree.path)
			let tmp = that.tree
			that.tree = new Tree()
			that.tree.setTree(tmp)
			
			that.calculateStats(that.tree.getRoot())
			that.writeAreaOverviews()
		}, that.tree)

	}
	
	that.generateFilename = function(path) {
		let filename = path.replace('/home/pepe/archive/', '');	
		filename = filename.replace(/\//g, '-');	
		filename = filename.replace(/\./g, '');	
		filename = filename.replace('json', '-overview.md');	
		return 'area-'+filename
	}

	that.generateFilenameHTML = function(path) {
		return that.generateFilename(path)+'.html'
	}
	that.generateFilenameMD = function(path) {
		return that.generateFilename(path)+'.md'
	}

	that.getStats = function(node) {
		if(node.stats === undefined)
			that.calculateStats(node)
		
		return node.stats
	}

	that.getURI = function(node) {

		if(node['type'] === 'area')
			return `<a href="${that.generateFilenameHTML(node.path)}">${node.name}</a>`
		else if(node['type'] === 'project') {
			let tmpTree = new ProjectTree()
			tmpTree.setTree(node)
			return `<a href="${tmpTree.getFilenameHTML()}">${tmpTree.getName()}</a>`
		}
	}
	
	that.calculateStats = function(node) {

		let stats = {
			'areas' : 0,
			'projects' : 0,
			'tasks' : 0,
			'remaining' : 0,
			'done' : 0,
			'failed' : 0,
			'waiting' : 0,
			'blocking' : 0,
			'sections' : 0,
		}
		
		that.tree.traverse( ['area'], node, (node) => {
			
			if(node['root'] === true)
				return

			stats['areas']++
		})

		that.tree.traverse( ['project'], node, (node) =>  {
			stats['projects']++
			
			let tmpTree = new ProjectTree()
			tmpTree.setTree(node)
			
			let pstats = tmpTree.getStats()
			stats['tasks'] += pstats['tasks']
			stats['remaining'] += pstats['remaining']
			stats['done'] += pstats['done']
			stats['failed'] += pstats['failed']
			stats['waiting'] += pstats['waiting']
			stats['blocking'] += pstats['blocking']
			stats['sections'] += pstats['sections']
		})

		for(let i=0; i<node['areas'].length; i++) {
			that.calculateStats(node['areas'][i])
		}

		node.stats = stats
	}

	that.writeAreaOverviews = function() {
		
		that.tree.traverse( ['area'], that.tree.getRoot(), (node) => {
			
			let mdTree = new MarkdownTree()
			mdTree.setFilename(that.generateFilenameMD(node.path))
			
			mdTree.addHeading(node.name, 1)
			
			// Pinned
			mdTree.addHeading('Pinned', 2)

			// Areas
			mdTree.startSegment()
			for(let i=0; i<node['areas'].length; i++) {
				let handle = node['areas'][i]
				mdTree.addToSegment({ 'level': 2, 'name': '📁 '+that.getURI(handle), 'stats': that.getStats(handle) })
			}
			mdTree.endSegment()
			
			// Projects
			mdTree.startSegment()
			for(let i=0; i<node['projects'].length; i++) {
				let handle = node['projects'][i]
				let tmpTree = new ProjectTree()
				tmpTree.setTree(handle)
				mdTree.addToSegment({ 'level': 2, 'name': 'X '+that.getURI(handle), 'stats': tmpTree.getStats() })
			}
			mdTree.endSegment()

			// Actual Write
			mdTree.writeZettel()
		})
	}
	
	that.writeZettel = function(zettelName, areaNode) {
		const fs = require('fs')
		fs.writeFile(`/home/pepe/zettelkasten/${that.filename}`, json2md(areaNode), function (err) {
			if (err) return console.log(err);
			console.log(`${that.filename} written.`);
		});
	}

	return that
}

exports.AreaTree = AreaTree
