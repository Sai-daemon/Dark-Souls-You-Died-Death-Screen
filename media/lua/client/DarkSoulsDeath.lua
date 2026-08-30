local function onPlayerDeath(playerObj)
	getSoundManager():StopMusic()
end

Events.OnPlayerDeath.Add(onPlayerDeath)
