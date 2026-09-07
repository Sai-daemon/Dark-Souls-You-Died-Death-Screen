ISPostDeathUI = ISPanelJoypad:derive("ISPostDeathUI")
ISPostDeathUI.instance = {}

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_MEDIUM + 6

function ISPostDeathUI:createChildren()
	self.respawnLabel = getCore():getGameMode() == "A Really CD DA" and getText("IGUI_PostDeath_Challenge") or getText("IGUI_PostDeath_Respawn")
	self.exitLabel = getText("IGUI_PostDeath_Exit")
	self.quitLabel = getText("IGUI_PostDeath_Quit")
	self.statsLabel = "CHARACTER STATS"
end

function ISPostDeathUI:prerender()
	ISPostDeathUI.instance[self.playerIndex] = self
	if self.screenWidth ~= getPlayerScreenWidth(self.playerIndex) or self.screenHeight ~= getPlayerScreenHeight(self.playerIndex) then
		local x = getPlayerScreenLeft(self.playerIndex)
		local y = getPlayerScreenTop(self.playerIndex)
		local w = getPlayerScreenWidth(self.playerIndex)
		local h = getPlayerScreenHeight(self.playerIndex)
		self.screenX = x
		self.screenY = y
		self.screenWidth = w
		self.screenHeight = h
		self:setX(x)
		self:setY(y)
		self:setWidth(w)
		self:setHeight(h)
	end
	if self.quitToDesktopDialog and self.quitToDesktopDialog:isReallyVisible() then
		self.quitToDesktopDialog:bringToTop()
	else
		self:bringToTop()
	end
	local T = DarkSoulsDeathTiming or { muffleStart = 1, muffleRampDuration = 2, muffleLevel = 0.25, showDelay = 3, barFadeInDuration = 0.4, pngStartScale = 0.9, pngEndScale = 1.05, pngStartAlpha = 0.7, pngEndAlpha = 0.85, pngGrowDuration = 2, pngFadeOutDuration = 1, desatStart = 3, desatDuration = 1, desatTarget = 1.0, blackoutStart = 7, blackoutDuration = 1, windowDelay = 8.5, musicRestoreDuration = 2 }
	local elapsedS = (getTimestampMs() - self.timeOfDeathMs) / 1000.0
	if not self.stingPlayed and elapsedS >= T.showDelay then
		self.stingPlayed = true
		getSoundManager():playUISound("YouDiedSting")
	end
	local desatProgress = 0.0
	if elapsedS > T.desatStart then
		desatProgress = math.min(1.0, (elapsedS - T.desatStart) / T.desatDuration)
	end
	local blackoutProgress = 0.0
	if elapsedS > T.blackoutStart then
		blackoutProgress = math.min(1.0, (elapsedS - T.blackoutStart) / T.blackoutDuration)
	end
	self.blackoutProgress = blackoutProgress
	local overlay = getSearchMode():getSearchModeForPlayer(self.playerIndex)
	if overlay then
		local desatVal = T.desatTarget * desatProgress
		local darkVal = blackoutProgress
		overlay:getDesat():setTargets(desatVal, desatVal)
		pcall(function() overlay:getDesat():setExterior(desatVal) end)
		pcall(function() overlay:getDesat():setInterior(desatVal) end)
		overlay:getDarkness():setTargets(darkVal, darkVal)
		pcall(function() overlay:getDarkness():setExterior(darkVal) end)
		pcall(function() overlay:getDarkness():setInterior(darkVal) end)
	end
	if elapsedS >= T.blackoutStart and DarkSoulsDeathDuckGameSounds then
		DarkSoulsDeathDuckGameSounds()
	end
	if elapsedS >= T.blackoutStart then
		DarkSoulsDeathStopZombiesActive = true
	end
	if not self.respawning and DarkSoulsDeathVolumes and DarkSoulsDeathVolumes.music ~= nil then
		local sm = getSoundManager()
		if elapsedS >= T.muffleStart and elapsedS < T.blackoutStart then
			local muffleProgress = math.min(1.0, (elapsedS - T.muffleStart) / T.muffleRampDuration)
			local factor = 1.0 - muffleProgress * (1.0 - T.muffleLevel)
			pcall(function() sm:setMusicVolume(DarkSoulsDeathVolumes.music * factor) end)
			pcall(function() sm:setSoundVolume(DarkSoulsDeathVolumes.sound * factor) end)
			pcall(function() sm:setAmbientVolume(DarkSoulsDeathVolumes.ambient * factor) end)
		elseif elapsedS >= T.blackoutStart then
			pcall(function() sm:setSoundVolume(0.0) end)
			pcall(function() sm:setAmbientVolume(0.0) end)
			local restoreProgress = math.min(1.0, (elapsedS - T.blackoutStart) / T.musicRestoreDuration)
			pcall(function() sm:setMusicVolume(DarkSoulsDeathVolumes.music * (T.muffleLevel + (1.0 - T.muffleLevel) * restoreProgress)) end)
		end
	end
	if self.clickUntil and getTimestampMs() < self.clickUntil and DarkSoulsDeathVolumes and DarkSoulsDeathVolumes.sound then
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathVolumes.sound) end)
	end
	local allPlayersDead = IsoPlayer.allPlayersDead()
	self.canQuitExit = allPlayersDead
	local allowRespawn = isClient() or (getNumActivePlayers() > 1)
	allowRespawn = getCore():getGameMode() ~= "Tutorial"
	if isClient() and getServerOptions():getBoolean("DropOffWhiteListAfterDeath") then
		allowRespawn = false
	end
	self.canRespawn = allowRespawn
	self.windowVisible = elapsedS >= T.windowDelay and not self.showingStats
	local hoverIdx = nil
	if self.windowVisible and not self.showingStats then
		hoverIdx = self:buttonAt(self:getMouseX(), self:getMouseY())
	end
	self.hoveredIndex = hoverIdx
	local dt = (UIManager.getMillisSinceLastRender() or 33) / 1000.0
	local speed = dt / 0.15
	if hoverIdx then
		self.hoverFade = math.min(1, (self.hoverFade or 0) + speed)
	else
		self.hoverFade = math.max(0, (self.hoverFade or 0) - speed)
	end
	ISPanelJoypad.prerender(self)
	self:setStencilRect(self.screenX - self.x, self.screenY - self.y, self.screenWidth, self.screenHeight)
end

function ISPostDeathUI:render()
	local dialogUp = self.quitToDesktopDialog and self.quitToDesktopDialog:isReallyVisible()
	if not dialogUp then
		local T = DarkSoulsDeathTiming or { showDelay = 3, barFadeInDuration = 0.4, pngStartScale = 0.9, pngEndScale = 1.05, pngStartAlpha = 0.8, pngEndAlpha = 0.9, pngGrowDuration = 2, pngFadeOutDuration = 1 }
		local elapsedS = (getTimestampMs() - self.timeOfDeathMs) / 1000.0
		if elapsedS >= T.showDelay then
			if not self.youDiedTexture then
				self.youDiedTexture = getTexture("media/ui/DarkSoulsDeath/you_died.png")
				if not self.youDiedTexture then
					self.youDiedTexture = getTexture("media/textures/DarkSoulsDeath/you_died.png")
				end
			end
			local growT = math.min(1.0, (elapsedS - T.showDelay) / T.pngGrowDuration)
			local scale = T.pngStartScale + (T.pngEndScale - T.pngStartScale) * growT
			local pngAlpha = T.pngStartAlpha + (T.pngEndAlpha - T.pngStartAlpha) * growT
			if elapsedS > T.showDelay + T.pngGrowDuration then
				local fadeT = math.min(1.0, (elapsedS - (T.showDelay + T.pngGrowDuration)) / T.pngFadeOutDuration)
				pngAlpha = T.pngEndAlpha * (1.0 - fadeT)
			end
			local barAlpha = 0.0
			if elapsedS < T.showDelay + T.barFadeInDuration then
				barAlpha = math.min(1.0, (elapsedS - T.showDelay) / T.barFadeInDuration)
			else
				barAlpha = 1.0
			end
			if elapsedS > T.showDelay + T.pngGrowDuration then
				local fadeT = math.min(1.0, (elapsedS - (T.showDelay + T.pngGrowDuration)) / T.pngFadeOutDuration)
				barAlpha = 1.0 * (1.0 - fadeT)
			end
			if self.youDiedTexture and (pngAlpha > 0 or barAlpha > 0) then
				local baseW = self.screenWidth * 0.36
				local tw = self.youDiedTexture:getWidth()
				local th = self.youDiedTexture:getHeight()
				local aspect = (tw and th and tw > 0) and (th / tw) or (1120 / 3794)
				local imgW = baseW * scale
				local imgH = imgW * aspect
				local imgX = self.screenX + (self.screenWidth - imgW) / 2 - self:getAbsoluteX()
				local imgY = self.screenY + (self.screenHeight - imgH) / 2 - self:getAbsoluteY()
				local fadeH = imgH * 0.6
				local barH = imgH + fadeH * 2
				local barY = imgY - fadeH
				if not self.barTexture then
					self.barTexture = getTexture("media/ui/DarkSoulsDeath/bar.png")
					if not self.barTexture then
						self.barTexture = getTexture("media/textures/DarkSoulsDeath/bar.png")
					end
				end
				if self.barTexture and barAlpha > 0 then
					self:drawTextureScaled(self.barTexture,
						self.screenX - self:getAbsoluteX(), barY,
						self.screenWidth, barH, barAlpha, 1, 1, 1)
				end
				if pngAlpha > 0 then
					self:drawTextureScaledAspect(self.youDiedTexture, imgX, imgY, imgW, imgH, pngAlpha, 1, 1, 1)
				end
			end
		end
	end
	if (self.blackoutProgress or 0) > 0 then
		self:drawRect(self.screenX - self:getAbsoluteX(), self.screenY - self:getAbsoluteY(), self.screenWidth, self.screenHeight, self.blackoutProgress, 0, 0, 0)
	end
	if not dialogUp then
		if self.showingStats then
			self:drawStats()
		elseif self.windowVisible then
			self:drawWindow()
		end
	end
	self:clearStencilRect()
end

function ISPostDeathUI:drawStats()
	local statLines = {}
	for i = 2, #self.lines do
		statLines[#statLines + 1] = self.lines[i]
	end
	if #statLines == 0 then return end
	local lineH = FONT_HGT_LARGE + 2
	local totalH = #statLines * lineH
	local startY = self.screenY + (self.screenHeight - totalH) / 2 - self:getAbsoluteY()
	for i = 1, #statLines do
		local text = statLines[i]
		local width = getTextManager():MeasureStringX(UIFont.Large, text)
		local y = startY + (i - 1) * lineH
		self:drawRect(self.screenX + (self.screenWidth - width) / 2 - 15 - self:getAbsoluteX(), y - 5, width + 30, FONT_HGT_LARGE + 10, 0.85, 0.0, 0.0, 0.0)
		self:drawTextCentre(text, self.screenX + self.screenWidth / 2 - self:getAbsoluteX(), y, 1.0, 1.0, 1.0, 1.0, UIFont.Large)
	end
end

function ISPostDeathUI:drawWindow()
	local joypadActive = JoypadState.players[self.playerIndex+1] ~= nil
	local list = {}
	if self.canRespawn then
		table.insert(list, { label = self.respawnLabel, cb = self.onRespawn, font = UIFont.Medium, hgt = BUTTON_HGT, fh = FONT_HGT_MEDIUM, joy = joypadActive and Joypad.Texture.AButton or nil })
	end
	if self.canQuitExit then
		table.insert(list, { label = self.exitLabel, cb = self.onExit, font = UIFont.Medium, hgt = BUTTON_HGT, fh = FONT_HGT_MEDIUM, joy = joypadActive and Joypad.Texture.XButton or nil })
		table.insert(list, { label = self.quitLabel, cb = self.onQuitToDesktop, font = UIFont.Medium, hgt = BUTTON_HGT, fh = FONT_HGT_MEDIUM, joy = joypadActive and Joypad.Texture.BButton or nil })
	end
	table.insert(list, { label = self.statsLabel, cb = self.onStats, font = UIFont.Large, hgt = FONT_HGT_LARGE + 6, fh = FONT_HGT_LARGE, joy = joypadActive and Joypad.Texture.YButton or nil })
	if #list == 0 then
		self.buttonRects = {}
		return
	end
	local joyW = FONT_HGT_MEDIUM
	local buttonWid = UI_BORDER_SPACING * 2
	for _, b in ipairs(list) do
		local w = getTextManager():MeasureStringX(b.font, b.label)
		local need = w + UI_BORDER_SPACING * 2
		if b.joy then
			need = need + joyW + 6
		end
		if need > buttonWid then
			buttonWid = need
		end
	end
	local totalH = 0
	for _, b in ipairs(list) do
		totalH = totalH + b.hgt
	end
	totalH = totalH + (#list - 1) * UI_BORDER_SPACING
	local windowX = (self.screenWidth - buttonWid) / 2
	local windowY = (self.screenHeight - totalH) / 2
	self:drawRect(windowX - 10, windowY - 10, buttonWid + 20, totalH + 20, 0.6, 0.0, 0.0, 0.0)
	self.buttonRects = {}
	local y = windowY
	for i, b in ipairs(list) do
		local hover = (i == self.hoveredIndex) and (self.hoverFade or 0) or 0
		self:drawRect(windowX, y, buttonWid, b.hgt, 0.8 + 0.2 * hover, 0.3 * hover, 0.3 * hover, 0.3 * hover)
		self:drawRectBorder(windowX, y, buttonWid, b.hgt, 0.3, 0.4, 0.4, 0.4)
		local textW = getTextManager():MeasureStringX(b.font, b.label)
		local textX = windowX + (buttonWid - textW) / 2
		if b.joy then
			local joyH = math.min(joyW, b.hgt - 6)
			self:drawTextureScaled(b.joy, windowX + 6, y + (b.hgt - joyH) / 2, joyH, joyH, 1, 1, 1, 1)
			textX = windowX + 6 + joyH + 6 + (buttonWid - 6 - joyH - 6 - textW) / 2
		end
		self:drawText(b.label, textX, y + (b.hgt - b.fh) / 2, 1.0, 1.0, 1.0, 1.0, b.font)
		table.insert(self.buttonRects, { x = windowX, y = y, w = buttonWid, h = b.hgt, cb = b.cb })
		y = y + b.hgt + UI_BORDER_SPACING
	end
end

function ISPostDeathUI:buttonAt(mx, my)
	if not self.buttonRects then return nil end
	for i, b in ipairs(self.buttonRects) do
		if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
			return i
		end
	end
	return nil
end

function ISPostDeathUI:onStats()
	self.showingStats = true
end

function ISPostDeathUI:hideStats()
	self.showingStats = false
end

function ISPostDeathUI:restoreVolumes()
	if DarkSoulsDeathVolumes and DarkSoulsDeathVolumes.music then
		getSoundManager():setMusicVolume(DarkSoulsDeathVolumes.music)
		getSoundManager():setSoundVolume(DarkSoulsDeathVolumes.sound)
		getSoundManager():setAmbientVolume(DarkSoulsDeathVolumes.ambient)
	end
	if DarkSoulsDeathRestoreGameSounds then
		DarkSoulsDeathRestoreGameSounds()
	end
	DarkSoulsDeathStopZombiesActive = false
end

function ISPostDeathUI:playClick()
	pcall(function()
		if DarkSoulsDeathStopZombieSounds then
			DarkSoulsDeathStopZombieSounds()
		end
		local sm = getSoundManager()
		if DarkSoulsDeathVolumes and DarkSoulsDeathVolumes.sound then
			sm:setSoundVolume(DarkSoulsDeathVolumes.sound)
		end
		self.clickUntil = getTimestampMs() + 250
		sm:playUISound("UIActivateButton")
	end)
end

function ISPostDeathUI:removeFromUIManager()
	self:restoreVolumes()
	ISUIElement.removeFromUIManager(self)
end

function ISPostDeathUI:setVisible(visible)
	ISUIElement.setVisible(self, visible)
	if visible and self.respawning then
		self.respawning = false
	end
end

function ISPostDeathUI:onQuitToDesktop()
	if MainScreen.instance:isReallyVisible() then return end
	if self.quitToDesktopDialog then
		self.quitToDesktopDialog:destroy()
	end
	local player = 0
	local width = 380;
	local x = getPlayerScreenLeft(player) + (getPlayerScreenWidth(player) - width) / 2
	local height = 120;
	local y = getPlayerScreenTop(player) + (getPlayerScreenHeight(player) - height) / 2
	local modal = ISModalDialog:new(x,y, width, height, getText("IGUI_ConfirmQuitToDesktop"), true, self, ISPostDeathUI.onConfirmQuitToDesktop, player);
	modal:initialise()
	self.quitToDesktopDialog = modal
	modal:addToUIManager()
	modal:setAlwaysOnTop(true)
	modal:bringToTop()
	if JoypadState.players[player+1] then
		modal.prevFocus = JoypadState.players[player+1].focus
		setJoypadFocus(player, modal)
	end
end

function ISPostDeathUI:onConfirmQuitToDesktop(button)
	if button.internal == "YES" then
		self:restoreVolumes()
		setGameSpeed(1)
		pauseSoundAndMusic()
		setShowPausedMessage(true)
		getCore():quitToDesktop()
	end
	self.quitToDesktopDialog = nil
end

function ISPostDeathUI:onExit()
	if MainScreen.instance:isReallyVisible() then return end
	self:restoreVolumes()
	setGameSpeed(1)
	self:removeFromUIManager()
	getCore():exitToMenu()
end

function ISPostDeathUI:onRespawn()
	if MainScreen.instance:isReallyVisible() then return end
	setGameSpeed(1)
	if DarkSoulsDeathStopZombieSounds then
		DarkSoulsDeathStopZombieSounds()
	end
	if DarkSoulsDeathVolumes and DarkSoulsDeathVolumes.sound then
		pcall(function() getSoundManager():setSoundVolume(DarkSoulsDeathVolumes.sound) end)
	end
	self.respawning = true
	self:setVisible(false)
	local joypadData = JoypadState.players[self.playerIndex+1]
	if joypadData then
		CoopCharacterCreation.newPlayer(joypadData.id, joypadData)
	else
		CoopCharacterCreation:newPlayerMouse()
	end
end

function ISPostDeathUI:onMouseDown(x, y)
	if self.quitToDesktopDialog and self.quitToDesktopDialog:isReallyVisible() then
		self.clickedIndex = nil
		return false
	end
	if not self.windowVisible then
		self.clickedIndex = nil
		return false
	end
	self.clickedIndex = self:buttonAt(self:getMouseX(), self:getMouseY())
	if self.clickedIndex then
		return true
	end
	return false
end

function ISPostDeathUI:onMouseUp(x, y)
	if self.quitToDesktopDialog and self.quitToDesktopDialog:isReallyVisible() then
		self.clickedIndex = nil
		return false
	end
	if not self.windowVisible then
		self.clickedIndex = nil
		return false
	end
	local idx = self.clickedIndex
	self.clickedIndex = nil
	if idx then
		if self:buttonAt(self:getMouseX(), self:getMouseY()) == idx then
			local b = self.buttonRects[idx]
			if b and b.cb then
				self:playClick()
				b.cb(self)
				return true
			end
		end
	end
	return false
end

function ISPostDeathUI:onMouseMove(dx, dy)
	return false
end

function ISPostDeathUI:onMouseWheel(del)
	return false
end

function ISPostDeathUI:onGainJoypadFocus(joypadData)
end

function ISPostDeathUI:onJoypadDown(button, joypadData)
	if self.showingStats then
		self:playClick()
		self:hideStats()
		return true
	end
	if not self.windowVisible then
		return false
	end
	if button == Joypad.AButton and self.canRespawn then
		self:playClick()
		self:onRespawn()
		return true
	elseif button == Joypad.XButton and self.canQuitExit then
		self:playClick()
		self:onExit()
		return true
	elseif button == Joypad.BButton and self.canQuitExit then
		self:playClick()
		self:onQuitToDesktop()
		return true
	elseif button == Joypad.YButton then
		self:playClick()
		self:onStats()
		return true
	end
	return false
end

function ISPostDeathUI:onJoypadBeforeDeactivate(joypadData)
end

function ISPostDeathUI:onJoypadReactivate(joypadData)
end

function ISPostDeathUI:new(playerIndex)
	local x = getPlayerScreenLeft(playerIndex)
	local y = getPlayerScreenTop(playerIndex)
	local w = getPlayerScreenWidth(playerIndex)
	local h = getPlayerScreenHeight(playerIndex)
	local o = ISPanelJoypad:new(x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o:setAnchorLeft(false)
	o:setAnchorTop(false)
	o.background = false
	o.screenX = x
	o.screenY = y
	o.screenWidth = w
	o.screenHeight = h
	o.playerIndex = playerIndex
	o:instantiate()
	o:setAlwaysOnTop(true)
	o.javaObject:setIgnoreLossControl(true)
	ISPostDeathUI.instance[playerIndex] = o
	return o
end

function ISPostDeathUI.OnPlayerDeath(playerObj)
	local playerNum = playerObj:getPlayerNum()
	local panel = ISPostDeathUI:new(playerNum)
	panel.timeOfDeath = getTimestamp()
	panel.timeOfDeathMs = getTimestampMs()
	panel.lines = {}
	table.insert(panel.lines, "YOU DIED")
	local s = getGameTime():getDeathString(playerObj)
	if s then
		table.insert(panel.lines, s)
	end
	s = getGameTime():getZombieKilledText(playerObj)
	if s then
		table.insert(panel.lines, s)
	end
	s = getGameTime():getGameModeText()
	if s then
		table.insert(panel.lines, s)
	end
	panel:addToUIManager()
	if MainScreen.instance:isVisible() then
		table.insert(ISUIHandler.visibleUI, panel.javaObject:toString())
		panel:setVisible(false)
		if JoypadState.players[playerNum+1] and JoypadState.saveFocus then
			JoypadState.saveFocus[playerNum+1] = panel
		end
	else
		if JoypadState.players[playerNum+1] then
			JoypadState.players[playerNum+1].focus = panel
		end
	end
end

Events.OnPlayerDeath.Add(ISPostDeathUI.OnPlayerDeath)

Events.OnKeyPressed.Add(function(key)
	for _, panel in pairs(ISPostDeathUI.instance) do
		if panel.showingStats then
			panel:hideStats()
		end
	end
end)
