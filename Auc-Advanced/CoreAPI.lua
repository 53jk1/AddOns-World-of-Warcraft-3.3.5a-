--[[
	Auctioneer Advanced
	Version: 5.12.5198 (QuirkyKiwi)
	Revision: $Id: CoreAPI.lua 5184 2011-06-24 00:16:48Z Nechckn $
	URL: http://auctioneeraddon.com/

	This is an addon for World of Warcraft that adds statistical history to the auction data that is collected
	when the auction is scanned, so that you can easily determine what price
	you will be able to sell an item for at auction or at a vendor whenever you
	mouse-over an item in the game

	License:
		This program is free software; you can redistribute it and/or
		modify it under the terms of the GNU General Public License
		as published by the Free Software Foundation; either version 2
		of the License, or (at your option) any later version.

		This program is distributed in the hope that it will be useful,
		but WITHOUT ANY WARRANTY; without even the implied warranty of
		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
		GNU General Public License for more details.

		You should have received a copy of the GNU General Public License
		along with this program(see GPL.txt); if not, write to the Free Software
		Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

	Note:
		This AddOn's source code is specifically designed to work with
		World of Warcraft's interpreted AddOn system.
		You have an implicit license to use this AddOn with these facilities
		since that is its designated purpose as per:
		http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
]]
if not AucAdvanced then return end
local AucAdvanced = AucAdvanced
local coremodule, internal = AucAdvanced.GetCoreModule("CoreAPI")
if not (coremodule and internal) then return end -- Someone has explicitely broken us


AucAdvanced.API = {}
local lib = AucAdvanced.API
local private = {}
internal.API = {}
local libinternal = internal.API

lib.Print = AucAdvanced.Print
local Const = AucAdvanced.Const
local GetFaction = AucAdvanced.GetFaction
local GetSetting = AucAdvanced.Settings.GetSetting
local DecodeLink = AucAdvanced.DecodeLink
local SanitizeLink = AucAdvanced.SanitizeLink
local debugPrint = AucAdvanced.Debug.DebugPrint

local tinsert = table.insert
local tremove = table.remove
local next,pairs,ipairs,type = next,pairs,ipairs,type
local wipe = wipe
local ceil,floor,max,abs = ceil,floor,max,abs
local tostring,tonumber,strjoin,strsplit,format = tostring,tonumber,strjoin,strsplit,format
local GetItemInfo = GetItemInfo
local time = time
local bitand = bit.band
-- GLOBALS: nLog, N_NOTICE, N_WARNING, N_ERROR


coremodule.Processors = {}
function coremodule.Processors.scanstats()
	lib.ClearMarketCache()
end
function coremodule.Processors.configchanged(...)
	lib.ClearMarketCache()
	private.ResetMatchers(...)
end
function coremodule.Processors.newmodule()
	private.ClearEngineCache()
	lib.ClearMarketCache()
	private.ResetMatchers()
end

do
    local EPSILON = 0.000001;
    local IMPROVEMENT_FACTOR = 0.8;
    local CORRECTION_FACTOR = 1000; -- 10 silver per gold, integration steps at tail
    local FALLBACK_ERROR = 1;       -- 1 silver per gold fallback error max

	-- cache[serverKey][itemsig]={value, seen, #stats}
    local cache = setmetatable({}, { __index = function(tbl,key)
			tbl[key] = {}
			return tbl[key]
		end
	})
    local pdfList = {};
    local engines = {};
    local ERROR = 0.05;
    -- local LOWER_INT_LIMIT, HIGHER_INT_LIMIT = -100000, 10000000;
    --[[
        This function acquires the current market value of the mentioned item using
        a configurable algorithm to process the data used by the other installed
        algorithms.

        The returned value is the most probable value that the item is worth
        using the algorithms in each of the STAT modules as specified
        by the GetItemPDF() function.

        AucAdvanced.API.GetMarketValue(itemLink, serverKey)
    ]]
    function lib.GetMarketValue(itemLink, serverKey)
        local _;
        if type(itemLink) == 'number' then _, itemLink = GetItemInfo(itemLink) end
		if not itemLink then return end

		local cacheSig = lib.GetSigFromLink(itemLink)
		if not cacheSig then return end -- not a valid item link
		serverKey = serverKey or GetFaction() -- call GetFaction once here, instead of in every Stat module

        local cacheEntry = cache[serverKey][cacheSig]
        if cacheEntry then
            return cacheEntry[1], cacheEntry[2], cacheEntry[3] -- explicit indexing faster than 'unpack' for 3 values
        end

        ERROR = GetSetting("core.marketvalue.tolerance");
        local saneLink = SanitizeLink(itemLink)

        local upperLimit, lowerLimit, seen = 0, 1e11, 0;

        if #engines == 0 then
            -- Rebuild the engine cache
            local modules = AucAdvanced.GetAllModules(nil, "Stat")
            for pos, engineLib in ipairs(modules) do
                local fn = engineLib.GetItemPDF;
                if fn then
                    tinsert(engines, {pdf = fn, array = engineLib.GetPriceArray});
                elseif nLog then
                    nLog.AddMessage("Auctioneer", "Market Pricing", N_WARNING, "Missing PDF", "Auctioneer engine '"..engineLib.GetName().."' does not have a GetItemPDF() function. This check will be removed in the near future in favor of faster calls. Implement this function.");
                end
            end
        end

        -- Run through all of the stat modules and get the PDFs
        local c, oldPdfMax, total = 0, #pdfList, 0;
        local convergedFallback = nil;
        for _, engine in ipairs(engines) do
            local i, min, max, area = engine.pdf(saneLink, serverKey);

            if type(i) == 'number' then
                -- This is a fallback
                if convergedFallback == nil or (type(convergedFallback) == 'number' and abs(convergedFallback - i) < FALLBACK_ERROR * convergedFallback / 10000) then
                    convergedFallback = i;
                else
                    convergedFallback = false;      -- Cannot converge on fallback pricing
                end
            end

            local priceArray = engine.array(saneLink, serverKey);

            if priceArray and (priceArray.seen or 0) > seen then
                seen = priceArray.seen;
            end

            if i and type(i) ~= 'number' then   -- pdfList[++c] = i;
                total = total + (area or 1);                                -- Add total area, assume 1 if not supplied
                c = c + 1;
                pdfList[c] =  i;
                if min < lowerLimit then lowerLimit = min; end
                if max > upperLimit then upperLimit = max; end
            end
        end

        -- Clean out extras if needed
        for i = c+1, oldPdfMax do
            pdfList[i] = nil;
        end

        if #pdfList == 0 and convergedFallback then
            if nLog then nLog.AddMessage("Auctioneer", "Market Pricing", N_WARNING, "Fallback Pricing Used", "Fallback pricing used due to no available PDFs on item "..itemLink); end
            return convergedFallback, 1, 1;
        end


        if not (lowerLimit > -1/0 and upperLimit < 1/0) then
			error("Invalid bounds detected while pricing "..(GetItemInfo(itemLink) or itemLink)..": "..tostring(lowerLimit).." to "..tostring(upperLimit))
		end


        -- Determine the totals from the PDFs
        local delta = (upperLimit - lowerLimit) * .01;

        if #pdfList == 0 or delta < EPSILON or total < EPSILON then
            return;                 -- No PDFs available for this item
        end

        local limit = total/2;
        local midpoint, lastMidpoint = 0, 0;

        -- Now find the 50% point
        repeat
            lastMidpoint = midpoint;
            total = 0;

            if not(delta > 0) then
				error("Infinite loop detected during market pricing for "..(GetItemInfo(itemLink) or itemLink))
			end

            for x = lowerLimit, upperLimit, delta do
                for i = 1, #pdfList do
                    local val = pdfList[i](x);
                    total = total + val * delta;
                end

                if total > limit then
                    midpoint = x;
                    break;
                end
            end

            delta = delta * IMPROVEMENT_FACTOR;


            if midpoint ~= midpoint or midpoint == 0 then
                if nLog and midpoint ~= midpoint then
                    nLog.AddMessage("Auctioneer", "Market Pricing", N_WARNING, "Unable To Calculate", "A NaN value was detected while processing the midpoint for PDF of "..(GetItemInfo(itemLink) or itemLink).."... Giving up.");
                elseif nLog then
                    nLog.AddMessage("Auctioneer", "Market Pricing", N_NOTICE, "Unable To Calculate", "A zero total was detected while processing the midpoint for PDF of "..(GetItemInfo(itemLink) or itemLink).."... Giving up.");
                end

                if convergedFallback then
                    if nLog then
                        nLog.AddMessage("Auctioneer", "Market Pricing", N_WARNING, "Fallback Pricing Used", "Fallback pricing used due to NaN/Zero total for item "..itemLink);
                    end
                    return convergedFallback, 1, 1;
                end
                return;                 -- Cannot calculate: NaN
            end

        until abs(midpoint - lastMidpoint)/midpoint < ERROR;

        if midpoint and midpoint > 0 then
            midpoint = floor(midpoint + 0.5);   -- Round to nearest copper

            -- Cache before finishing up
			cache[serverKey][cacheSig] = {midpoint, seen, #pdfList}

            return midpoint, seen, #pdfList;
        else
            if nLog then
                nLog.AddMessage("Auctioneer", "Market Pricing", N_WARNING, "Unable To Calculate", "No midpoint was detected for item "..(GetItemInfo(itemLink) or itemLink).."... Giving up.");
            end
            return;
        end

    end

	-- Clear the cache of Stats engines (called if a new module is registered)
	function private.ClearEngineCache()
		wipe(engines)
	end

    -- Clears the results cache for AucAdvanced.API.GetMarketValue()
    function lib.ClearMarketCache()
		wipe(cache)
    end
end

function lib.ClearItem(itemLink, serverKey)
	local saneLink = SanitizeLink(itemLink)
	local modules = AucAdvanced.GetAllModules("ClearItem")
	for pos, engineLib in ipairs(modules) do
		engineLib.ClearItem(saneLink, serverKey)
	end
	lib.ClearMarketCache()
end

--[[ AucAdvanced.API.IsKeyword(testword [, keyword])
	Determine whether testword is equal to or an alias of keyword
	Returns the keyword if it matches, nil otherwise
	For case-insensitive keywords, tries both unmodified and lowercase
	Note: default cases must be handled separately
--]]
do
	-- allowable keywords (so far): ALL, faction, server
	local keywords = { -- entry: alias = keyword,
		ALL = "ALL",
		faction = "faction",
		server = "server",
		realm = "server",
	}
	-- todo: functions to add new keywords, and to add new aliases for keywords
	function lib.IsKeyword(testword, keyword)
		if type(testword) ~= "string" then return end
		local key = keywords[testword] or keywords[testword:lower()] -- try unmodified and lowercased
		if key then
			if not keyword or keyword == key then
				return key
			end
		end
	end
end

function lib.ClearData(command)
	local serverKey1, serverKey2, serverKey3

	-- split command into keyword and extra parts
	local keyword, extra = "faction", "" -- default
	if type(command) == "string" then
		local _, ind, key = strfind(command, "(%S+)")
		if key then
			key = lib.IsKeyword(key)
			if key then
				keyword = key -- recognised keyword
				extra = strtrim(strsub(command, ind+1))
			else
				extra = strtrim(command) -- try to resolve whole command (as a "faction")
			end
		end
	elseif command then -- only valid types are string or nil
		error("Unrecognised parameter type to ClearData: "..type(command)..":"..tostring(command))
	end

	-- At this point keyword should be one of the strings in the following if-block
	-- extra should be a string, where 'no extra information' is denoted by ""
	if keyword == "ALL" then
		if extra == "" then serverKey1 = "ALL" end
	elseif keyword == "server" then
		if extra == "" then extra = Const.PlayerRealm end
		-- otherwise assume the user typed the server name correctly
		-- modules should silently ignore unrecognised serverKeys
		serverKey1 = extra.."-Alliance"
		serverKey2 = extra.."-Horde"
		serverKey3 = extra.."-Neutral"
	elseif keyword == "faction" then
		if extra == "" then
			serverKey1 = GetFaction()
		elseif AucAdvanced.SplitServerKey(extra) then -- it's a valid serverKey
			serverKey1 = extra
		else
			local fac = AucAdvanced.IsFaction(extra) -- it's a valid faction group
			if fac then
				serverKey1 = Const.PlayerRealm.."-"..fac
			end
		end
	end

	if serverKey1 then
		local modules = AucAdvanced.GetAllModules("ClearData")
		for pos, lib in ipairs(modules) do
			lib.ClearData(serverKey1)
			if serverKey2 then
				lib.ClearData(serverKey2)
				lib.ClearData(serverKey3)
			end
		end
		lib.ClearMarketCache()
	else
		lib.Print("Auctioneer: Unrecognized keyword or faction for ClearData {{"..command.."}}")
	end
end


function lib.GetAlgorithms(itemLink)
	local saneLink = SanitizeLink(itemLink)
	local engines = {}
	local modules = AucAdvanced.GetAllModules()
	for pos, engineLib in ipairs(modules) do
		if engineLib.GetPrice or engineLib.GetPriceArray then
			if not engineLib.IsValidAlgorithm
			or engineLib.IsValidAlgorithm(saneLink) then
				local engine = engineLib.GetName()
				tinsert(engines, engine)
			end
		end
	end
	return engines
end

function lib.IsValidAlgorithm(algorithm, itemLink)
	local saneLink = SanitizeLink(itemLink)
	local modules = AucAdvanced.GetAllModules()
	for pos, engineLib in ipairs(modules) do
		if engineLib.GetName() == algorithm and (engineLib.GetPrice or engineLib.GetPriceArray) then
			if engineLib.IsValidAlgorithm then
				return engineLib.IsValidAlgorithm(saneLink)
			end
			return true
		end
	end
	return false
end

--store the last data request and just return a cache value for the next 5 secs (5 secs is just arbitrary)
local LastAlgorithmSig, LastAlgorithmTime, LastAlgorithmPrice, LastAlgorithmSeen, LastAlgorithmArray
function lib.GetAlgorithmValue(algorithm, itemLink, serverKey, reserved)
	if (not algorithm) then
		if nLog then nLog.AddMessage("Auctioneer", "API", N_ERROR, "Incorrect Usage", "No pricing algorithm supplied to GetAlgorithmValue") end
		return
	end
	if type(itemLink) == "number" then
		local _
		_, itemLink = GetItemInfo(itemLink)
	end
	if (not itemLink) then
		if nLog then nLog.AddMessage("Auctioneer", "API", N_ERROR, "Incorrect Usage", "No itemLink supplied to GetAlgorithmValue") end
		return
	end

	if reserved then
		lib.ShowDeprecationAlert("AucAdvanced.API.GetAlgorithmValue(algorithm, itemLink, serverKey)",
		"The 'faction' and 'realm' parameters are deprecated in favor of the new 'serverKey' parameter. Use this instead."
		);

		serverKey = reserved.."-"..serverKey;
	end
	serverKey = serverKey or GetFaction()

	local saneLink = SanitizeLink(itemLink)
	--check if this was just retrieved and return that value
	local algosig = strjoin(":", algorithm, saneLink, serverKey)
	if algosig == LastAlgorithmSig and LastAlgorithmTime + 5 > time() then
		return LastAlgorithmPrice, LastAlgorithmSeen, LastAlgorithmArray
	end

	local modules = AucAdvanced.GetAllModules()
	for pos, engineLib in ipairs(modules) do
		if engineLib.GetName() == algorithm and (engineLib.GetPrice or engineLib.GetPriceArray) then
			if engineLib.IsValidAlgorithm
			and not engineLib.IsValidAlgorithm(saneLink) then
				return
			end

			local price, seen, array
			if (engineLib.GetPriceArray) then
				array = engineLib.GetPriceArray(saneLink, serverKey)
				if (array) then
					price = array.price
					seen = array.seen
				end
			else
				price = engineLib.GetPrice(saneLink, serverKey)
			end
			LastAlgorithmSig = algosig
			LastAlgorithmTime = time()
			LastAlgorithmPrice, LastAlgorithmSeen, LastAlgorithmArray = price, seen, array
			return price, seen, array
		end
	end
	--error(("Cannot find pricing algorithm: %s"):format(algorithm))
	return
end

--[[ resultsTable = AucAdvanced.API.QueryImage(queryTable, serverKey, reserved, ...)
	'queryTable' specifies the query to perform
	'serverKey' defaults to the current faction
	'reserved' must always be nil
	The working code can be viewed in CoreScan.lua for more details.
--]]
lib.QueryImage = AucAdvanced.Scan.QueryImage

-- unpackedTable = AucAdvanced.API.UnpackImageItem(imageItem)
-- imageItem is one of the values (subtables) in the table returned by QueryImage or GetImageCopy
lib.UnpackImageItem = AucAdvanced.Scan.UnpackImageItem

-- scanStatsTable = AucAdvanced.API.GetScanStats(serverKey)
-- Timestamps: scanstats.LastScan, scanstats.LastFullScan, scanstats.ImageUpdated
-- Scan statistics subtables: scanstats[0] (last scan), scanstats[1], scanstats[2] (two scans prior to last scan)
lib.GetScanStats = AucAdvanced.Scan.GetScanStats

-- imageTable = AucAdvanced.API.GetImageCopy(serverKey)
-- Generates an independent copy of the current scan data image for the specified serverKey
lib.GetImageCopy = AucAdvanced.Scan.GetImageCopy

function lib.ListUpdate()
	if lib.IsBlocked() then return end
	AucAdvanced.SendProcessorMessage("listupdate")
end

function lib.BlockUpdate(block, propagate)
	local blocked
	if block == true then
		blocked = true
		private.isBlocked = true
		AuctionFrameBrowse:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	else
		blocked = false
		private.isBlocked = nil
		AuctionFrameBrowse:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	end

	if (propagate) then
		AucAdvanced.SendProcessorMessage("blockupdate", blocked)
	end
end

function lib.IsBlocked()
	return private.isBlocked == true
end


--[[Progress bars that are usable by any addon.
name = string - unique bar name
value =  0-100   the % the bar should be filled
show =  boolean  true will keep bar displayed, false will hide the bar and free it for use by another addon
text =  string - the text to display on the bar
options = table containing formatting commands.
	options.barColor = { R,G,B, A}   red, green, blue, alpha values.
	options.textColor = { R,G,B, A}   red, green, blue, alpha values.

value, text, color, and options are all optional variables
]]
local ProgressBarFrames = {}
local ActiveProgressBars = {}
-- generate new bars as needed
local function newBar()
	local bar = CreateFrame("STATUSBAR", nil, UIParent, "TextStatusBar")
	bar:SetWidth(300)
	bar:SetHeight(18)
	bar:SetBackdrop({
				bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
				tile=1, tileSize=10, edgeSize=10,
				insets={left=1, right=1, top=1, bottom=1}
			})

	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.6,0,0,0.6)
	bar:SetMinMaxValues(0,100)
	bar:SetValue(50)
	bar:Hide()

	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bar.text:SetPoint("CENTER", bar, "CENTER")
	bar.text:SetJustifyH("CENTER")
	bar.text:SetJustifyV("CENTER")
	bar.text:SetTextColor(1,1,1)

	tinsert(ProgressBarFrames, bar)
	local newID = #ProgressBarFrames

	if newID > 1 then
		-- attach to previous bar
		bar:SetPoint("BOTTOM", ProgressBarFrames[newID-1], "TOP", 0, 0)
	end
	return newID
end
-- create 1 bar to start for anchoring
newBar()
-- handles the rendering
local function renderBars(ID, name, value, text, options)
	local self = ProgressBarFrames[ID]
	if not self then assert("No bar found available for ID", ID, name, text) end

	-- reset bars that are not in use to defaults
	if self and not name then
		self:Hide()
		self.text:SetText("")
		self:SetStatusBarColor(0.6, 0, 0, 0.6) --light red color
		self.text:SetTextColor(1, 1, 1, 1)
		return
	end

	self:Show()
	--update progress
	if value then
		self:SetValue(value)
	end
	--change bars text if desired
	if text then
		self.text:SetText(text)
	end
	--[[options is a table that contains, "tweaks" ie text or bar color changes
	Nothing below this line will be processed unless an options table is passed]]
	if not options then return end

	--change bars color
	local barColor = options.barColor
	if barColor then
		local r, g, b, a = barColor[1],barColor[2], barColor[3], barColor[4]
		if r and g and b then
			a = a or 0.6
			self:SetStatusBarColor(r, g, b, a)
		end
	end
	--change text color
	local textColor = options.textColor
	if textColor then
		local r, g, b, a = textColor[1],textColor[2], textColor[3], textColor[4]
		if r and g and b then
			a = a or 1
			self.text:SetTextColor(r, g, b, a)
		end
	end
end
--main entry point. Handles which bar will be assigned and recycling bars
function lib.ProgressBars(name, value, show, text, options)
	-- reanchor first bar so we can display even if AH is closed
	if AuctionFrame and AuctionFrame:IsShown() then
		ProgressBarFrames[1]:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -5, 5)
	else
		ProgressBarFrames[1]:SetPoint("CENTER", UIParent, "CENTER", -5,5)
	end

	if type(name) ~= "string" then return end
	if value and type(value) ~= "number" then return end
	if options and type(options) ~= "table" then options = nil end

	local ID = ActiveProgressBars[name]
	if show then
		if ID then -- this is a live bar; update the data table
			local barData = ActiveProgressBars[ID]
			assert(barData[1] == name) -- ### debug
			if value then barData[2] = value end
			if text then barData[3] = text end
			if options then barData[4] = options end
		else -- initialize data table for new bar
			-- get an available bar
			local test = #ActiveProgressBars + 1
			if ProgressBarFrames[test] then
				ID = test
			else
				ID = newBar()
			end
			ActiveProgressBars[ID] = {name, value, text, options}
			ActiveProgressBars[name] = ID
		end
		renderBars(ID, name, value, text, options)
	elseif ID then
		tremove(ActiveProgressBars, ID)
		ActiveProgressBars[name] = nil
		-- move down and re-render higher bars
		for renderID = 1, #ActiveProgressBars + 1 do
			-- first reset/hide every bar
			renderBars(renderID)
			-- then if it is in use re-render from the data table
			local barData = ActiveProgressBars[renderID]
			if barData then
				ActiveProgressBars[barData[1]] = renderID -- update 'name' lookup entry
				renderBars(renderID, barData[1], barData[2], barData[3], barData[4])
			end
		end
	end
end

--[[ Market matcher APIs ]]--

local matcherCurList
local matcherNameLookup
local matcherOrderedEngines
local matcherDropdown
local matcherSelected = 1
function private.ResetMatchers(event, setting)
	if not setting or setting:sub(1, 7) == "profile" then
		matcherCurList = nil
		matcherNameLookup = nil
		matcherOrderedEngines = nil
		matcherDropdown = nil
	end
end

local function RebuildMatcherListLookup()
	matcherCurList = GetSetting("core.matcher.matcherlist")
	if not matcherCurList then
		matcherCurList = {}

		-- Caution: may trigger a call to GetMatcherDropdownList. todo: handle any resulting function re-entry better
		AucAdvanced.Settings.SetSetting("core.matcher.matcherlist", matcherCurList)
	end
	local modules = AucAdvanced.GetAllModules(nil, "Match")
	matcherNameLookup = {}
	for index, engine in ipairs(modules) do
		local name = engine.GetName()
		if type(engine.GetMatchArray) == "function" then
			matcherNameLookup[name] = engine
			local insert = true
			for _, listName in ipairs(matcherCurList) do
				if listName == name then
					insert = false
					break
				end
			end
			if insert then
				AucAdvanced.Print("Auctioneer: New matcher found: "..name)
				tinsert(matcherCurList, 1, name)
			end
		else
			debugPrint("Auctioneer engine '"..name.."' does not have a GetMatchArray() function.", "CoreAPI", "Missing GetMatchArray", "Warning")
		end
	end
end

local function GetMatcherList()
	if not matcherCurList then
		RebuildMatcherListLookup()
	end
	return matcherCurList
end

local function GetMatcherLookup()
	if not matcherNameLookup then
		RebuildMatcherListLookup()
	end
	return matcherNameLookup
end

local function GetMatcherEngines()
	if not matcherOrderedEngines then
		local lookup = GetMatcherLookup()
		local matcherlist = GetMatcherList()
		matcherOrderedEngines = {}
		for index, name in ipairs(matcherlist) do
			local engine = lookup[name]
			if engine then
				tinsert(matcherOrderedEngines, engine)
			end
		end
	end
	return matcherOrderedEngines
end

-- Matcher functions used by CoreSettings for Matcher dropdown list

function libinternal.GetMatcherDropdownList()
	if not matcherDropdown then
		local matcherlist = GetMatcherList()
		matcherDropdown = {}
		for index, name in ipairs(matcherlist) do
			tinsert(matcherDropdown, {index, index..": "..name})
		end
	end
	return matcherDropdown
end

function libinternal.MatcherSetter(setting, value)
	local matcherlist = GetSetting("core.matcher.matcherlist") -- work from the actual saved setting, not matcherCurList (which has probably been reset)
	if not matcherlist then return end
	if setting == "matcher.select" then
		if type(value) == "number" and value >= 1 and value <= #matcherlist then
			matcherSelected = value
			return true
		end
	end
	if not matcherlist[matcherSelected] then
		matcherSelected = 1
		return
	end
	private.ResetMatchers()
	if setting == "matcher.up" then
		local newpos = matcherSelected - 1
		if newpos >= 1 then
			matcherlist[newpos], matcherlist[matcherSelected] = matcherlist[matcherSelected], matcherlist[newpos]
			matcherSelected = newpos
			return true
		end
	elseif setting == "matcher.down" then
		local newpos = matcherSelected + 1
		if newpos <= #matcherlist then
			matcherlist[newpos], matcherlist[matcherSelected] = matcherlist[matcherSelected], matcherlist[newpos]
			matcherSelected = newpos
			return true
		end
	elseif setting == "matcher.delete" then
		tremove(matcherlist, matcherSelected)
		local n = #matcherlist
		if n > 0 and matcherSelected > n then
			matcherSelected = n
		end
		return true
	end
end

function libinternal.MatcherGetter(setting)
	if setting == "matcher.select" then
		return matcherSelected
	end
end

--[[ GetBestMatch(link, algorithm, serverKey)
	Determine base price from algorithm, then pass through all matchers to get the matched price
	Parameters:
		link: full (hyperlink-style) itemLink
		algorithm: "market" or price<number> or algorithm<string, as used by GetAlgorithmVale>
		serverKey: optional serverKey
	Returns:
		price: final price after all matching
		nil: (obsolete)
		count: number of matchers contributing an adjustment to the price
		diff: averaged difference from original price. todo: is performing an average here appropriate?
		matchString: formatted string (including '\n' characters) describing what the matchers have done
--]]
function lib.GetBestMatch(itemLink, algorithm, serverKey)
	local price
	local saneLink = SanitizeLink(itemLink)
	if algorithm == "market" then
		price = lib.GetMarketValue(saneLink, serverKey)
	elseif type(algorithm) == "number" then
		price = algorithm
	else
		price = lib.GetAlgorithmValue(algorithm, saneLink, serverKey)
	end
	if not price then return end

	local matchers = GetMatcherEngines()
	local originalPrice = price
	local count, infoString = 0, ""

	for index = 1, #matchers do
		local matcher = matchers[index]
		local matchArray = matcher.GetMatchArray(saneLink, price, serverKey, originalPrice)
		if matchArray then
			price = matchArray.value
			count = count + 1
			if matchArray.returnstring then
				infoString = infoString.."\n"..matchArray.returnstring -- using two .. is faster than calling strjoin
			end
		end
	end

	if price > 0 then
		return price, nil, count, price - originalPrice, infoString
	end
end

-- Returns the number of installed matchers
-- Normally only used to check if number of matchers is > 0
-- Note: count will include matchers that are installed but disabled
function lib.GetNumMatchers()
	return #(GetMatcherEngines())
end

-- Additional Matcher functions for compatibility

-- Returns an ordered list of matcher names
-- Matchers are installed, and if itemLink was provided, are valid for that item
-- Note: matchers may not be enabled, or may not actually have data for that item
function lib.GetMatchers(itemLink)
	local saneLink = SanitizeLink(itemLink)
	local matchers = GetMatcherEngines()
	local retlist = {}
	for index, matcher in ipairs(matchers) do
		if not saneLink or not matcher.IsValidMatcher or matcher.IsValidMatcher(saneLink) then
			tinsert(retlist, matcher.GetName())
		end
	end
	return retlist
end

-- Checks that the itemLink is valid for the specified matcher
-- Obsolete, as all matchers should return nil from GetMatchArray if they cannot handle the item
-- However may still be useful for external modules to obtain a matcher lib from the name
function lib.IsValidMatcher(matcher, itemLink)
	if type(matcher) == "table" then -- if provided with a table, get the name
		matcher = matcher.GetName and matcher.GetName()
	end
	matcher = GetMatcherLookup()[matcher] -- validate name and get the matcher lib
	if not matcher then return end
	local saneLink = SanitizeLink(itemLink)
	if not saneLink or not matcher.IsValidMatcher or matcher.IsValidMatcher(saneLink) then
		return matcher
	end
end

-- Allows external modules to request individual matcher values using matcher's name
function lib.GetMatcherValue(matcher, itemLink, price, serverKey, originalPrice)
	if type(matcher) == "table" then
		matcher = matcher.GetName and matcher.GetName()
	end
	matcher = GetMatcherLookup()[matcher]
	if not matcher then return end
	local saneLink = SanitizeLink(itemLink)
	local matchArray = matcher.GetMatchArray(saneLink, price, serverKey, originalPrice)
	if not matchArray then
		matchArray = {
			value = price,
			diff = 0,
		}
	end
	return matchArray.value, matchArray
end


-- Signature conversion functions

-- Creates an AucAdvanced signature from an item link
function lib.GetSigFromLink(link)
	local ptype = type(link)
	if ptype == "number" then
		return ("%d"):format(link)
	elseif ptype ~= "string" then
		return
	end
	local lType,id,enchant,gem1,gem2,gem3,gemBonus,suffix,seed = strsplit(":", link)
	if not id or lType:sub(-4) ~= "item" then
		return
	end

	if suffix and suffix ~= "0" then
		local factor = "0"
		if suffix:byte(1) == 45 then -- look for '-' to see if it is a negative number
			local nseed = tonumber(seed)
			if nseed then
				factor = ("%d"):format(bitand(nseed, 65535)) -- here format is faster than tostring
			end
		end
		if enchant and enchant ~= "0" then
			-- concat is slightly faster than using strjoin with this many parameters, and far faster than format
			return id..":"..suffix..":"..factor..":"..enchant
		elseif factor ~= "0" then
			return id..":"..suffix..":"..factor
		else
			return id..":"..suffix
		end
	else
		if enchant and enchant ~= "0" then
			return id..":0:0:"..enchant
		else
			return id
		end
	end
end

-- Creates an item link from an AucAdvanced signature
function lib.GetLinkFromSig(sig)
	local id, suffix, factor, enchant = strsplit(":", sig)
	local itemstring = format("item:%s:%s:0:0:0:0:%s:%s:80:0", id, enchant or "0", suffix or "0", factor or "0")
	local name, link = GetItemInfo(itemstring)
	if link then
		return SanitizeLink(link), name -- name is ignored by most calls
	end
end

-- Decodes an AucAdvanced signature into numerical values
-- Can be compared to the return values from DecodeLink
function lib.DecodeSig(sig)
	if type(sig) ~= "string" then return end
	local id, suffix, factor, enchant = strsplit(":", sig)
	id = tonumber(id)
	if not id or id == 0 then return end
	suffix = tonumber(suffix) or 0
	factor = tonumber(factor) or 0
	enchant = tonumber(enchant) or 0
	return id, suffix, factor, enchant
end

-- A Short Sig is the same format as a normal Sig, but contains at most 3 fields - ID:Suffix:Factor
-- the functions GetLinkFromSig and DecodeSig will still work on a SSig
-- Used by Stat modules for storage/packing of saved data
-- for speed we assume that link has already been verified as a valid item link
function lib.GetShortSigFromLink(link)
	local lType,id,enchant,gem1,gem2,gem3,gemBonus,suffix,seed = strsplit(":", link)
	if suffix and suffix ~= "0" then
		if suffix:byte(1) == 45 then -- look for '-' to see if it is a negative number
			local nseed = tonumber(seed)
			if nseed then
				local nfactor = bitand(nseed, 65535)
				if nfactor ~= 0 then
					-- the following construction appears to be faster
					-- than just using a single, more complicated, format call
					return id..":"..suffix..":"..format("%d", nfactor)
				end
			end
		end
		return id..":"..suffix
	end
	return id
end

function lib.SigToShortSig(sig)
	-- strip off enchant field, then strip off any trailing "0"
	local id, suffix, factor, enchant = strsplit(sig)
	if not enchant then -- already in ssig format
		return sig
	end
	if factor and factor ~= "0" then
		return id..":"..suffix..":"..factor
	elseif suffix and suffix ~= "0" then
		return id..":"..suffix
	end
	return id
end

-- Returns id (number), property (string)
-- Used by Stat modules for storage/packing of saved data
-- for speed we assume that link has already been verified as a valid item link
function lib.GetPropertyFromLink(link)
	local lType,id,enchant,gem1,gem2,gem3,gemBonus,suffix,seed = strsplit(":", link)
	id = tonumber(id)
	if suffix and suffix ~= "0" then
		if suffix:byte(1) == 45 then -- look for '-' to see if it is a negative number
			local nseed = tonumber(seed)
			if nseed then
				local nfactor = bitand(nseed, 65535)
				if nfactor ~= 0 then
					return id, suffix.."x"..format("%d", nfactor)
				end
			end
		end
		return id, suffix
	end
	return id, "0"
end

-------------------------------------------------------------------------------
-- Statistical devices created by Matthew 'Shirik' Del Buono
-- For Auctioneer
-------------------------------------------------------------------------------
local sqrtpi = math.sqrt(math.pi);
local sqrtpiinv = 1/sqrtpi;
local sq2pi = math.sqrt(2*math.pi);
local pi = math.pi;
local exp = math.exp;
local bellCurveMeta = {
    __index = {
        SetParameters = function(self, mean, stddev)
            if (stddev == 0) then
                error("Standard deviation cannot be zero");
            elseif (stddev ~= stddev) then
                error("Standard deviation must be a real number");
            end
			if stddev < .1 then --need to prevent obsurdly small stddevs like 1e-11, as they cause freeze-ups
				stddev = .1
			end
            self.mean = mean;
            self.stddev = stddev;
            self.param1 = 1/(stddev*sq2pi);     -- Make __call a little faster where we can
            self.param2 = 2*stddev^2;
        end
    },
    -- Simple bell curve call
    __call = function(self, x)
        local n = self.param1*exp(-(x-self.mean)^2/self.param2);
        -- if n ~= n then
            -- DEFAULT_CHAT_FRAME:AddMessage("-----------------");
            -- DevTools_Dump{param1 = self.param1, param2 = self.param2, x = x, mean = self.mean, stddev = self.stddev, exp = exp(-(x-self.mean)^2/self.param2)};
            -- error(x.." produced NAN ("..tostring(n)..")");
        -- end
        return n;
    end
}
-------------------------------------------------------------------------------
-- Creates a bell curve object that can then be manipulated to pass
-- as a PDF function. This is a recyclable object -- the mean and
-- standard deviation can be updated as necessary so that it does not have
-- to be regenerated
--
-- Note: This creates a bell curve with a standard deviation of 1 and
-- mean of 0. You will probably want to update it to your own desired
-- values by calling return:SetParameters(mean, stddev)
-------------------------------------------------------------------------------
function lib.GenerateBellCurve()
    return setmetatable({mean=0, stddev=1, param1=sqrtpiinv, param2=2}, bellCurveMeta);
end

-- Dumps out market pricing information for debugging. Only handles bell curves for now.
function lib.DumpMarketPrice(itemLink, serverKey)
	local modules = AucAdvanced.GetAllModules(nil, "Stat");
	for pos, engineLib in ipairs(modules) do
		local success, result = pcall(engineLib.GetItemPDF, itemLink, serverKey);
		if success then
			if getmetatable(result) == bellCurveMeta then
				print(engineLib.GetName() .. ": Mean = " .. result.mean .. ", Standard Deviation = " .. result.stddev);
			else
				print(engineLib.GetName() .. ": Non-Standard PDF: " .. tostring(result));
			end
		else
			print(engineLib.GetName() .. ": Reported error: " .. tostring(result));
		end
	end
end

--[[===========================================================================
--|| Deprecation Alert Functions
--||=========================================================================]]
do
    local SOURCE_PATTERN = "([^\\/:]+:%d+): in function `([^\"']+)[\"']";
    local seenCalls = {};
    local uid = 0;

    -------------------------------------------------------------------------------
    -- Shows a deprecation alert. Indicates that a deprecated function has
    -- been called and provides a stack trace that can be used to help
    -- find the culprit.
    -- @param replacementName (Optional) The displayable name of the replacement function
    -- @param comments (Optional) Any extra text to display
    -------------------------------------------------------------------------------
    function lib.ShowDeprecationAlert(replacementName, comments)
        local caller, source, functionName =
            debugstack(3):match(SOURCE_PATTERN),        -- Keep in mind this will be truncated to only the first in the tuple
            debugstack(2):match(SOURCE_PATTERN);        -- This will give us both the source and the function name

        functionName = functionName .. "()";

        -- Check for this source & caller combination
        seenCalls[source] = seenCalls[source] or {};
        if not seenCalls[source][caller] then
            -- Not warned yet, so warn them!
            seenCalls[source][caller]=true
            -- Display it
            AucAdvanced.Print(
                "Auctioneer: "..
                functionName .. " has been deprecated and was called by |cFF9999FF"..caller:match("^(.+)%.[lLxX][uUmM][aAlL]:").."|r. "..
                (replacementName and ("Please use "..replacementName.." instead. ") or "")..
                (comments or "")
            );
	        geterrorhandler()(
	            "Deprecated function call occurred in Auctioneer API:\n     {{{Deprecated Function:}}} "..functionName..
	                "\n     {{{Source Module:}}} "..source:match("^(.+)%.[lLxX][uUmM][aAlL]:")..
	                "\n     {{{Calling Module:}}} "..caller:match("^(.+)%.[lLxX][uUmM][aAlL]:")..
	                "\n     {{{Available Replacement:}}} "..(replacementName or "None")..
	                (comments and "\n\n"..comments or "")
			)
		end



    end

end

AucAdvanced.RegisterRevision("$URL: http://svn.norganna.org/auctioneer/branches/5.12/Auc-Advanced/CoreAPI.lua $", "$Rev: 5184 $")
