local _, ns = ...
local kpf, kf = ns.kpf, ns.kf
--- event handler helper ---------------------------------------------------
kui.events = {}

-- args: event[, function]
-- if a function is given it will be called instead of the named table value
-- it must accept the arguments: event, ...
function kpf:addEvent(e, f)
	if not f and not self.t[e] then
		kf.kui:print('no event handler exists for `' .. e .. '` in plugin `' .. self.n .. '`')
		return
	end

	if kui.events[e] then
		kui.events[e][self.n] = f or true
	else
		kui.events[e] = {
			[self.n] = f or true
		}
	end
	
	if not kf:IsEventRegistered(e) then
		kf:RegisterEvent(e)
	end
end

function kpf:removeEvent(e)
	if kui.events[e] then
		kui.events[e][self.n] = nil
		
		if #kui.events[e] == 0 then
			kf:UnregisterEvent(e)
		end
	end	
end

kf:SetScript('OnEvent', function(self, event, ...)
	if not kui.events[event] then return end
	
	for pn, enabled in pairs(kui.events[event]) do
		p = kui:getPlugin(pn)
	
		if (p[event] and enabled) or (type(enabled) == 'function') then
			if event ~= 'ADDON_LOADED' or (event == 'ADDON_LOADED' and ... == pn) then
				-- if event is addon_loaded, only run this if it is called
				-- for this particular addon (as always).
				if type(enabled) == 'function' then
					-- call the registered function
					enabled(event, ...)
				else
					p[event](p, ...)
				end
			end
		end
	end
end)