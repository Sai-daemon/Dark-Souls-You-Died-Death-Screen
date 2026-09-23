if DarkSoulsDeathAudioOnlyLoaded then return end
DarkSoulsDeathAudioOnlyLoaded = true

DarkSoulsDeathAudioTiming = DarkSoulsDeathAudioTiming or {
	muffleStart = 1,
	muffleRampDuration = 2,
	muffleLevel = 0.25,
	showDelay = 3,
	blackoutStart = 7,
	musicRestoreDuration = 2,
}

DarkSoulsDeathAudioVolumes = {}
DarkSoulsDeathAudioPlayerNum = nil
DarkSoulsDeathAudioClickUntil = 0

-- Seconds after the per-sound duck before ambient streams and rain are stopped.
DarkSoulsDeathAudioSilence = DarkSoulsDeathAudioSilence or {
	ambientStreamStopDelay = 0.5,
}
local deathTimeMs = nil
local stingPlayed = false

local function captureBaselines()
	local okMusic, musicVol = pcall(function() return getSoundManager():getMusicVolume() end)
	local okSound, soundVol = pcall(function() return getSoundManager():getSoundVolume() end)
	local okEngine, engineVol = pcall(function() return getSoundManager():getVehicleEngineVolume() end)
	DarkSoulsDeathAudioVolumes.music = okMusic and musicVol or getCore():getOptionMusicVolume() / 10.0
	DarkSoulsDeathAudioVolumes.sound = okSound and soundVol or getCore():getOptionSoundVolume() / 10.0
	DarkSoulsDeathAudioVolumes.vehicleEngine = okEngine and engineVol or getCore():getOptionVehicleEngineVolume() / 10.0
	-- SoundManager:getAmbientVolume() is hardcoded to 1.0, so the option is the only real ambient source.
	DarkSoulsDeathAudioVolumes.ambient = getCore():getOptionAmbientVolume() / 10.0
end

local soundSnapshots = {}
local soundsDucked = false
local duckedAtMs = nil
local advancedSoundWas = nil

-- GameSound:getUserVolume() returns a hardcoded 1.0 unless the advanced sound options system is on.
local function enablePerSoundVolume()
	if advancedSoundWas ~= nil then return end
	local ok, was = pcall(function() return SystemDisabler.getEnableAdvancedSoundOptions() end)
	advancedSoundWas = ok and was and true or false
	pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(true) end)
end

local function restorePerSoundVolume()
	if advancedSoundWas == nil then return end
	local was = advancedSoundWas
	advancedSoundWas = nil
	pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(was) end)
end

-- The player can change the volume options while the death screen is up, so the live options win.
local function refreshBaselines()
	local core = getCore()
	local music = core:getOptionMusicVolume() / 10.0
	local sound = core:getOptionSoundVolume() / 10.0
	local ambient = core:getOptionAmbientVolume() / 10.0
	local engine = core:getOptionVehicleEngineVolume() / 10.0
	if DarkSoulsDeathAudioVolumes.music == music and DarkSoulsDeathAudioVolumes.sound == sound
		and DarkSoulsDeathAudioVolumes.ambient == ambient and DarkSoulsDeathAudioVolumes.vehicleEngine == engine then
		return
	end
	DarkSoulsDeathAudioVolumes.music = music
	DarkSoulsDeathAudioVolumes.sound = sound
	DarkSoulsDeathAudioVolumes.ambient = ambient
	DarkSoulsDeathAudioVolumes.vehicleEngine = engine
end

local function snapshotGameSounds()
	soundSnapshots = {}
	enablePerSoundVolume()
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
							soundSnapshots[name] = { sound = gs, volume = vol }
						end
					end
				end
			end
		end
	end
end

local function duckGameSounds()
	if soundsDucked then return end
	soundsDucked = true
	duckedAtMs = getTimestampMs()
	-- Not 0: a fresh Alarm has volume 0.0, so its "vol != this.volume" guard would skip SetVolume.
	for _, entry in pairs(soundSnapshots) do
		pcall(function() entry.sound:setUserVolume(0.0001) end)
	end
end

local function stopZombieSounds()
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

local function stopAmbient()
	-- am:stop() clears alarmList permanently, so it waits until the duck has reached a sounding alarm.
	local delay = (DarkSoulsDeathAudioSilence.ambientStreamStopDelay or 0) * 1000
	if duckedAtMs and getTimestampMs() >= duckedAtMs + delay then
		local am = getAmbientStreamManager()
		if am then
			am:stop()
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

local function restoreGameSounds()
	for _, entry in pairs(soundSnapshots) do
		pcall(function() entry.sound:setUserVolume(entry.volume) end)
	end
	soundSnapshots = {}
	soundsDucked = false
	duckedAtMs = nil
	restorePerSoundVolume()
end

local function restoreVolumes()
	if DarkSoulsDeathAudioVolumes.music ~= nil then
		pcall(function() getSoundManager():setMusicVolume(DarkSoulsDeathAudioVolumes.music) end)
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathAudioVolumes.sound) end)
		pcall(function() getSoundManager():setAmbientVolume(DarkSoulsDeathAudioVolumes.ambient) end)
		if DarkSoulsDeathAudioVolumes.vehicleEngine ~= nil then
			pcall(function() getSoundManager():setVehicleEngineVolume(DarkSoulsDeathAudioVolumes.vehicleEngine) end)
		end
	end
	restoreGameSounds()
end

DarkSoulsDeathAudioRestore = restoreVolumes

DarkSoulsDeathAudioPlayClick = function()
	pcall(function()
		stopZombieSounds()
		local sm = getSoundManager()
		if DarkSoulsDeathAudioVolumes.sound then
			sm:setSoundVolume(DarkSoulsDeathAudioVolumes.sound)
		end
		DarkSoulsDeathAudioClickUntil = getTimestampMs() + 250
		sm:playUISound("UIActivateButton")
	end)
end

DarkSoulsDeathAudioRespawn = function()
	stopZombieSounds()
	if DarkSoulsDeathAudioVolumes.sound then
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathAudioVolumes.sound) end)
	end
end

local function onPlayerDeath(playerObj)
	getSoundManager():StopMusic()
	captureBaselines()
	snapshotGameSounds()
	deathTimeMs = getTimestampMs()
	stingPlayed = false
	DarkSoulsDeathAudioPlayerNum = playerObj:getPlayerNum()
end

local function onTick()
	if not deathTimeMs then return end
	if DarkSoulsDeathAudioVolumes.music == nil then return end
	refreshBaselines()
	local T = DarkSoulsDeathAudioTiming or { muffleStart = 1, muffleRampDuration = 2, muffleLevel = 0.25, showDelay = 3, blackoutStart = 7, musicRestoreDuration = 2 }
	local elapsedS = (getTimestampMs() - deathTimeMs) / 1000.0
	local sm = getSoundManager()
	local engineVol = DarkSoulsDeathAudioVolumes.vehicleEngine
	if elapsedS >= T.muffleStart and elapsedS < T.blackoutStart then
		local muffleProgress = math.min(1.0, (elapsedS - T.muffleStart) / T.muffleRampDuration)
		local factor = 1.0 - muffleProgress * (1.0 - T.muffleLevel)
		pcall(function() sm:setMusicVolume(DarkSoulsDeathAudioVolumes.music * factor) end)
		pcall(function() sm:setSoundVolume(DarkSoulsDeathAudioVolumes.sound * factor) end)
		pcall(function() sm:setAmbientVolume(DarkSoulsDeathAudioVolumes.ambient * factor) end)
		if engineVol ~= nil then
			pcall(function() sm:setVehicleEngineVolume(engineVol * factor) end)
		end
	elseif elapsedS >= T.blackoutStart then
		duckGameSounds()
		stopZombieSounds()
		stopAmbient()
		pcall(function() sm:setSoundVolume(0.0) end)
		pcall(function() sm:setAmbientVolume(0.0) end)
		pcall(function() sm:setVehicleEngineVolume(0.0) end)
		local restoreProgress = math.min(1.0, (elapsedS - T.blackoutStart) / T.musicRestoreDuration)
		pcall(function() sm:setMusicVolume(DarkSoulsDeathAudioVolumes.music * (T.muffleLevel + (1.0 - T.muffleLevel) * restoreProgress)) end)
	end
	if DarkSoulsDeathAudioClickUntil and getTimestampMs() < DarkSoulsDeathAudioClickUntil and DarkSoulsDeathAudioVolumes.sound then
		pcall(function() sm:setSoundVolume(DarkSoulsDeathAudioVolumes.sound) end)
	end
	if not stingPlayed and elapsedS >= T.showDelay then
		stingPlayed = true
		pcall(function() sm:playUISound("YouDiedSting") end)
	end
end

local function onMainMenuEnter()
	if deathTimeMs then
		restoreVolumes()
		deathTimeMs = nil
		stingPlayed = false
	end
end

local function onPlayerUpdate(player)
	if deathTimeMs and DarkSoulsDeathAudioPlayerNum ~= nil
		and player:getPlayerNum() == DarkSoulsDeathAudioPlayerNum and not player:isDead() then
		restoreVolumes()
		deathTimeMs = nil
		stingPlayed = false
		DarkSoulsDeathAudioPlayerNum = nil
	end
end

Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnTick.Add(onTick)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
