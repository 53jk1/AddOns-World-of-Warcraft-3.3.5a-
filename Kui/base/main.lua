local addon, ns = ...

if kui then
	print('|c9900ff00Kui:|r an addon already possesses a global variable named kui.')
end

kui = {} -- media files/functions unrelated to plugins
--- media / files ----------------------------------------------------------
local media = "Interface\\AddOns\\Kui\\media\\"
kui.m = {
	t = {
		-- borders
		square	= media .. 't\\simpleSquare',
		shadow	= media .. 't\\shadowBorder',
		rounded	= media .. 't\\solidRoundedBorder',
	
		-- textures
		solid		= media .. 't\\solid',
		innerShade	= media .. 't\\innerShade',
		
		-- progress bars
		bar		= media .. 't\\bar',
		sbar	= media .. 't\\barSmall',
	},
	f = {
		accid	= media .. 'f\\accid.ttf',
		yanone	= media .. 'f\\yanone.ttf',
	},
}

--- frame ------------------------------------------------------------------
--- for event/script helpers
local kf = CreateFrame('Frame')

-- plugin functions container (used as metatable)
local kpf = {}
kpf.__index = kpf

function kpf:print(m)
	if type(m) == 'string' then
		print('|cff9900ff' .. (self.n or '[No name]') .. ':|r ' .. m)
	end
end

-- pass kf & kpf
ns.kf, ns.kpf = kf, kpf