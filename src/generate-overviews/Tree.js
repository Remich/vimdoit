const Tree = function() {

	const that  = {}
	that.tree     = undefined

	that.setTree = function(tree) {
		that.tree = tree
	}

	that.getRoot = function() {
		return that.tree
	}

	that.getType = function(node) {
		return node['type']
	}

	that.getAttribute = function(node, attribute) {
		return node[attribute]
	}

	// USAGE:
	// find project with name `foobar`: traverse('project', [ 'name', 'foobar ], (val) => { })
	that.traverse = function(criteria, node, callback) {
		// type says on what type of structure in the tree criteria should be checked
		let [ type, attribute, value ] = criteria

		// check for callback condition
		if(type !== undefined && attribute === undefined && value === undefined) {
			if(type === that.getType(node)) {
				callback(node)	
			}
		} else if(type === undefined && attribute !== undefined && value !== undefined) {
			if(that.getAttribute(node, attribute) === value) {
				callback(node)
			}
		} else if(type !== undefined && attribute !== undefined && value !== undefined) {
			if(type === that.getType(node)
				&& that.getAttribute(node, attribute) === value) {
				callback(node)
			}
		}

		// recurse tasks
		if(node['tasks'] !== undefined)
			for(let i=0; i<node['tasks'].length; i++) {
				that.traverse(criteria, node['tasks'][i], callback)
			}

		// recurse sections
		if(node['sections'] !== undefined)
			for(let i=0; i<node['sections'].length; i++) {
				that.traverse(criteria, node['sections'][i], callback)
			}

		// recurse projects
		if(node['projects'] !== undefined)
			for(let i=0; i<node['projects'].length; i++) {
				that.traverse(criteria, node['projects'][i], callback)
			}
		
		// recurse areas
		if(node['areas'] !== undefined)
			for(let i=0; i<node['areas'].length; i++) {
				that.traverse(criteria, node['areas'][i], callback)
			}
	}

	return that
}

exports.Tree = Tree
