local _, ns = ...
local kpf, kf = ns.kpf, ns.kf
--- periodic tasks helper --------------------------------------------------
kui.tasks = {}

function kpf:addTask(interval)
	if not self.t.OnUpdate then
		kf.kui:print('no OnUpdate handler exists in plugin `' .. self.n .. '`')
		return
	end

	kui.tasks[self.n] = { i = interval, e = 0 }
end

function kpf:removeTask()
	kui.tasks[self.n] = nil
end

kf.elapsed = 0
kf:SetScript('OnUpdate', function(self, e)
	local p, t, pn
	self.elapsed = self.elapsed + e	
	
	if self.elapsed >= .1 then
		for pn, t in pairs(kui.tasks) do
			p = kui:getPlugin(pn)
		
			if p and p.OnUpdate then
				t.e = t.e + e
				
				if t.i == .1 or t.e >= t.i then
					-- (as .1 is the smallest possible, it needs to be synced)
					p:OnUpdate()
					t.e = 0
				end
			end
		end
		
		self.elapsed = 0
	end
end)