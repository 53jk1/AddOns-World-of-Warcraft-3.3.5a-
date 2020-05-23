local _, ns = ...
local kpf, kf = ns.kpf, ns.kf
-- plugin helper ---------------------------------------------------------------
kui.plugins = {}

-- create metatable for a plugin
-- called like: example.kui = kui:addPlugin("My_Name", example)
function kui:addPlugin(name, table)
	if not name then
		kf.kui:print('attempted to add nil plugin')
		return
	end
		
	kui.plugins[name] = {}
	setmetatable(kui.plugins[name], kpf)
	
	kui.plugins[name].t = table
	kui.plugins[name].n = name
	
	return kui.plugins[name]
end

-- return a plugin's table
function kui:getPlugin(name)
	if not name then
		kf.kui:print('attempted to get nil plugin')
		return
	end

	if kui.plugins[name] then
		return kui.plugins[name].t
	else
		kf.kui:print('attempted to get non-existing plugin `' .. name .. '`')
		return
	end
end