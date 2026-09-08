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
local deathTimeMs = nil
local stingPlayed = false

local function captureBaselines()
	local okMusic, musicVol = pcall(function() return getSoundManager():getMusicVolume() end)
	local okSound, soundVol = pcall(function() return getSoundManager():getSoundVolume() end)
	local okAmbient, ambientVol = pcall(function() return getSoundManager():getAmbientVolume() end)
	DarkSoulsDeathAudioVolumes.music = okMusic and musicVol or getCore():getOptionMusicVolume()
	DarkSoulsDeathAudioVolumes.sound = okSound and soundVol or getCore():getOptionSoundVolume()
	DarkSoulsDeathAudioVolumes.ambient = okAmbient and ambientVol or getCore():getOptionAmbientVolume()
end

local soundSnapshots = {}
local soundsDucked = false

local function snapshotGameSounds()
	soundSnapshots = {}
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
	for _, entry in pairs(soundSnapshots) do
		pcall(function() entry.sound:setUserVolume(0.0) end)
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

local function restoreGameSounds()
	for _, entry in pairs(soundSnapshots) do
		pcall(function() entry.sound:setUserVolume(entry.volume) end)
	end
	soundSnapshots = {}
	soundsDucked = false
end

local function restoreVolumes()
	if DarkSoulsDeathAudioVolumes.music ~= nil then
		pcall(function() getSoundManager():setMusicVolume(DarkSoulsDeathAudioVolumes.music) end)
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathAudioVolumes.sound) end)
		pcall(function() getSoundManager():setAmbientVolume(DarkSoulsDeathAudioVolumes.ambient) end)
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
	local T = DarkSoulsDeathAudioTiming or { muffleStart = 1, muffleRampDuration = 2, muffleLevel = 0.25, showDelay = 3, blackoutStart = 7, musicRestoreDuration = 2 }
	local elapsedS = (getTimestampMs() - deathTimeMs) / 1000.0
	local sm = getSoundManager()
	if elapsedS >= T.muffleStart and elapsedS < T.blackoutStart then
		local muffleProgress = math.min(1.0, (elapsedS - T.muffleStart) / T.muffleRampDuration)
		local factor = 1.0 - muffleProgress * (1.0 - T.muffleLevel)
		pcall(function() sm:setMusicVolume(DarkSoulsDeathAudioVolumes.music * factor) end)
		pcall(function() sm:setSoundVolume(DarkSoulsDeathAudioVolumes.sound * factor) end)
		pcall(function() sm:setAmbientVolume(DarkSoulsDeathAudioVolumes.ambient * factor) end)
	elseif elapsedS >= T.blackoutStart then
		duckGameSounds()
		stopZombieSounds()
		stopAmbient()
		pcall(function() sm:setSoundVolume(0.0) end)
		pcall(function() sm:setAmbientVolume(0.0) end)
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
