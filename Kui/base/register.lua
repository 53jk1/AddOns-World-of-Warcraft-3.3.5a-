local addon, ns = ...
local kf = ns.kf
--- finishing up ---------------------------------------------------------------
kf.Slash = function(msg, editbox)
	ReloadUI()
end

--- register it as a plugin of itself?
kf.kui = kui:addPlugin(addon, kf)
kf.kui:addSlash('RELOADUI', 'rl')