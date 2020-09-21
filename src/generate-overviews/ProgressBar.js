const ProgressBar = function(size, stats) {
	
	const that = {}

	that.size  = size
	that.stats = stats
	that.percentage = undefined
	
	that.calculatePercentage = function() {
		let f = function(n1, n2) {
			if(n1 === 0 && n2 === 0)
				return 0
			else
				return ((n1 / n2) * 100).toFixed(0)
		}
		that.percentage = {
			'done' : f(that.stats['done'], that.stats['tasks']),
			'failed' : f(that.stats['failed'], that.stats['tasks']),
			'waiting' : f(that.stats['waiting'], that.stats['tasks']),
			'blocking' : f(that.stats['blocking'], that.stats['tasks'])
		}
	}

	that.getDataPercentage = function() {
		l = []

		if(that.stats['done'] > 0)
			l.push(that.percentage['done'])
		if(that.stats['failed'] > 0)
			l.push(that.percentage['failed'])
		if(that.stats['waiting'] > 0)
			l.push(that.percentage['waiting'])
		if(that.stats['blocking'] > 0)
			l.push(that.percentage['blocking'])

		if(l.length === 0)
			l.push('0')

		return l.join(',')
	}
	
	that.getBar = function() {
		
		that.calculatePercentage()

		let grey           = that.getBarGrey()
		let red            = that.getBarRed()
		let yellow         = that.getBarYellow()
		let orange         = that.getBarOrange()
		let dataPercentage = that.getDataPercentage()

		let str = `
	<div class="ui ${that.size} multiple progress" data-percent="${dataPercentage}"> ${grey}${red}${yellow}${orange} </div>
	`
		return str.trim()
	}

	that.hasBarToTheLeft = function(bar) {
		if(bar === 'grey')
			return false
		else if(bar === 'red')
			return that.stats['done'] > 0 ? true : false
		else if(bar === 'yellow') {
			if(that.stats['done'] > 0
				|| that.stats['failed'] > 0)
				return true
			else
				return false
		} else if(bar === 'orange') {
			if(that.stats['done'] > 0
				|| that.stats['failed'] > 0
				|| that.stats['waiting'] > 0)
				return true
			else
				return false
		}
	}

	that.hasBarToTheRight = function(bar) {
		if(bar === 'grey') {
			if(that.stats['failed'] > 0
				|| that.stats['waiting'] > 0
				|| that.stats['blocking'] > 0)
				return true
			else
				return false
		} else if(bar === 'red') {
			if(that.stats['waiting'] > 0
				|| that.stats['blocking'] > 0)
				return true
			else
				return false
		} else if(bar === 'yellow') {
			if(that.stats['blocking'] > 0)
				return true
			else
				return false
		}
	}

	that.isOnlyBar = function(bar) {
		if(that.stats['failed'] === 0
			&& that.stats['waiting'] === 0
			&& that.stats['blocking'] === 0)
			return true
		else
			return false
	}
	
	that.getBarGrey = function() {
		if(that.stats['done'] === 0 && that.isOnlyBar('grey') === false)
			return ''
		
		let borderRadius = that.hasBarToTheRight('grey') === true ? 'border-top-right-radius: 0px; border-bottom-right-radius: 0px;' : '' 
		let str = `
<div class="bar" style="transition-duration: 300ms; display: block; width: ${that.percentage['done']}%; ${borderRadius}">
	<div class="progress">${that.stats['done']}</div>
</div>`
		
		return str.trim()
	}

	that.getBarRed = function() {
		if(that.stats['failed'] === 0)
			return ''
		
		let borderRadiusLeft = that.hasBarToTheLeft('red') === true ? 'border-top-left-radius: 0px; border-bottom-left-radius: 0px;' : ''
		let borderRadiusRight = that.hasBarToTheRight('red') === true ? 'border-top-right-radius: 0px; border-bottom-right-radius: 0px;' : ''

		let str = `
<div class="red bar" style="transition-duration: 300ms; display: block; width: ${that.percentage['failed']}%; ${borderRadiusRight} ${borderRadiusLeft}">
	<div class="progress">${that.stats['failed']}</div>
</div>`

		return str.trim()
	}

	that.getBarYellow = function() {
		if(that.stats['waiting'] === 0)
			return ''
		
		let borderRadiusLeft = that.hasBarToTheLeft('yellow') === true ? 'border-top-left-radius: 0px; border-bottom-left-radius: 0px;' : ''
		let borderRadiusRight = that.hasBarToTheRight('yellow') === true ? 'border-top-right-radius: 0px; border-bottom-right-radius: 0px;' : ''

		let str = `
<div class="yellow bar" style="transition-duration: 300ms; display: block; width: ${that.percentage['waiting']}%; ${borderRadiusRight} ${borderRadiusLeft}">
	<div class="progress">${that.stats['waiting']}</div>
</div>`

		return str.trim()
	}

	that.getBarOrange = function() {
		if(that.stats['blocking'] === 0)
			return ''
		
		let borderRadiusLeft = that.hasBarToTheLeft('orange') === true ? 'border-top-left-radius: 0px; border-bottom-left-radius: 0px;' : ''

		let str = `
<div class="orange bar" style="transition-duration: 300ms; display: block; width: ${that.percentage['blocking']}%; ${borderRadiusLeft}">
	<div class="progress">${that.stats['blocking']}</div>
</div>`

		return str.trim()
	}
	
	return that
}

exports.ProgressBar = ProgressBar
