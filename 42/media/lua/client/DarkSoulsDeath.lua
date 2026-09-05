DarkSoulsDeathTiming = DarkSoulsDeathTiming or {
	showDelay = 3,
	fadeInDuration = 1,
	desatTarget = 0.9,
	blackoutDelay = 4,
	blackoutDuration = 2,
}

local function onPlayerDeath(playerObj)
	getSoundManager():StopMusic()
	local playerNum = playerObj:getPlayerNum()
	getSearchMode():setEnabled(playerNum, true)
	local overlay = getSearchMode():getSearchModeForPlayer(playerNum)
	overlay:getDesat():setTargets(0.0, 0.0)
	overlay:getBlur():setTargets(0.0, 0.0)
	overlay:getDarkness():setTargets(0.0, 0.0)
	overlay:getRadius():setTargets(0.0, 0.0)
	overlay:getGradientWidth():setTargets(0.0, 0.0)
end

Events.OnPlayerDeath.Add(onPlayerDeath)
