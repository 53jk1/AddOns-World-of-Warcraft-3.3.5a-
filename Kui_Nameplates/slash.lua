--[[
	Kui Nameplates
	Kesava-Auchindoun
	As part of Kui
	
	Code relating to the slash commands
	Passes np
]]

local addon, ns	= ...
local np			= {}

np.kui = kui:addPlugin(addon, np)

---------------------------------------------------------------- KNP handlers --
-- slash command handler
function np:Slash(msg, msgs)
	self.kui:configSlash(msg, msgs)
end

------------------------------------------------------ Configuration defaults --
function np:ADDON_LOADED()
	self.kui:registerSaved('KuiNameplatesSaved', false, 3)
	
	-- TODO: i suppose this should be built in to kui
	self.kui:addSetting(nil, 'reset', nil,
		'Reset configuration to defaults. This will reload the UI',
		function()
			_G['KuiNameplatesSaved'] = {}
			ReloadUI()
		end)
	
	----------------------------------------------------------------------------
	self.kui:addSettingGroup('gen', 'General display')
	
	self.kui:addSetting('gen', 'fade', true,
		'Smoothly fade frames when they appear or when you change targets')
	
	self.kui:addSetting('gen', 'fadespeed', .5,
		'Frame fade speed multiplier',
		nil, { numL = .1, numU = 5 })
	
	self.kui:addSetting('gen', 'fademouse', false,
		'Fade in nameplates when you hover the mouse over them')
	
	self.kui:addSetting('gen', 'fadeall', false,
		'Always fade all nameplates except the target\'s')
	
	self.kui:addSetting('gen', 'fadedalpha', .3,
		'The alpha value to which untargeted frames fade',
		nil, { numL = 0, numU = 1 })
	
	self.kui:addSetting('gen', 'combat', false,
		'Automatically show/hide enemy nameplates upon entering/exiting combat',
		nil, { l = function(self)
			if self.v then
				np.kui:addEvent('PLAYER_REGEN_ENABLED')
				np.kui:addEvent('PLAYER_REGEN_DISABLED')
			else
				np.kui:removeEvent('PLAYER_REGEN_ENABLED')
				np.kui:removeEvent('PLAYER_REGEN_DISABLED')
			end
		end})

	self.kui:addSetting('gen', 'highlight', true,
		'Highlight frames when you hover the mouse over them',
		nil, { rl = true })
		
	self.kui:addSetting('gen', 'combopoints', true,
		'Show combo points next to frames',
		nil, { rl = true, l = function(self)
			if self.v then
				np.kui:addEvent('UNIT_COMBO_POINTS')
			else
				np.kui:removeEvent('UNIT_COMBO_POINTS')
			end
		end})

	----------------------------------------------------------------------------
	self.kui:addSettingGroup('tank', 'Tank mode')
	
	self.kui:addSetting('tank', 'toggle', false,
		'Recolour health bars when you have threat')
	
	self.kui:addSetting('tank', 'barcolour', { .2, .9, .1 },
		'The colour of the health bar when you have threat')

	self.kui:addSetting('tank', 'glowcolour', { 1, 0, 0 },
		'The colour of the nameplate glow when you have threat')

	----------------------------------------------------------------------------
	self.kui:addSettingGroup('hp', 'Health display')
	
	self.kui:addSetting('hp', 'max', true,
		'Show maximum health when at 100%')
	
	self.kui:addSetting('hp', 'deficit', true,
		'Show deficit health when lower than 100%')
	
	self.kui:addSetting('hp', 'percent', true,
		'Show health percent when lower than 100% and if precise values cannot be shown')
	
	self.kui:addSetting('hp', 'current', false,
		'Show current health when lower than 100%')
		
	self.kui:addSetting('hp', 'precise', true,
		'Only show precise numeric values for friendly units')

	self.kui:addSetting('hp', 'showalt', true,
		'Show small alternate health text values',
		nil, { rl = true })
	
	self.kui:addSetting('hp', 'mouseover', false,
		'Hide health until you hover the mouse over or target the nameplate')
		
	----------------------------------------------------------------------------
	self.kui:addSettingGroup('cast', 'Cast bar')
	
	self.kui:addSetting('cast', 'toggle', true,
		'Enable the cast bar',
		nil, { rl = true, l = function(self)
			if self.v then
				np.kui:addEvent('UNIT_SPELLCAST_START', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_FAILED', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_STOP', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_INTERRUPTED', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_DELAYED', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_CHANNEL_START', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_CHANNEL_UPDATE', np.UnitCastEvent)
				np.kui:addEvent('UNIT_SPELLCAST_CHANNEL_STOP', np.UnitCastEvent)
			else
				np.kui:removeEvent('UNIT_SPELLCAST_START', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_FAILED', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_STOP', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_INTERRUPTED', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_DELAYED', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_CHANNEL_START', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_CHANNEL_UPDATE', np.UnitCastEvent)
				np.kui:removeEvent('UNIT_SPELLCAST_CHANNEL_STOP', np.UnitCastEvent)
			end
		end})
	
	self.kui:addSetting('cast', 'casttime', true,
		'Show current and maximum cast time and the total delayed time caused by attacks',
		nil, { rl = true })

	self.kui:addSetting('cast', 'spellname', true,
		'Show the spell\'s name under the cast bar',
		nil, { rl = true })
		
	self.kui:addSetting('cast', 'spellicon', true,
		'Show the spell\'s icon next to the health bar',
		nil, { rl = true })

	self.kui:addSetting('cast', 'barcolour', { .43, .47, .55 },
		'Colour of the cast bar when the spell is interruptible',
		kui.config.ParseColorArg)
	
	self.kui:addSetting('cast', 'warnings', false,
		'Show cast warnings and incoming healing',
		nil, { rl = true, l = function(self)
			if self.v then
				np.kui:addEvent('COMBAT_LOG_EVENT_UNFILTERED', np.CastWarningEvent)
			else
				np.kui:removeEvent('COMBAT_LOG_EVENT_UNFILTERED')
			end
		end})
	
	self.kui:addSetting('cast', 'usenames', false,
		'Use names to show cast warnings. This will increase memory usage and may cause warnings to be displayed on incorrect nameplates, but warnings will be shown for all visible units rather than only those which have been targeted')
	
	------------------------------------------------------------------------
	self.kui:addSlash('KUI_NAMEPLATES', {'kuinp', 'knp'})
end

np.kui:addEvent('ADDON_LOADED')
ns.np	= np