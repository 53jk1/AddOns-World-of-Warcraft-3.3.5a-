local _, ns = ...
local kpf, kf = ns.kpf, ns.kf
--- slash command helper ---------------------------------------------------
function kpf:addSlash(name, commands, func)
	if type(commands) == 'string' then
		commands = { commands }
	end

	if type(commands) ~= 'table' then
		kf.kui:print('invalid call to addSlash: commands must be table')
		return
	end

	if not func and not self.t.Slash then
		kf.kui:print('no .Slash handler exists in plugin `' .. self.n .. '`')
		return
	end
	
	local i = 0
	for _, command in pairs(commands) do
		i = i + 1
		_G['SLASH_' .. name .. i] = '/' .. command
	end
	
	SlashCmdList[name] = function(msg)
		local wlist = {}
		for word in msg:gmatch('%S+') do
			table.insert(wlist, word)
		end
		
		if func then
			func(msg, wlist)
		else
			self.t:Slash(msg, wlist)
		end
	end
end