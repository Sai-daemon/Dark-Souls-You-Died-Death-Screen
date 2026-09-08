DarkSoulsDeathTiming = DarkSoulsDeathTiming or {
	muffleStart = 1,
	muffleRampDuration = 2,
	muffleLevel = 0.25,
	showDelay = 3,
	barFadeInDuration = 0.4,
	pngStartScale = 0.9,
	pngEndScale = 1.05,
	pngStartAlpha = 0.7,
	pngEndAlpha = 0.85,
	pngGrowDuration = 2,
	pngHoldDuration = 0.3,
	pngFadeOutDuration = 1,
	desatStart = 3,
	desatDuration = 1,
	desatTarget = 1.0,
	blackoutStart = 7,
	blackoutDuration = 1,
	windowDelay = 8.5,
	musicRestoreDuration = 2,
}

DarkSoulsDeathVolumes = {}
DarkSoulsDeathPlayerNum = nil
DarkSoulsDeathSoundSnapshots = {}
DarkSoulsDeathSoundsDucked = false
DarkSoulsDeathStopZombiesActive = false

local function snapshotGameSounds()
	DarkSoulsDeathSoundSnapshots = {}
	local ok, cats = pcall(function() return GameSounds.getCategories() end)
	if not ok or not cats then return end
	for i = 0, cats:size() - 1 do
		local catOk, cat = pcall(function() return cats:get(i) end)
		if catOk and cat and cat ~= "UI" and cat ~= "Music" then
			local sOk, sounds = pcall(function() return GameSounds.getSoundsInCategory(cat) end)
			if sOk and sounds then
				for j = 0, sounds:size() - 1 do
					local gsOk, gs = pcall(function() return sounds:get(j) end)
					if gsOk and gs then
						local nOk, name = pcall(function() return gs:getName() end)
						local vOk, vol = pcall(function() return gs:getUserVolume() end)
						if nOk and name and vOk then
							DarkSoulsDeathSoundSnapshots[name] = { sound = gs, volume = vol }
						end
					end
				end
			end
		end
	end
end

DarkSoulsDeathDuckGameSounds = function()
	if DarkSoulsDeathSoundsDucked then return end
	DarkSoulsDeathSoundsDucked = true
	for _, entry in pairs(DarkSoulsDeathSoundSnapshots) do
		pcall(function() entry.sound:setUserVolume(0.0) end)
	end
end

DarkSoulsDeathRestoreGameSounds = function()
	for _, entry in pairs(DarkSoulsDeathSoundSnapshots) do
		pcall(function() entry.sound:setUserVolume(entry.volume) end)
	end
	DarkSoulsDeathSoundSnapshots = {}
	DarkSoulsDeathSoundsDucked = false
end

DarkSoulsDeathStopZombieSounds = function()
	local cell = getCell()
	if not cell then return end
	local list = cell:getObjectListForLua()
	if not list then return end
	for i = 0, list:size() - 1 do
		local obj = list:get(i)
		if obj and instanceof(obj, "IsoZombie") then
			local em = obj:getEmitter()
			if em then
				em:stopAll()
			end
		end
	end
end

DarkSoulsDeathStopAmbient = function()
	local am = getAmbientStreamManager()
	if am then
		am:stop()
	end
	local pieces = getSoundManager():getAmbientPieces()
	if not pieces then return end
	for i = 0, pieces:size() - 1 do
		local p = pieces:get(i)
		if p then
			p:stop()
		end
	end
end

DarkSoulsDeathRestoreAll = function()
	if DarkSoulsDeathVolumes.music ~= nil then
		pcall(function() getSoundManager():setMusicVolume(DarkSoulsDeathVolumes.music) end)
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathVolumes.sound) end)
		pcall(function() getSoundManager():setAmbientVolume(DarkSoulsDeathVolumes.ambient) end)
	end
	DarkSoulsDeathRestoreGameSounds()
	DarkSoulsDeathStopZombiesActive = false
end

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

	local okMusic, musicVol = pcall(function() return getSoundManager():getMusicVolume() end)
	local okSound, soundVol = pcall(function() return getSoundManager():getSoundVolume() end)
	local okAmbient, ambientVol = pcall(function() return getSoundManager():getAmbientVolume() end)
	DarkSoulsDeathVolumes.music = okMusic and musicVol or getCore():getOptionMusicVolume()
	DarkSoulsDeathVolumes.sound = okSound and soundVol or getCore():getOptionSoundVolume()
	DarkSoulsDeathVolumes.ambient = okAmbient and ambientVol or getCore():getOptionAmbientVolume()
	DarkSoulsDeathPlayerNum = playerNum
	snapshotGameSounds()
end

Events.OnPlayerDeath.Add(onPlayerDeath)

Events.OnTick.Add(function()
	if DarkSoulsDeathStopZombiesActive then
		DarkSoulsDeathStopZombieSounds()
		DarkSoulsDeathStopAmbient()
	end
end)

Events.OnPlayerUpdate.Add(function(player)
	if DarkSoulsDeathPlayerNum ~= nil and DarkSoulsDeathVolumes.music ~= nil
		and player:getPlayerNum() == DarkSoulsDeathPlayerNum and not player:isDead() then
		DarkSoulsDeathPlayerNum = nil
		DarkSoulsDeathRestoreAll()
	end
end)
