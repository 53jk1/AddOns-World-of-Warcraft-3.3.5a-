--[[
	Kui Nameplates
	Kesava-Auchindoun
	As part of Kui
	
	TODO try to use default cast bar
	TODO add options to change the cast bar's uninterruptible glow/bar colour
]]

local addon, ns = ...
local np, loadedGUIDs, loadedNames, targetExists
	= ns.np, {}, {}
	
-- Custom reaction colours
np.r = {
    { .7, .2, .1 },		-- hated
    { 1, .8, 0 },		-- neutral
    { .2, .6, .1 },		-- friendly
}

-- combat log events to listen to for cast warnings/healing
local castEvents = {
	['SPELL_CAST_START'] = true,
	['SPELL_CAST_SUCCESS'] = true,
	['SPELL_INTERRUPT'] = true,
	['SPELL_HEAL'] = true,
	['SPELL_PERIODIC_HEAL'] = true
}

------------------------------------------------------------- Frame functions --
-- set colour of health bar according to reaction/threat
local function SetHealthColour(self)
	if self.hasThreat then
		self.health.reset = true
		self.health:SetStatusBarColor(unpack(np.kui:getSaved('tank', 'barcolour')))
		return
	end
	
	local r, g, b = self.oldHealth:GetStatusBarColor()
	if	self.health.reset  or
		r ~= self.health.r or
		g ~= self.health.g or
		b ~= self.health.b
	then
		-- store the default colour
		self.health.r, self.health.g, self.health.b = r, g, b
		self.health.reset, self.friend = nil, nil
		
		if g > .9 and r == 0 and b == 0 then
			-- friendly NPC
			self.friend = true
			r, g, b = unpack(np.r[3])
		elseif b > .9 and r == 0 and g == 0 then
			-- friendly player
			self.friend = true
			r, g, b = 0, .3, .6
		elseif r > .9 and g == 0 and b == 0 then
			-- enemy NPC
			r, g, b = unpack(np.r[1])
		elseif (r + g) > 1.8 and b == 0 then
			-- neutral NPC
			r, g, b = unpack(np.r[2])
		end
			-- enemy player, use default UI colour
		
		self.health:SetStatusBarColor(r, g, b)
	end
end

local function SetGlowColour(self, r, g, b, a)
	if not r then
		-- set default colour
		r, g, b = 0, 0, 0
	end

	if not a then
		a = .85
	end
	
    self.bg:SetVertexColor(r, g, b, a)
end

local function SetCastWarning(self, spellName, spellSchool)
	self.castWarning.ag:Stop()

	if	spellName == nil then
		-- hide the warning instantly when interrupted
		self.castWarning:SetAlpha(0)
	else
		local col = COMBATLOG_DEFAULT_COLORS.schoolColoring[spellSchool] or
			{r = 1, g = 1, b = 1}
	
		self.castWarning:SetText(spellName)
		self.castWarning:SetTextColor(col.r, col.g, col.b)
		self.castWarning:SetAlpha(1)
		
		self.castWarning.ag:Play()
	end
end

local function SetIncomingWarning(self, amount)
	if amount == 0 then return end
	self.incWarning.ag:Stop()

	if amount > 0 then
		-- healing
		amount = '+'..amount
		self.incWarning:SetTextColor(0, 1, 0)
	else
		-- damage (nyi)
		self.incWarning:SetTextColor(1, 0, 0)
	end

	self.incWarning:SetText(amount)

	self.incWarning:SetAlpha(1)
	self.incWarning.ag.fade:SetEndDelay(.5)
	
	self.incWarning.ag:Play()
end

-- Show the frame's castbar if it is casting
-- TODO update this for other units (party1target etc)
local function IsFrameCasting(self)
	if not self.castbar or not self.target then return end

	local name = UnitCastingInfo('target')
	local channel = false
	
	if not name then
		name = UnitChannelInfo('target')
		channel = true
	end
		
	if name then
		-- if they're casting or channeling, try to show a castbar
		np.UNIT_SPELLCAST_START(self, 'target', channel)
	end
end

local function StoreFrameGUID(self, guid)
	if not guid then return end
	if self.guid and loadedGUIDs[self.guid] then
		if self.guid ~= guid then
			-- the currently stored guid is incorrect
			loadedGUIDs[self.guid] = nil
		else
			return
		end
	end
	
	self.guid = guid
	loadedGUIDs[guid] = self
	
	if loadedNames[self.name.text] == self then
		loadedNames[self.name.text] = nil
	end
end

--------------------------------------------------------- Update combo points --
local function ComboPointsUpdate(self)
	if self.points and self.points > 0 then
		local size = (13 + ((18 - 13) / 5) * self.points)
		local blue = (1 - (1 / 5) * self.points)
	
		self:SetText(self.points)
		self:SetFont(kui.m.f.yanone, size, 'OUTLINE')
		self:SetTextColor(1, 1, blue)
	elseif self:GetText() then
		self:SetText('')
	end
end

----------------------------------------------------- Castbar script handlers --
local function OnCastbarUpdate(bar, elapsed)
	if bar.channel then
		bar.progress = bar.progress - elapsed
	else
		bar.progress = bar.progress + elapsed
	end
	
	if	not bar.duration or
		((not bar.channel and bar.progress >= bar.duration) or
		(bar.channel and bar.progress <= 0))
	then
		-- hide the castbar bg
		bar:GetParent():Hide()
		bar.progress = 0
		return
	end
	
	-- display progress
	if bar.max then
		bar.curr:SetText(string.format("%.1f", bar.progress))
		
		if bar.delay == 0 or not bar.delay then
			bar.max:SetText(string.format("%.1f", bar.duration))
		else
			-- display delay
			if bar.channel then
				-- time is removed
				bar.max:SetText(string.format("%.1f", bar.duration)..
					'|cffff0000-'..string.format("%.1f", bar.delay)..'|r')
			else
				-- time is added
				bar.max:SetText(string.format("%.1f", bar.duration)..
					'|cffff0000+'..string.format("%.1f", bar.delay)..'|r')
			end
		end
	end
	
	bar:SetValue(bar.progress/bar.duration)
end

---------------------------------------------------- Update health bar & text --
-- TODO: holy memory usage batman
local function OnHealthValueChanged(oldBar, curr)
	local frame	= oldBar:GetParent()
	local min, max	= oldBar:GetMinMaxValues()
	local deficit, isHpMax = max - curr, curr == max
	local canShowPrecise, big, sml
	
	frame.health:SetMinMaxValues(min, max)
	frame.health:SetValue(curr)
	
	-- display conditions
	if np.kui:getSaved('hp', 'precise') then 
		canShowPrecise = frame.friend
	else
		canShowPrecise = true
	end

	local canShowDeficit, canShowMax =
		canShowPrecise and not isHpMax,
		canShowPrecise and isHpMax
	
	if np.kui:getSaved('hp', 'deficit') and canShowDeficit then
		big = "-" .. kui.num(deficit)
		sml = kui.num(curr)
	elseif np.kui:getSaved('hp', 'max') and canShowMax then
		big = kui.num(max)
		sml = ''
	elseif np.kui:getSaved('hp', 'current') and canShowDeficit then
		big = kui.num(curr)
		sml = kui.num(max)
	elseif np.kui:getSaved('hp', 'percent') and not isHpMax then
		big = floor(curr / max * 100)
		sml = kui.num(curr)
	else
		big = ''
		sml = ''
	end
	
	frame.health.p:SetText(big and big or '')
	
	if frame.health.mo then
		frame.health.mo:SetText(sml and sml or '')
	end
end

------------------------------------------------------- Frame script handlers --
local function OnFrameShow(self)
	-- reset name
	self.name.text = self.oldName:GetText()
	self.name:SetText(self.name.text)
	
	if np.kui:getSaved('hp', 'mouseover') then
		-- force run un-highlight code
		self.highlighted = true
	end

	-- classifications
	if self.boss:IsVisible() then
		self.level:SetText('??b')
		self.level:SetTextColor(1, 0, 0)
		self.level:Show()
	elseif self.state:IsVisible() then
		if self.state:GetTexture() == "Interface\\Tooltips\\EliteNameplateIcon"
		then
			self.level:SetText(self.level:GetText()..'+')
		else
			self.level:SetText(self.level:GetText()..'r')
		end
	end
	
	if self.state:IsVisible() then
		-- hide the elite/rare dragon
		self.state:Hide()
	end
	
	if 	np.kui:getSaved('cast', 'usenames') and
		not loadedNames[self.name.text] and
		not self.guid
	then
		-- store this frame's name
		loadedNames[self.name.text] = self
	end
	
	self:UpdateFrame()
	self:UpdateFrameCritical()
	
	self:SetGlowColour()
	self:IsCasting()
end

local function OnFrameHide(self)
	if self.guid then
		-- remove guid from the store and unset it
		loadedGUIDs[self.guid] = nil
		self.guid = nil
		
		if self.cp then
			self.cp.points = nil
			self.cp:Update()
		end
	end
	
	if loadedNames[self.name.text] == self then
		-- remove name from store
		-- if there are name duplicates, this will be recreated in an onupdate
		loadedNames[self.name.text] = nil
	end
	
	self.lastAlpha	= 0
	self.fadingTo	= nil
	self.hasThreat	= nil
	self.target		= nil
	
	-- unset stored health bar colours
	self.health.r, self.health.g, self.health.b, self.health.reset
		= nil, nil, nil, nil
	
	if self.castbar then
		-- reset cast bar
		self.castbar.duration = nil
		self.castbar.id = nil
		self.castbarbg:Hide()
	end
	
	if self.castWarning then
		-- reset cast warning
		self.castWarning:SetText()
		self.castWarning.ag:Stop()
		
		self.incWarning:SetText()
	end
end

local function OnFrameEnter(self)
	if self.highlight then
		self.highlight:Show()
	end

	self:StoreGUID(UnitGUID('mouseover'))
	
	if np.kui:getSaved('hp', 'mouseover') then
		self.health.p:Show()
		if self.health.mo then self.health.mo:Show() end
	end
end

local function OnFrameLeave(self)
	if self.highlight then
		self.highlight:Hide()
	end

	if not self.target and np.kui:getSaved('hp', 'mouseover') then
		self.health.p:Hide()
		if self.health.mo then self.health.mo:Hide() end
	end
end

local function OnFrameUpdate(self, e)
	self.elapsed	= self.elapsed + e
	self.critElap	= self.critElap + e
	
	self.defaultAlpha = self:GetAlpha()
	------------------------------------------------------------------- Alpha --
	if self.currentAlpha and self.defaultAlpha ~= self.currentAlpha then
		-- ignore default UI's alpha changes
		self:SetAlpha(self.currentAlpha)
	end
	
	if	(	self.defaultAlpha == 1 and
			targetExists) or
		(	np.kui:getSaved('gen', 'fademouse') and
			self.highlighted)
	then
		self.currentAlpha = 1
	elseif	targetExists or np.kui:getSaved('gen', 'fadeall') then
		self.currentAlpha = np.kui:getSaved('gen', 'fadedalpha') or .3
	else
		self.currentAlpha = 1
	end
	------------------------------------------------------------------ Fading --
	if np.kui:getSaved('gen', 'fade') then
		-- track changes in the alpha level and intercept them
		if self.currentAlpha ~= self.lastAlpha then
			if not self.fadingTo or self.fadingTo ~= self.currentAlpha then
				if kui.frameIsFading(self) then
					kui.frameFadeRemoveFrame(self)
				end
			
				-- fade to the new value
				self.fadingTo 		= self.currentAlpha
				local alphaChange	= (self.fadingTo - (self.lastAlpha or 0))
				
				kui.frameFade(self, {
					mode		= alphaChange < 0 and 'OUT' or 'IN',
					timeToFade	= abs(alphaChange) * (np.kui:getSaved('gen', 'fadespeed') or .5),
					startAlpha	= self.lastAlpha or 0,
					endAlpha	= self.fadingTo,
					finishedFunc = function()
						self.fadingTo = nil
					end,
				})
			end
			
			self.lastAlpha = self.currentAlpha
		end
	end
	
	-- call delayed updates
	if self.elapsed > 1 then
		self.elapsed = 0
		self:UpdateFrame()
	end
	
	if self.critElap > .1 then
		self.critElap = 0
		self:UpdateFrameCritical()
	end
end

-- stuff that can be updated less often
local function UpdateFrame(self)
	if	np.kui:getSaved('cast', 'usenames')	and 
		not loadedNames[self.name.text] and
		not self.guid
	then
		-- ensure a frame is still stored for this name, as name conflicts cause
		-- it to be erased when another might still exist
		-- also ensure that if this frame is targeted, this is the stored frame
		-- for its name
		loadedNames[self.name.text] = self
	end
	
	-- Health bar colour
	self:SetHealthColour()
	
	-- force health update (as self.friend is managed by SetHealthColour)
	OnHealthValueChanged(self.oldHealth, self.oldHealth:GetValue())
	
	if self.cp then
		-- combo points
		self.cp:Update()
	end
end

-- stuff that needs to be updated often
local function UpdateFrameCritical(self)
	------------------------------------------------------------------ Threat --
	if self.glow:IsVisible() then
		self.glow.wasVisible = true
	
		self.glow.r, self.glow.g, self.glow.b = self.glow:GetVertexColor()
		self:SetGlowColour(self.glow.r, self.glow.g, self.glow.b)
		
		if not self.friend and np.kui:getSaved('tank', 'toggle') then
			-- in tank mode; is the default glow is red (are we tanking)?
			self.hasThreat = (self.glow.g + self.glow.b) < .1
			
			if self.hasThreat then
				-- tanking; recolour bar & glow
				local r, g, b = unpack(np.kui:getSaved('tank', 'glowcolour'))
				self:SetGlowColour(r, g, b)
				self:SetHealthColour()
			end	
		end
	elseif self.glow.wasVisible then
		self.glow.wasVisible = nil
		
		-- restore shadow glow colour
		self:SetGlowColour()
		
		if self.hasThreat then
			-- lost threat
			self.hasThreat = nil
			self:SetHealthColour()
		end
	end
	------------------------------------------------------------ Target stuff --
	if	targetExists and
		self.defaultAlpha == 1 and
		self.name.text == UnitName('target')
	then
		-- this frame is targetted
		if not self.target then
			-- the frame just became targetted
			self.target = true
			self:StoreGUID(UnitGUID('target'))
			
			if np.kui:getSaved('hp', 'mouseover') then
				self.health.p:Show()
				if self.health.mo then self.health.mo:Show() end
			end
			
			-- check if the frame is casting
			self:IsCasting()
		end
	elseif self.target then
		self.target = nil
		
		if not self.highlighted and np.kui:getSaved('hp', 'mouseover') then
			self.health.p:Hide()
			if self.health.mo then self.health.mo:Hide() end
		end
	end
	--------------------------------------------------------------- Mouseover --
	if self.oldHighlight:IsShown() then
		if not self.highlighted then
			self.highlighted = true
			OnFrameEnter(self)
		end
	elseif self.highlighted then
		self.highlighted = false
		OnFrameLeave(self)
	end
	
	-- [debug]
	--[[
	if self.guid and loadedGUIDs[self.guid] == self then
		self.guidtext:SetText(self.guid)
	else
		self.guidtext:SetText(nil)
	end
	
	if self.name.text and loadedNames[self.name.text] == self then
		self.nametext:SetText('Has name')
	else
		self.nametext:SetText(nil)
	end
	]]
end

--------------------------------------------------------------- KNP functions --
function np:GetNameplate(guid, name)
	local gf, nf = loadedGUIDs[guid], loadedNames[name]

	if gf then
		return gf
	elseif nf then
		return nf
	else
		return nil
	end
end

function np:IsNameplate(frame)
	if frame:GetName() and not string.find(frame:GetName(), "^NamePlate") then
		return false
	end
	
	local overlayRegion = select(2, frame:GetRegions())
    return (overlayRegion and
		overlayRegion:GetObjectType() == "Texture" and
		overlayRegion:GetTexture() == "Interface\\Tooltips\\Nameplate-Border")
end

function np:InitFrame(frame)
	-- TODO: this is just a tad long
	frame.init = true

	local healthBar, castBar = frame:GetChildren()
	local _, castbarOverlay, shieldedRegion, spellIconRegion
		= castBar:GetRegions()
	
    local
		glowRegion, overlayRegion, highlightRegion, nameTextRegion,
		levelTextRegion, bossIconRegion, raidIconRegion, stateIconRegion
		= frame:GetRegions() 
    
	highlightRegion:SetTexture(nil)
	bossIconRegion:SetTexture(nil)
	shieldedRegion:SetTexture(nil)
	castbarOverlay:SetTexture(nil)
	glowRegion:SetTexture(nil)

	-- disable default cast bar
	castBar:SetParent(nil)
	castbarOverlay.Show = function() return end
	castBar:SetScript('OnShow', function() castBar:Hide() end)
	
	frame.bg	= overlayRegion
	frame.glow	= glowRegion
	frame.boss	= bossIconRegion
	frame.state	= stateIconRegion
	frame.level	= levelTextRegion
	
	if np.kui:getSaved('cast', 'spellicon') then
		frame.spell = spellIconRegion
	end
	
	frame.oldHealth = healthBar
	frame.oldHealth:Hide()
	
	frame.oldName = nameTextRegion
	frame.oldName:Hide()
	
	frame.oldHighlight = highlightRegion
	
    ---------------------------------------------------------- Frame functions--
    frame.UpdateFrame			= UpdateFrame
    frame.UpdateFrameCritical	= UpdateFrameCritical
    frame.SetHealthColour   	= SetHealthColour
    frame.SetGlowColour     	= SetGlowColour
	frame.IsCasting				= IsFrameCasting
	frame.StoreGUID				= StoreFrameGUID
    
    ------------------------------------------------------------------ Layout --
	-- health bar --------------------------------------------------------------
	-- size & point are set OnFrameShow
	frame.health = CreateFrame('StatusBar', nil, frame)
	frame.health:SetStatusBarTexture(kui.m.t.bar)
	
	frame.health:SetWidth(110)
	frame.health:SetHeight(10)
	
	frame.health:ClearAllPoints()
	frame.health:SetPoint("CENTER")
	
	-- so i suppose I have to make sure it's in front of itself
	frame.health:SetFrameLevel(frame:GetFrameLevel()+1)
	
	-- frame background --------------------------------------------------------
	-- this also provides the shadow & threat glow
	-- 120x20 over 256x32
	frame.bg:SetTexture('Interface\\AddOns\\Kui_Nameplates\\FrameGlow')
	frame.bg:SetTexCoord(0, .469, 0, .625)
	frame.bg:SetVertexColor(0, 0, 0, .85)
	
	frame.bg:SetPoint('TOPLEFT', frame.health, -5, 5)
	frame.bg:SetPoint('BOTTOMRIGHT', frame.health, 5, -5)
	
	-- health background -------------------------------------------------------
	frame.health.bg = frame:CreateTexture(nil, 'ARTWORK')
	frame.health.bg:SetDrawLayer('ARTWORK', 1) -- (1 sub-layer above .bg)
	frame.health.bg:SetTexture(kui.m.t.solid)
	frame.health.bg:SetVertexColor(0, 0, 0, .85)
	
	frame.health.bg:SetPoint('TOPLEFT', frame.health, -1, 1)
	frame.health.bg:SetPoint('BOTTOMRIGHT', frame.health, 1, -1)
	
	-- overlay (text is parented to this) --------------------------------------
	frame.overlay = CreateFrame('Frame', nil, frame)
	frame.overlay:SetAllPoints(frame.health)
	
	frame.overlay:SetFrameLevel(frame.health:GetFrameLevel()+1)
	
	-- highlight ---------------------------------------------------------------
	if np.kui:getSaved('gen', 'highlight') then
		frame.highlight = frame.overlay:CreateTexture(nil, 'ARTWORK')
		frame.highlight:SetTexture(kui.m.t.innerShade)
		
		frame.highlight:SetAllPoints(frame.health)
		
		frame.highlight:SetVertexColor(1, 1, 1)
		frame.highlight:SetAlpha(.2)
		frame.highlight:Hide()
	end
	
	-- health text -------------------------------------------------------------
	frame.health.p = kui.CreateFontString(frame.overlay, {
		font = kui.m.f.yanone, size = 11, outline = "OUTLINE" })
	frame.health.p:SetJustifyH('RIGHT')
	
	frame.health.p:SetPoint('BOTTOMRIGHT', frame.health, 'TOPRIGHT', -2, -3)
	
	if np.kui:getSaved('hp', 'showalt') then
		frame.health.mo = kui.CreateFontString(frame.overlay, {
			font = kui.m.f.yanone, size = 8, outline = "OUTLINE" })
		frame.health.mo:SetJustifyH('RIGHT')
	
		frame.health.mo:SetPoint('BOTTOMRIGHT', frame.health, -2, -2)
		frame.health.mo:SetAlpha(.5)
	end
	
	-- level text --------------------------------------------------------------
	frame.level = kui.CreateFontString(frame.level, { reset = true,
		font = kui.m.f.yanone, size = 9, outline = 'OUTLINE' })
	frame.level:SetParent(frame.overlay)
	
	frame.level:ClearAllPoints()
	frame.level:SetPoint('BOTTOMLEFT', frame.health, 'TOPLEFT', 2, -3)

	-- name text ---------------------------------------------------------------
	frame.name = kui.CreateFontString(frame.overlay, {
		font = kui.m.f.yanone, size = 9, outline = 'OUTLINE' })
	frame.name:SetJustifyH('LEFT')

	frame.name:SetHeight(8)

	frame.name:SetPoint('LEFT', frame.level, 'RIGHT', -2, 0)
	frame.name:SetPoint('RIGHT', frame.health.p, 'LEFT')
	
	-- combo point text --------------------------------------------------------
	if np.kui:getSaved('gen', 'combopoints') then
		frame.cp = kui.CreateFontString(frame.health,
			{ font = kui.m.f.yanone, size = 13, outline = 'OUTLINE', shadow = true })
		frame.cp:SetPoint('LEFT', frame.health, 'RIGHT', 5, 1)
		
		frame.cp.Update = ComboPointsUpdate
	end
	
	if np.kui:getSaved('cast', 'toggle') then
		-- TODO move this (and similar things) into functions
		-- cast bar background -------------------------------------------------
		frame.castbarbg = CreateFrame("Frame", nil, frame)
		frame.castbarbg:SetFrameStrata('BACKGROUND');
		frame.castbarbg:SetBackdrop({
			bgFile = kui.m.t.solid, edgeFile = kui.m.t.shadow,
			edgeSize = 5, insets = {
				top = 5, left = 5, bottom = 5, right = 5
			}
		})
		
		frame.castbarbg:SetBackdropColor(0, 0, 0, .85)
		frame.castbarbg:SetBackdropBorderColor(1, .2, .1, 0)
		frame.castbarbg:SetHeight(15)
		
		frame.castbarbg:SetPoint('TOPLEFT', frame.health.bg, 'BOTTOMLEFT', -5, 4)
		frame.castbarbg:SetPoint('TOPRIGHT', frame.health.bg, 'BOTTOMRIGHT', 5, 0)
		
		frame.castbarbg:Hide()
		
		-- cast bar ------------------------------------------------------------
		frame.castbar = CreateFrame("StatusBar", nil, frame.castbarbg)
		frame.castbar:SetStatusBarTexture(kui.m.t.bar)		
		
		frame.castbar:SetPoint('TOPLEFT', frame.castbarbg, 'TOPLEFT', 6, -6)
		frame.castbar:SetPoint('BOTTOMLEFT', frame.castbarbg, 'BOTTOMLEFT', 6, 6)
		frame.castbar:SetPoint('RIGHT', frame.castbarbg, 'RIGHT', -6, 0)
		
		frame.castbar:SetMinMaxValues(0, 1)
	
		-- cast bar text -------------------------------------------------------
		if np.kui:getSaved('cast', 'spellname') then
			frame.castbar.name = kui.CreateFontString(frame.castbar, {
				font = kui.m.f.yanone, size = 9, outline = "OUTLINE" })
			frame.castbar.name:SetPoint('TOPLEFT', frame.castbar, 'BOTTOMLEFT', 2, -1)
		end
		
		if np.kui:getSaved('cast', 'casttime') then
			frame.castbar.max = kui.CreateFontString(frame.castbar, {
				font = kui.m.f.yanone, size = 9, outline = "OUTLINE" })
			frame.castbar.max:SetPoint('TOPRIGHT', frame.castbar, 'BOTTOMRIGHT', -2, -1)

			frame.castbar.curr = kui.CreateFontString(frame.castbar, {
				font = kui.m.f.yanone, size = 8, outline = "OUTLINE" })
			frame.castbar.curr:SetAlpha(.5)
			frame.castbar.curr:SetPoint('TOPRIGHT', frame.castbar.max, 'TOPLEFT', -1, -1)
		end

		if frame.spell then
			-- cast bar icon background ----------------------------------------
			frame.spellbg = frame.castbarbg:CreateTexture(nil, 'BACKGROUND')
			frame.spellbg:SetTexture(kui.m.t.solid)
			frame.spellbg:SetSize(18, 18)
			
			frame.spellbg:SetVertexColor(0, 0, 0, .85)
			
			frame.spellbg:SetPoint('TOPRIGHT', frame.health.bg, 'TOPLEFT', -1, 0)
			
			-- cast bar icon ---------------------------------------------------
			frame.spell:ClearAllPoints()
			frame.spell:SetParent(frame.castbarbg)
			frame.spell:SetSize(16, 16)
			
			frame.spell:SetPoint('TOPRIGHT', frame.spellbg, -1, -1)
			
			frame.spell:SetTexCoord(.1, .9, .1, .9)
		end
		
		-- scripts -------------------------------------------------------------
		frame.castbar:HookScript('OnShow', function(bar)
			if bar.interruptible then
				bar:SetStatusBarColor(unpack(np.kui:getSaved('cast', 'barcolour')))
				bar:GetParent():SetBackdropBorderColor(0, 0, 0, .3)
			else
				bar:SetStatusBarColor(.8, .1, .1)			
				bar:GetParent():SetBackdropBorderColor(1, .1, .2, .5)
			end
		end)

		frame.castbar:SetScript('OnUpdate', OnCastbarUpdate)
	end
	
	-- cast warning ------------------------------------------------------------
	if np.kui:getSaved('cast', 'warnings') then
		-- casting spell name
		frame.castWarning = kui.CreateFontString(frame.overlay, {
			font = kui.m.f.yanone, size = 10, outline = 'OUTLINE' })
		frame.castWarning:SetPoint('BOTTOMLEFT', frame.level, 'TOPLEFT', 0, 1)
		frame.castWarning:Hide()

		frame.castWarning.ag 	= frame.castWarning:CreateAnimationGroup()
		frame.castWarning.fade	= frame.castWarning.ag:CreateAnimation('Alpha')
		frame.castWarning.fade:SetSmoothing('IN')
		frame.castWarning.fade:SetDuration(3)
		frame.castWarning.fade:SetChange(-1)
		
		frame.castWarning.ag:SetScript('OnPlay', function(self)
			self:GetParent():Show()
		end)
		
		frame.castWarning.ag:SetScript('OnFinished', function(self)
			self:GetParent():Hide()
		end)
		
		-- incoming healing
		frame.incWarning = kui.CreateFontString(frame.overlay, {
			font = kui.m.f.yanone, size = 8, outline = 'OUTLINE' })
		frame.incWarning:SetPoint('BOTTOMRIGHT', frame.health.p, 'TOPRIGHT', 1)
		frame.incWarning:Hide()
		
		frame.incWarning.ag 	 = frame.incWarning:CreateAnimationGroup()
		frame.incWarning.ag.fade = frame.incWarning.ag:CreateAnimation('Alpha')
		frame.incWarning.ag.fade:SetSmoothing('IN')
		frame.incWarning.ag.fade:SetDuration(.5)
		frame.incWarning.ag.fade:SetChange(-.5)
		
		frame.incWarning.ag:SetScript('OnPlay', function(self)
			self:GetParent():Show()
		end)
		
		frame.incWarning.ag:SetScript('OnFinished', function(self)
			if self.fade:GetEndDelay() > 0 then
				-- fade out fully
				self:GetParent():SetAlpha(.5)
				self.fade:SetEndDelay(0)
				self:Play()
			else
				self:GetParent():Hide()
			end
		end)
		
		-- handlers
		frame.SetCastWarning = SetCastWarning
		frame.SetIncomingWarning = SetIncomingWarning
	end
    
    ----------------------------------------------------------------- Scripts --
	frame:SetScript('OnShow', OnFrameShow)
	frame:SetScript('OnHide', OnFrameHide)
    frame:SetScript('OnUpdate', OnFrameUpdate)
	
	frame.oldHealth:SetScript('OnValueChanged', OnHealthValueChanged)

	-- [debug]
	--[[
	frame:SetBackdrop({bgFile=kui.m.t.solid})
	frame:SetBackdropColor(1, 1, 1, .5)
	
	frame.guidtext = kui.CreateFontString(frame, {
		font = kui.m.f.yanone, size = 10, outline = "OUTLINE" })
	frame.guidtext:SetPoint('TOP', frame, 'BOTTOM')
	
	frame.nametext = kui.CreateFontString(frame, {
		font = kui.m.f.yanone, size = 10, outline = "OUTLINE" })
	frame.nametext:SetPoint('TOP', frame.guidtext, 'BOTTOM')
	]]
	
	------------------------------------------------------------ Finishing up --
    frame.elapsed	= 0
	frame.critElap	= 0
	
	-- force OnShow
	OnFrameShow(frame)
end

---------------------------------------------------------------------- Events --
function np:UNIT_COMBO_POINTS()
	local target = UnitGUID('target')
	if not target or not loadedGUIDs[target] then return end
	target = loadedGUIDs[target]
	
	if target.cp then
		target.cp.points = GetComboPoints('player', 'target')
		target.cp:Update()	
	end
	
	-- clear points on other frames
	for guid, frame in pairs(loadedGUIDs) do
		if frame.cp and guid ~= target.guid then
			frame.cp.points = nil
			frame.cp:Update()
		end
	end
end

function np:PLAYER_TARGET_CHANGED()
	targetExists = UnitExists('target')
end

-- automatic toggling of enemy frames
function np:PLAYER_REGEN_ENABLED()
	SetCVar('nameplateShowEnemies', 0)
end
function np:PLAYER_REGEN_DISABLED()
	SetCVar('nameplateShowEnemies', 1)
end

-- custom cast bar events ------------------------------------------------------
function np.UNIT_SPELLCAST_START(frame, unit, channel)
	local cb = frame.castbar
	local	
		name, _, text, texture, startTime, endTime, _, castID,
		notInterruptible
		
	if channel then
		name, _, text, texture, startTime, endTime, _, castID, notInterruptible
			= UnitChannelInfo(unit)
	else
		name, _, text, texture, startTime, endTime, _, castID, notInterruptible
			= UnitCastingInfo(unit)
	end
	
	if not name then
		frame.castbarbg:Hide()
		return
	end

	cb.id 				= castID
	cb.channel			= channel
	cb.interruptible 	= not notInterruptible
	cb.duration			= (endTime/1000) - (startTime/1000)
	cb.delay			= 0
	
	if frame.spell then
		frame.spell:SetTexture(texture)
	end
	
	if cb.name then
		cb.name:SetText(name)
	end
	
	if cb.channel then
		cb.progress	= (endTime/1000) - GetTime()
	else
		cb.progress	= GetTime() - (startTime/1000)
	end
	
	frame.castbarbg:Show()
end

function np.UNIT_SPELLCAST_DELAYED(frame, unit, channel)
	local cb = frame.castbar
	local _, name, startTime, endTime
	
	if channel then
		name, _, _, _, startTime, endTime = UnitChannelInfo(unit)
	else
		name, _, _, _, startTime, endTime = UnitCastingInfo(unit)
	end
	
	if not name then
		return
	end
	
	local newProgress
	if cb.channel then
		newProgress	= (endTime/1000) - GetTime()
	else
		newProgress	= GetTime() - (startTime/1000)
	end
	
	cb.delay = (cb.delay or 0) + cb.progress - newProgress
	cb.progress = newProgress
end

function np.UNIT_SPELLCAST_CHANNEL_START(frame, unit)
	np.UNIT_SPELLCAST_START(frame, unit, true)
end
function np.UNIT_SPELLCAST_CHANNEL_UPDATE(frame, unit)
	np.UNIT_SPELLCAST_DELAYED(frame, unit, true)
end

function np.UNIT_SPELLCAST_STOP(frame, unit)
	frame.castbarbg:Hide()
end
function np.UNIT_SPELLCAST_FAILED(frame, unit)
	frame.castbarbg:Hide()
end
function np.UNIT_SPELLCAST_INTERRUPTED(frame, unit)
	frame.castbarbg:Hide()
end
function np.UNIT_SPELLCAST_CHANNEL_STOP(frame, unit)
	frame.castbarbg:Hide()
end

-- custom cast bar event handler -----------------------------------------------
function np.UnitCastEvent(e, unit, ...)
	if unit == 'player' then return end
	local guid, name, f = UnitGUID(unit), GetUnitName(unit), nil
	--guid, name = UnitGUID('target'), GetUnitName('target')
	
	-- fetch the unit's nameplate
	f = np:GetNameplate(guid, name)
	if f then
		if not f.castbar then return end
		if	e == 'UNIT_SPELLCAST_STOP' or
			e == 'UNIT_SPELLCAST_FAILED' or
			e == 'UNIT_SPELLCAST_INTERRUPTED'
		then
			-- these occasionally fire after a new _START
			local _, _, castID = ...
			if f.castbar.id ~= castID then
				return
			end
		end
		
		np[e](f, unit)
	end
end

-- cast warning handler --------------------------------------------------------
function np.CastWarningEvent(_, ...)
	-- _ = COMBAT_LOG_EVENT_UNFILTERED
	local castTime, event, _, guid, name, _, _, targetGUID, targetName
		= ...
	
	if castEvents[event] then
		if	event == 'SPELL_HEAL' or
			event == 'SPELL_PERIODIC_HEAL'
		then
			-- fetch the spell's target's nameplate
			guid, name = targetGUID, targetName
		end
		
		local f = np:GetNameplate(guid, name)
		if f then
			if not f.SetIncomingWarning then return end
			local spName, spSch = select(13, ...)
			
			if	event == 'SPELL_HEAL' or
				event == 'SPELL_PERIODIC_HEAL'
			then
				-- display heal warning
				local amount = select(15, ...)
				f:SetIncomingWarning(amount)
			elseif event == 'SPELL_INTERRUPT' then
				-- hide the warning
				f:SetCastWarning(nil)
			else
				-- or display it for this spell
				f:SetCastWarning(spName, spSch)
			end
		end
	end
end

---------------------------------------------------------------- Kui handlers --
local WorldFrame = WorldFrame

np.frames = 0
function np:OnUpdate()
	local i, f, frames
	frames = select('#', WorldFrame:GetChildren())
	
	if frames ~= np.frames then
		for i = 1, frames do
			f = select(i, WorldFrame:GetChildren())

			if self:IsNameplate(f) and not f.init then
				self:InitFrame(f)
			end
		end
		
		np.frames = frames
	end
end

np.kui:addEvent('PLAYER_TARGET_CHANGED')
np.kui:addTask(.1)