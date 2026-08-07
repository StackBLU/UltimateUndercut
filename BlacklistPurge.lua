--[=====[
[[SND Metadata]]
author: Stack
version: 1.0.0
description: Repeatedly removes the first entry from the BlackList until manually stopped.
[[End Metadata]]
--]=====]

local waitShort = 0.1
local waitBetweenDeletes = 0.5

local addonBlackList = "BlackList"
local addonContextMenu = "ContextMenu"
local addonSelectYesno = "SelectYesno"

local buttonBlackListSelectItem = {1}
local buttonContextMenuRemoveFromBlacklist = {0, 1}
local buttonSelectYesnoYes = {0}

local scriptTag = "[BP]"

function SelectBlackListItem(index)
    yield("/callback " .. addonBlackList .. " true "
        .. buttonBlackListSelectItem[1] .. " "
        .. tostring(index - 1))
end

function ClickRemoveFromBlacklist()
    yield("/callback " .. addonContextMenu .. " true "
        .. buttonContextMenuRemoveFromBlacklist[1] .. " "
        .. buttonContextMenuRemoveFromBlacklist[2])
end

function ConfirmYes()
    yield("/callback " .. addonSelectYesno .. " true "
        .. buttonSelectYesnoYes[1])
end

function RemoveFirstBlackListEntry()
    SelectBlackListItem(1)

    while not Addons.GetAddon(addonContextMenu).Ready do
        yield("/wait " .. waitShort)
    end

    ClickRemoveFromBlacklist()

    while not Addons.GetAddon(addonSelectYesno).Ready do
        yield("/wait " .. waitShort)
    end

    ConfirmYes()
end

-- End of functions / Start of script

if not Addons.GetAddon(addonBlackList).Ready then
    yield("/echo " .. scriptTag .. " BlackList is not open.")
    return
end

while true do
    RemoveFirstBlackListEntry()
    yield("/wait " .. waitBetweenDeletes)
end