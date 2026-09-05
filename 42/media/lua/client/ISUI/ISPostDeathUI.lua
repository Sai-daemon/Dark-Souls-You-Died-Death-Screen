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
	local T = DarkSoulsDeathTiming or { showDelay = 3, fadeInDuration = 1, desatTarget = 0.9, blackoutDelay = 4, blackoutDuration = 2 }
	local elapsedMs = getTimestampMs() - self.timeOfDeathMs
	if not self.waitOver then
		self.waitOver = elapsedMs > T.showDelay * 1000.0
		if self.waitOver and not self.musicPlayed then
			self.musicPlayed = true
			getSoundManager():playMusic("PlayerDied")
		end
	end
	if self.waitOver and not self.fadeStart then
		self.fadeStart = getTimestampMs()
	end
	local desatProgress = math.min(1.0, elapsedMs / (T.showDelay * 1000.0))
	local blackoutProgress = 0.0
	if elapsedMs > (T.showDelay + T.blackoutDelay) * 1000.0 then
		blackoutProgress = math.min(1.0, (elapsedMs - (T.showDelay + T.blackoutDelay) * 1000.0) / (T.blackoutDuration * 1000.0))
	end
	self.blackoutProgress = blackoutProgress
	local overlay = getSearchMode():getSearchModeForPlayer(self.playerIndex)
	if overlay then
		overlay:getDesat():setTargets(T.desatTarget * desatProgress, T.desatTarget * desatProgress)
		overlay:getDarkness():setTargets(blackoutProgress, blackoutProgress)
	end
	local allPlayersDead = IsoPlayer.allPlayersDead()
	self.canQuitExit = allPlayersDead
	local allowRespawn = isClient() or (getNumActivePlayers() > 1)
	allowRespawn = getCore():getGameMode() ~= "Tutorial"
	if isClient() and getServerOptions():getBoolean("DropOffWhiteListAfterDeath") then
		allowRespawn = false
	end
	self.canRespawn = allowRespawn
	self.windowVisible = (self.blackoutProgress or 0) >= 1 and not self.showingStats
	ISPanelJoypad.prerender(self)
	self:setStencilRect(self.screenX - self.x, self.screenY - self.y, self.screenWidth, self.screenHeight)
end

function ISPostDeathUI:render()
	local dialogUp = self.quitToDesktopDialog and self.quitToDesktopDialog:isReallyVisible()
	if not dialogUp and self.waitOver then
		local T = DarkSoulsDeathTiming or { fadeInDuration = 1 }
		local fadeIn = 1.0
		if self.fadeStart then
			fadeIn = math.min(1.0, (getTimestampMs() - self.fadeStart) / (T.fadeInDuration * 1000.0))
		end
		if not self.youDiedTexture then
			self.youDiedTexture = getTexture("media/ui/DarkSoulsDeath/you_died.png")
			if not self.youDiedTexture then
				self.youDiedTexture = getTexture("media/textures/DarkSoulsDeath/you_died.png")
			end
		end
		local imgW = self.screenWidth * 0.36
		local imgH = imgW * (1120 / 3794)
		if self.youDiedTexture then
			local tw = self.youDiedTexture:getWidth()
			local th = self.youDiedTexture:getHeight()
			if tw and th and tw > 0 then
				imgH = imgW * (th / tw)
			end
		end
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
		if self.barTexture then
			self:drawTextureScaled(self.barTexture,
				self.screenX - self:getAbsoluteX(), barY,
				self.screenWidth, barH, fadeIn, 1, 1, 1)
		end
		if self.youDiedTexture then
			self:drawTextureScaledAspect(self.youDiedTexture, imgX, imgY, imgW, imgH, fadeIn, 1, 1, 1)
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
	local list = {}
	if self.canRespawn then
		table.insert(list, { label = self.respawnLabel, cb = self.onRespawn, font = UIFont.Medium, hgt = BUTTON_HGT, fh = FONT_HGT_MEDIUM })
	end
	if self.canQuitExit then
		table.insert(list, { label = self.exitLabel, cb = self.onExit, font = UIFont.Medium, hgt = BUTTON_HGT, fh = FONT_HGT_MEDIUM })
		table.insert(list, { label = self.quitLabel, cb = self.onQuitToDesktop, font = UIFont.Medium, hgt = BUTTON_HGT, fh = FONT_HGT_MEDIUM })
	end
	table.insert(list, { label = self.statsLabel, cb = self.onStats, font = UIFont.Large, hgt = FONT_HGT_LARGE + 6, fh = FONT_HGT_LARGE })
	if #list == 0 then
		self.buttonRects = {}
		return
	end
	local buttonWid = UI_BORDER_SPACING * 2
	for _, b in ipairs(list) do
		local w = getTextManager():MeasureStringX(b.font, b.label)
		if w + UI_BORDER_SPACING * 2 > buttonWid then
			buttonWid = w + UI_BORDER_SPACING * 2
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
		self:drawRect(windowX, y, buttonWid, b.hgt, 0.8, 0.0, 0.0, 0.0)
		self:drawRectBorder(windowX, y, buttonWid, b.hgt, 0.3, 0.4, 0.4, 0.4)
		self:drawTextCentre(b.label, windowX + buttonWid / 2, y + (b.hgt - b.fh) / 2, 1.0, 1.0, 1.0, 1.0, b.font)
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
		setGameSpeed(1)
		pauseSoundAndMusic()
		setShowPausedMessage(true)
		getCore():quitToDesktop()
	end
	self.quitToDesktopDialog = nil
end

function ISPostDeathUI:onExit()
	if MainScreen.instance:isReallyVisible() then return end
	setGameSpeed(1)
	self:removeFromUIManager()
	getCore():exitToMenu()
end

function ISPostDeathUI:onRespawn()
	if MainScreen.instance:isReallyVisible() then return end
	setGameSpeed(1)
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
