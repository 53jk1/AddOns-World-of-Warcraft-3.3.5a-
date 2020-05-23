--[[ DELETE v DELETE v DELETE v DELETE v DELETE v DELETE v DELETE v DELETE --

	NOTE:
	This is an example addon. Use the below code to start your own
	module should you wish.

	This top section should bel deleted from any derivative code
	before you distribute it.

]]

if true then
	 --Comment out this return to see the example module running.
	 return
end

--^ DELETE ^ DELETE ^ DELETE ^ DELETE ^ DELETE ^ DELETE ^ DELETE ^ DELETE ^--

--[[
	Auctioneer - Stat's API Example module
	Version: 5.12.5198 (QuirkyKiwi)
	Revision: $Id: Example.lua 4828 2010-07-21 22:20:18Z Prowell $
	URL: http://auctioneeraddon.com/

	This is an Auctioneer module that does something nifty.

	License:
		This program is free software; you can redistribute it and/or
		modify it under the terms of the GNU General Public License
		as published by the Free Software Foundation; either version 2
		of the License, or (at your option) any later version.

		This program is distributed in the hope that it will be useful,
		but WITHOUT ANY WARRANTY; without even the implied warranty of
		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
		GNU General Public License for more details.

		You should have recenived a copy of the GNU General Public License
		along with this program(see GPL.txt); if not, write to the Free Software
		Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

	Note:
		This AddOn's source code is specifically designed to work with
		World of Warcraft's interpreted AddOn system.
		You have an implicit license to use this AddOn with these facilities
		since that is its designated purpose as per:
		http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
--]]

-- Make sure Auctioneer is loaded.  Especially important if used as an embedded module
-- in a non-auctioneer addon that doesn't require auctioneer (auctioneer is an optional dependency)
if not AucAdvanced then return end

--[[
Convention Used to identify the addon to Auctioneer is a libType and a name.
The name must be unique or else Auctioneer will return nil from NewModule.
Valid libType's are:
	Filter	-- Allows removal of auctions from consideration by Stats modules for statistical use.
	Stat	-- Gathers and reports statistics about items.  The heart of Auctioneer.
	Util	-- This is a catch-all.  A module that doesn't do the additional items of the others.
	Match	-- Module is used by Auctioneer to control pricing (set to some value).
--]]
local libName = "Example"
local libType = "Stat"

local lib,parent,private = AucAdvanced.NewModule(libType, libName)
-- One case where this will happen is if the libType/libName combo has already been registered.
-- in fact, that should be the only case this happens.
if not lib then return end

local print,decode,_,_,replicate,empty,get,set,default,debugPrint,fill = AucAdvanced.GetModuleLocals()

--[[
The following functions are part of the module's exposed methods:
	GetName()         (required) Should return this module's full name
	CommandHandler()  (optional) Slash command handler for this module
	Processor()       (optional) Processes messages sent by Auctioneer
	ScanProcessor()   (optional) Processes items from the scan manager
*	GetPrice()        (required) Returns estimated price for item link
*	GetPriceColumns() (optional) Returns the column names for GetPrice
	OnLoad()          (optional) Receives load message for all modules

	(*) Only implemented in stats modules; util modules do not provide
]]


--[[ 
Function is required in ALL lib's created by AucAdvanced.NewModule
This function should return the full name of this module.
However, NewModule creates a default that returns the libName.
]]
--[[
function lib.GetName()
	return libName
end
]]

--[[
lib.Processor is deprecated.  It will not be called at all if lib.Processors is defined.
Support for this could be removed soon, so don't use in a new routine.
A simple upgrade path for older modules is to 
add a line
lib.Processors.[callbackType] = lib.Processors
for each callbackType.
However, a more efficient method is to create new functions that do only what is needed for
that specific callback type, as some of these callbacks are done very often.
Also, for proper functioning, lib.Processor and/or lib.Processors.[callbackType] functions
must be defined when the addon is registered and must not be added or removed after that point.
Code inside the function must be used if you don't want to handle the message all the time.
]]
function lib.Processor(callbackType, ...)
	if (callbackType == "tooltip") then
		--Called when the tooltip is being drawn.
		lib.ProcessTooltip(...)
	elseif (callbackType == "config") then
		--Called when you should build your Configator tab.
		private.SetupConfigGui(...)
	elseif (callbackType == "listupdate") then
		--Called when the AH Browse screen receives an update.
	elseif (callbackType == "configchanged") then
		--Called when your config options (if Configator) have been changed.
	end
end

lib.Processors = {}
lib.Processors.listupdate = function(callbackType) end
lib.Processors.blockupdate = function(callbackType, blocked) end
lib.Processors.buyqueue = function(callbackType, itemsInQueue) end
-- Note, this returns a string of "<link>;<price>;<count>'
--  it probably should be modified to in the future return callbackType, link, price, count
lib.Processors.bidcancelled = function(callbackType, cancelInfo) end
-- Note, this returns a string of "<link>;<seller>;<count>;<price>;<reason>'
--  it probably should be modified to in the future return callbackType, link, seller, count, price, reason
lib.Processors.bidplaced = function(callbackType, bidInfo) end
-- Expected to be deprecated in the future.  A new processor message SKtooltip is in works, but not yet called.
lib.Processors.tooltip = function(callbackType, tooltip, name, hyperlink, quality, quantity, cost, extra) end
-- Not yet in use.
lib.Processors.SKtooltip = function(callbackType, serverKey, tooltip, name, hyperlink, quality, quantity, cost, extra) end
-- Called every frame while opened?
lib.Processors.auctionui = function(callbackType) end
-- An auctioneer addon has been loaded.
lib.Processors.load = function(callbackType, addon) end
-- Auction UI Opened
lib.Processors.auctionopen = function(callbackType) end
-- Auction UI Closed
lib.Processors.auctionclose = function(callbackType) end
-- Send a message that a module has been added.
lib.Processors.newmodule = function(callbackType) end
-- Indicate post queue has been reduced
lib.Processors.postqueue = function(callbackType, queuelength) end
-- Indicate results of a post attempt
lib.Processors.postresult = function(callbackType, successful, id, request, reason) end
--[[
ToDo: Document these.
These a bit messy.  More docs needed here.
]]
lib.Processors.scanprogress = function(callbackType, state, totalAuctions, scannedAuctions, elapsedTime, page, maxPages, query, scanCount) end
lib.Processors.scanstats = function(callbackType, stats) end
lib.Processors.scanfinish = function(callbackType, scanSizre, querySig, qryInfo, inComplete, curQuery, scanStats) end
-- A query was sent.  via QueryAuctionItems.  Not the ... are the standard return items form QueryAuctionItems.
lib.Processors.querysent = function(callbackType, query, isSearch, ...) end
-- Page Store for page has completed.
lib.Processors.pagefinished = function(callbackType, pageNum) end
lib.Processors.scanstart = function(callbackType, scanSize, querySig, qryInfo) end
lib.Processors.configchanged = function(callbackType, setting, value) end
-- Request for config screen gui elements.  gui references the config screen GUI.
lib.Processors.config = function(callbackType, gui) end
lib.Processors.searchbegin = function(callbackType, searcherName) end
lib.Processors.searchcomplete = function(callbackType, searcherName) end

-- ToDo: figure out what events there are, and document them.



function lib.ProcessTooltip(frame, name, hyperlink, quality, quantity, cost, additional)
	-- In this function, you are afforded the opportunity to add data to the tooltip should you so
	-- desire. You are passed a hyperlink, and it's up to you to determine whether or what you should
	-- display in the tooltip.
end

function lib.OnLoad()
	--This function is called when your variables have been loaded.
	--You should also set your Configator defaults here

	print("AucAdvanced: {{"..libType..":"..libName.."}} loaded!")
	AucAdvanced.Settings.SetDefault("util.example.active", true)
	AucAdvanced.Settings.SetDefault("util.example.slider", 50)
	AucAdvanced.Settings.SetDefault("util.example.wideslider", 100)
	AucAdvanced.Settings.SetDefault("util.example.hardselectbox", 5)
	AucAdvanced.Settings.SetDefault("util.example.dynamicselectbox", 5)
	AucAdvanced.Settings.SetDefault("util.example.label", "Label")
	AucAdvanced.Settings.SetDefault("util.example.text", "")
	AucAdvanced.Settings.SetDefault("util.example.numberbox", "5")
	AucAdvanced.Settings.SetDefault("util.example.moneyframe", "50000000")
	AucAdvanced.Settings.SetDefault("util.example.moneyframepinned", "010101")
end

--[[ Local functions ]]--

function private.SetupConfigGui(gui)
	-- The defaults for the following settings are set in the lib.OnLoad function
	local id = gui:AddTab(libName)
	gui:MakeScrollable(id)
	gui:AddControl(id, "Header",     0,    libName.." options")
	gui:AddControl(id, "Checkbox",   0, 1, "util.example.active", "This is a checkbox, it has two settings true (selected) and false (cleared)")

	gui:AddControl(id, "Subhead",    0,    "There are two kinds of sliders:")
	gui:AddControl(id, "Slider",     0, 1, "util.example.slider", 0, 100, 1, "Normal Sliders: %d%%")
	gui:AddControl(id, "WideSlider", 0, 1, "util.example.wideslider",    0, 200, 1, "And Wide Sliders: %d%%")

	gui:AddControl(id, "Subhead",    0,    "There are also two ways to build a selection box:")
	gui:AddControl(id, "Selectbox",  0, 1, {
		{0, "Zero"},
		{1, "One"},
		{2, "Two"},
		{3, "Three"},
		{4, "Four"},
		{5, "Five"},
		{6, "Six"},
		{7, "Seven"},
		{8, "Eight"},
		{9, "Nine"}
	}, "util.example.hardselectbox", "Statically, by hardcoding the values...")
	gui:AddControl(id, "Selectbox",  0, 1, private.GetNumbers, "util.example.dynamicselectbox", "Or dynamically by specifying a function instead of a table...")

	gui:AddControl(id, "Subhead",    0,    "There are also a few ways to add text:\n  The Headers and SubHeaders that you've already seen...")
	gui:AddControl(id, "Note",       0, 1, nil, nil, "Notes...")
	gui:AddControl(id, "Label",      0, 1, "util.example.label", "And Labels")

	gui:AddControl(id, "Subhead",    0,    "There are two ways to get input via keyboard:")
	gui:AddControl(id, "Text",       0, 1, "util.example.text", "Via the Text Control...")
	gui:AddControl(id, "NumberBox",  0, 1, "util.example.numberbox", 0, 9, "Or using the NumberBox if you only need numbers.")

	gui:AddControl(id, "Subhead",          0,    "There are two kinds of Money Frames:")
	gui:AddControl(id, "MoneyFrame",       0, 1, "util.example.moneyframe", "MoneyFrames...")
	gui:AddControl(id, "MoneyFramePinned", 0, 1, "util.example.moneyframepinned", 0, 101010, "And PinnedMoneyFrames.")

	gui:AddControl(id, "Subhead",    0,    "And finally...")
	gui:AddControl(id, "Button",     0, 1, "util.example.button", "The Button!")
end

function private.GetNumbers()
	return { {0, "Zero"}, {1, "One"}, {2, "Two"}, {3, "Three"}, {4, "Four"}, {5, "Five"}, {6, "Six"}, {7, "Seven"}, {8, "Eight"}, {9, "Nine"} }
end

function private.Foo()
end

function private.Bar()
end

function private.Baz()
end

AucAdvanced.RegisterRevision("$URL: http://dev.norganna.org/auctioneer/trunk/Auc-Advanced/Modules/Auc-Util-Example/Example.lua $", "$Rev: 4828 $")
