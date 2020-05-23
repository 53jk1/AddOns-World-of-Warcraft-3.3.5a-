local _, ns = ...
local kpf, kf = ns.kpf, ns.kf
--[[ slash configuration helper ------------------------------------------------
	Registers the following variables in plugins:
	.saved and .savedPC
		These store the names of the global saved variables.
		
	.config and .configPC
		These store what will become a copy of the global saved variable once
		all settings have been added using the addSetting and addSettingGroup
		functions. This is commited to the global variable whenever a call to
		configSlash (the slash handler) is successful.  Storing this 'copy'
		ensures that if a setting or group is renamed, it will not exist as a
		ghost in the global variable.
]]
-- configuration functions
kui.config = {}

-- generic argument functions
-- parse .1 .2 .3[ .4] into {.1, .2, .3[, .4] }
kui.config.ParseColourArg = function(self, msgs)
	local r, g, b, a = select(2, unpack(msgs))
	
	if a then
		a = tonumber(a)
	end
	
	r, g, b =
		tonumber(r),
		tonumber(g),
		tonumber(b)
	
	if	(r and r <= 1) and (g and g <= 1) and (b and b <= 1) and
		(not a or a <= 1)
	then
		self.v = { r, g, b, a or nil }
		return true
	end
end

-- convert a numeric string and validate it against provided limits
kui.config.ParseNumberArg = function(self, msgs)
	local num = tonumber(msgs[2])
	if	num and
		(not self.numL or num >= self.numL) and	-- lower limit
		(not self.numU or num <= self.numU)		-- upper limit
	then
		self.v = num
		return true
	end
end

-- invert the setting's boolean value
kui.config.ParseBooleanArg = function(self, msgs)
	self.v = not self.v
	return true
end

-- print the given generated configuration table
kui.config.PrintTable = function(tbl, altered)
	for setting, value in pairs(tbl) do
		if	type(value) == 'table' and
			(not altered or setting == altered)
		then
			local final -- final message line for this setting
			
			if value.gd then
				final = setting
			else
				final =
					(altered and setting..' is now' or setting)..
					(value.v == nil and '' or ': ')
			end
			
			if value.gd then
				final = final..': |cffffffaa'..value.gd..' settings|r'
			elseif value.v == true then
				final = final..'|cff00ff00enabled|r'
			elseif value.v == false then
				final = final..'|cffff0000disabled|r'
			elseif type(value.v) == 'table' then
				if #value.v == 3 or #value.v == 4 then
					-- value is/should be a colour table
					final = final..string.format('|cff%02x%02x%02x'..table.concat(value.v, ', ')..'|r',
						value.v[1]*255, value.v[2]*255, value.v[3]*255)
				else
					final = final..table.concat(value.v, ', ')
				end
			elseif value.v and (type(value.v) == 'string' or type(value.v) == 'number') then
				final = final..value.v
			end
			
			if value.d then
				final = final..' |cff888888['..value.d..']|r'
			end
			
			if value.rl then
				final = final..' |cffff0000[Requires UI reload]|r'
			end
			
			print(final)
		end
	end
end

-- register a saved variable
function kpf:registerSaved(variableName, perChar, version)
	if not _G[variableName] then
		_G[variableName] = {}
	end

	if version then
		if select('#', _G[variableName]) == 0 then
			_G[variableName].kcversion = version
		elseif	_G[variableName].kcversion ~= version then
			-- settings are out of date; reset them
			_G[variableName] = { kcversion = version }
			self:print((perChar and 'Per-character' or 'Global')..' configuration has been reset due to an update.')
		end
	end
	
	if perChar then
		self.savedPC = variableName
	else
		self.saved = variableName
	end
end

-- update the registered saved variable
function kpf:updateSaved(perChar)
	local var = perChar and self.savedPC or self.saved

	if var then
		_G[var] = perChar and kui.configPC or kui.config
	end
end

-- add a setting group to this plugin's config table
function kpf:addSettingGroup(name, description, perChar)
	if not self.saved and not self.savedPC then
		kf.kui:print('attempt to add setting group with no saved variable in plugin `'..self.n..'`')
		return
	end
	
	if name == 'kcversion' then
		kf.kui:print('attempt to add a setting group named `kcversion` in plugin `'..self.n..'`')
		return
	end
	
	local tbl
	if perChar then
		self.configPC = self.configPC or {}
		tbl = self.configPC
	else
		self.config = self.config or {}
		tbl = self.config
	end
	
	-- create group
	tbl[name] = { gd = description }
end

-- add a setting to this plugin's config table
function kpf:addSetting(group, command, default, desc, func, add)
	if not self.saved and not self.savedPC then
		kf.kui:print('attempt to add setting with no saved variable in plugin `'..self.n..'`')
		return
	end

	--[[ add = {
		i = invalidMsg
		p = perChar
		l = loadFunc
	}]]
	
	local perChar	= add and add.p or nil
	local sv		= perChar and _G[self.savedPC] or _G[self.saved]
	
	local tbl
	if perChar then
		self.configPC = self.configPC or {}
		tbl = self.configPC
	else
		self.config = self.config or {}
		tbl = self.config
	end
	
	if group then
		if type(tbl[group]) == 'table' and tbl[group].gd then
			-- create setting in the group
			tbl = tbl[group]
			sv = sv[group] or nil
		else
			kf.kui:print('attempt to add setting to non-existing or corrupt group `'..group..'` in plugin `'..self.n..'`')
			return
		end
	end

	if not func then
		-- guess the setting type
		local typ = type(default)
		if typ == 'boolean' then
			func = kui.config.ParseBooleanArg
		elseif typ == 'number' then
			func = kui.config.ParseNumberArg
		elseif typ == 'table' and (#default == 3 or #default == 4) then
			-- table of numbers: r, g, b[, a]
			func = kui.config.ParseColourArg
		end
	end
	
	-- generate invalid argument warnings
	if func == kui.config.ParseNumberArg and (not add or not add.i) then
		if not add then
			add = { i = 'Must be a number.' }
		elseif add.numU and add.numL then
			add.i = 'Must be a number between '..add.numL..' and '..add.numU..'.'
		elseif add.numL and not add.numU then
			add.i = 'Must be a number below '..add.numU..'.'
		elseif add.numU and not add.numL then
			add.i = 'Must be a number above '..add.numL..'.'
		end
	elseif func == kui.config.ParseColourArg and (not add or not add.i) then
		if not add then add = {} end
		add.i = 'Must be 3 or 4 numbers between 0 and 1 representing red, green, blue [and alpha]. E.g. .25 .5 0 1'
	end
	
	-- create command table
	tbl[command] = {
		d = desc,
		f = func
	}
	tbl = tbl[command]
	
	if sv and sv[command] then
		-- this setting exists in the saved variable, inherit it
		tbl.v = sv[command].v
	else
		-- or use the default value
		tbl.v = default
	end
	
	if add then
		-- add additional values
		for k,v in pairs(add) do
			tbl[k] = v
		end
		
		if tbl.l then
			-- run load function
			tbl.l(tbl)
		end
	end
end

-- handle slash command for configuration (print, call functions, etc)
function kpf:configSlash(msg, msgs)
	local tbl, altered = self.config
	
	if _G[self.saved].kcversion and not self.config.kcversion then
		-- store the configuration version in the local copy
		self.config.kcversion = _G[self.saved].kcversion
	end
	
	if type(tbl[msgs[1]]) == 'table' and tbl[msgs[1]].gd then
		-- this is a call to a grouped setting
		tbl = tbl[msgs[1]]
		table.remove(msgs, 1)
	end
	
	for setting, value in pairs(tbl) do
		if	msgs[1] ~= nil and 
			type(value) == 'table' and
			msgs[1] == setting and
			value.f
		then
			altered = value.f(value, msgs)
			
			if altered then
				altered = setting
			elseif altered == nil then
				self.t.kui:print('|cffff0000Invalid arguments for '..setting..'.|r')
				
				if value.i and type(value.i) == 'string' then
					print('|cffff0000Usage:|r '..value.i)
				end
				return
			end
			
			if value.l then
				-- run load function
				value.l(value)
			end
			
			break
		end
	end
	
	-- print config
	self.t.kui:print('configuration:')
	kui.config.PrintTable(tbl, altered)
	
	-- update saved variable
	_G[self.saved] = self.config
end

function kpf:getSaved(group, setting)
	if self.config[group] and self.config[group][setting] then
		return self.config[group][setting].v
	elseif self.config[setting] then
		return self.config[setting].v
	else
		return nil
	end
end
