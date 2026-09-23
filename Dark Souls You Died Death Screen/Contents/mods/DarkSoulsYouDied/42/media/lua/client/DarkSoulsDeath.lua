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

-- Tunables for the extra audio treatment; every other value here is fixed behaviour.
DarkSoulsDeathSilence = DarkSoulsDeathSilence or {
	duckTo = 0.0001,              -- not 0: a fresh Alarm has volume 0.0, so "vol != this.volume" would skip SetVolume
	ambientStreamStopDelay = 0.5, -- seconds after the duck before ambient streams and rain are stopped
	extraSounds = { "HouseAlarm", "Fire", "Generator", "GeneratorLoop" }, -- ducked by name, on top of every category
}

DarkSoulsDeathDuckedAtMs = nil
DarkSoulsDeathAdvancedSoundWas = nil

-- GameSound:getUserVolume() returns a hardcoded 1.0 unless the advanced sound options system is on,
-- so the per-sound duck only reaches the engine while that flag is enabled.
DarkSoulsDeathEnablePerSoundVolume = function()
	if DarkSoulsDeathAdvancedSoundWas ~= nil then return end
	local ok, was = pcall(function() return SystemDisabler.getEnableAdvancedSoundOptions() end)
	DarkSoulsDeathAdvancedSoundWas = ok and was and true or false
	pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(true) end)
end

DarkSoulsDeathRestorePerSoundVolume = function()
	if DarkSoulsDeathAdvancedSoundWas == nil then return end
	local was = DarkSoulsDeathAdvancedSoundWas
	DarkSoulsDeathAdvancedSoundWas = nil
	pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(was) end)
end

-- The player can change the volume options while the death screen is up, so the live options win.
DarkSoulsDeathRefreshVolumes = function()
	local core = getCore()
	local music = core:getOptionMusicVolume() / 10.0
	local sound = core:getOptionSoundVolume() / 10.0
	local ambient = core:getOptionAmbientVolume() / 10.0
	local engine = core:getOptionVehicleEngineVolume() / 10.0
	if DarkSoulsDeathVolumes.music == music and DarkSoulsDeathVolumes.sound == sound
		and DarkSoulsDeathVolumes.ambient == ambient and DarkSoulsDeathVolumes.vehicleEngine == engine then
		return
	end
	DarkSoulsDeathVolumes.music = music
	DarkSoulsDeathVolumes.sound = sound
	DarkSoulsDeathVolumes.ambient = ambient
	DarkSoulsDeathVolumes.vehicleEngine = engine
end

local function snapshotGameSounds()
	DarkSoulsDeathSoundSnapshots = {}
	DarkSoulsDeathEnablePerSoundVolume()
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
	-- Named stragglers the category walk misses; getSound returns nil for unknown names.
	local extras = DarkSoulsDeathSilence.extraSounds
	if extras then
		for _, name in ipairs(extras) do
			local gs = GameSounds.getSound(name)
			if gs and not DarkSoulsDeathSoundSnapshots[name] then
				DarkSoulsDeathSoundSnapshots[name] = { sound = gs, volume = gs:getUserVolume() }
			end
		end
	end
end

DarkSoulsDeathDuckGameSounds = function()
	if DarkSoulsDeathSoundsDucked then return end
	DarkSoulsDeathSoundsDucked = true
	DarkSoulsDeathDuckedAtMs = getTimestampMs()
	local duckTo = DarkSoulsDeathSilence.duckTo or 0.0001
	for _, entry in pairs(DarkSoulsDeathSoundSnapshots) do
		pcall(function() entry.sound:setUserVolume(duckTo) end)
	end
end

DarkSoulsDeathRestoreGameSounds = function()
	for _, entry in pairs(DarkSoulsDeathSoundSnapshots) do
		pcall(function() entry.sound:setUserVolume(entry.volume) end)
	end
	DarkSoulsDeathSoundSnapshots = {}
	DarkSoulsDeathSoundsDucked = false
	DarkSoulsDeathDuckedAtMs = nil
	DarkSoulsDeathRestorePerSoundVolume()
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
	-- am:stop() clears alarmList permanently, so it waits until the duck has reached a sounding alarm.
	if DarkSoulsDeathDuckedAtMs then
		local delay = (DarkSoulsDeathSilence.ambientStreamStopDelay or 0) * 1000
		if getTimestampMs() >= DarkSoulsDeathDuckedAtMs + delay then
			local am = getAmbientStreamManager()
			if am then
				am:stop()
			end
		end
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

-- Engine loops read a static volume constant and ignore per-sound volumes, so the VCA is the only lever.
DarkSoulsDeathStopWorldSounds = function()
	pcall(function() getSoundManager():setVehicleEngineVolume(0.0) end)
end

DarkSoulsDeathRestoreAll = function()
	if DarkSoulsDeathVolumes.music ~= nil then
		pcall(function() getSoundManager():setMusicVolume(DarkSoulsDeathVolumes.music) end)
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathVolumes.sound) end)
		pcall(function() getSoundManager():setAmbientVolume(DarkSoulsDeathVolumes.ambient) end)
		if DarkSoulsDeathVolumes.vehicleEngine ~= nil then
			pcall(function() getSoundManager():setVehicleEngineVolume(DarkSoulsDeathVolumes.vehicleEngine) end)
		end
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
	local okEngine, engineVol = pcall(function() return getSoundManager():getVehicleEngineVolume() end)
	DarkSoulsDeathVolumes.music = okMusic and musicVol or getCore():getOptionMusicVolume() / 10.0
	DarkSoulsDeathVolumes.sound = okSound and soundVol or getCore():getOptionSoundVolume() / 10.0
	DarkSoulsDeathVolumes.vehicleEngine = okEngine and engineVol or getCore():getOptionVehicleEngineVolume() / 10.0
	-- SoundManager:getAmbientVolume() is hardcoded to 1.0, so the option is the only real ambient source.
	DarkSoulsDeathVolumes.ambient = getCore():getOptionAmbientVolume() / 10.0
	DarkSoulsDeathPlayerNum = playerNum
	snapshotGameSounds()
end

Events.OnPlayerDeath.Add(onPlayerDeath)

Events.OnTick.Add(function()
	if DarkSoulsDeathPlayerNum ~= nil then
		DarkSoulsDeathRefreshVolumes()
	end
	if DarkSoulsDeathStopZombiesActive then
		DarkSoulsDeathStopZombieSounds()
		DarkSoulsDeathStopAmbient()
		DarkSoulsDeathStopWorldSounds()
	end
end)

Events.OnPlayerUpdate.Add(function(player)
	if DarkSoulsDeathPlayerNum ~= nil and DarkSoulsDeathVolumes.music ~= nil
		and player:getPlayerNum() == DarkSoulsDeathPlayerNum and not player:isDead() then
		DarkSoulsDeathPlayerNum = nil
		DarkSoulsDeathRestoreAll()
	end
end)
