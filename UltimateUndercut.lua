--[=====[
[[SND Metadata]]
author: Stack
version: 2.0.0
description: Intelligently undercuts your retainer listings! https://github.com/StackBLU
[[End Metadata]]
--]=====]

-- Default values
local defaultPrice = 1000
local minPrice = 1
local priceToReturn = 1000 -- If an item would be sold for under this price, return it to inventory (Set to 0 to disable)
local quantityCheck = 10 -- priceToReturn only applies if the item has under this quantity (so if you're selling 5000 fire crystals for 30g each, it won't return them to your inventory)

-- Wait times
local waitShort = 0.1
local waitBetweenItems = 2

-- Loop limits
local maxItemsToProcess = 20
local maxSearchWaitTicks = 50

-- Price calculation constants
local salesMedianFloorMultiplier = 0.3
local marketFloorPercentile = 0.2
local marketFloorMultiplier = 0.5
local salesWeight = 0.6
local marketWeight = 0.4
local noPricesMultiplier = 0.95
local lowValueThreshold = 5000
local lowValueFloorMultiplier = 0.4
local lowValueAdjustmentMultiplier = 1.1
local highValueLowerBoundMultiplier = 0.7

-- Addon names
local addonRetainerList = "RetainerList"
local addonSelectString = "SelectString"
local addonRetainerSellList = "RetainerSellList"
local addonRetainerSell = "RetainerSell"
local addonContextMenu = "ContextMenu"
local addonItemSearchResult = "ItemSearchResult"
local addonItemHistory = "ItemHistory"
local addonTalk = "Talk"

-- Text node paths
local nodeRetainerListBase = {1, 27}
local nodeRetainerListRetainerSlots = {4, 41001, 41002, 41003, 41004, 41005, 41006, 41007, 41008, 41009}
local nodeRetainerListRetainerName = {2, 3}

local nodeSelectString = {1, 3, 51002}

local nodeRetainerSellListBase = {1, 11}
local nodeRetainerSellListItemSlots = {5, 51001, 51002, 51003, 51004, 51005, 51006, 51007, 51008, 51009, 51010, 51011, 51012, 51013, 51014, 51015, 51016, 51017, 51018, 51019}
local nodeRetainerSellListItemName = {3}
local nodeRetainerSellListItemQuantity = {4, 6}
local nodeRetainerSellListTotalItemsCount = {1, 14, 19}

local nodeRetainerSellItemName = {1, 5, 7}
local nodeRetainerSellCurrentPrice = {1, 8, 10, 5}
local nodeRetainerSellComparePricesButton = {1, 2, 4}
local nodeRetainerSellConfirmButton = {0}

local nodeItemSearchResultBase = {1, 26}
local nodeItemSearchResultItemSlots = {4, 41001, 41002, 41003, 41004, 41005, 41006, 41007, 41008, 41009, 41010, 41011, 41012, 41013, 41014, 41015, 41016, 41017, 41018, 41019, 41020, 41021}
local nodeItemSearchResultPrice = {5}
local nodeItemSearchResultRetainerName = {10}
local nodeItemSearchResultHistoryButton = {0}

local nodeItemHistoryBase = {1, 10}
local nodeItemHistoryItemSlots = {4, 41001, 41002, 41003, 41004, 41005, 41006, 41007, 41008, 41009, 41010, 41011, 41012, 41013, 41014, 41015, 41016, 41017, 41018, 41019, 41020, 41021}
local nodeItemHistoryPrice = {4}

-- Button paths
local buttonRetainerListSpecificRetainer = {2}
local buttonSelectStringOpenItemList = {2}
local buttonRetainerSellListItemSlot = {0}
local buttonContextMenuAdjustPrice = {0, 0}
local buttonContextMenuReturnToInventory = {0, 2}
local buttonRetainerSellCompare = {4}
local buttonRetainerSellConfirm = {0}
local buttonItemSearchResultOpenHistory = {0}
local buttonTalkConfirm = {0}
local buttonCloseWindow = {-1}
local buttonRetainerSellSetPrice = {2}

-- Script identifier
local scriptTag = "[UU]"

-- Numbers
itemCount = 0
nextRetainer = 0
price = 0
targetSaleSlot = 1
totalItems = 0
totalRetainers = 0
totalProcessed = 0
itemWasReturned = false

-- Strings
currentPrice = ""
lastItem = ""
openItem = ""
itemQuantity = ""

-- Tables/Arrays
marketPrices = {}
myRetainers = {}
retainersToRun = {}
salesHistory = {}
returnedItems = {}

function GetNodeText(addon, ...)
    if Addons.GetAddon(addon).Ready then
        local node = Addons.GetAddon(addon):GetNode(...)
        return node and node.Text and tostring(node.Text) or ""
    end
    return ""
end

function CountRetainers()
    while not Addons.GetAddon(addonRetainerList).Ready do yield("/wait " .. waitShort) end    
    for i, slotId in ipairs(nodeRetainerListRetainerSlots) do
        local retainerName = GetNodeText(addonRetainerList, nodeRetainerListBase[1], nodeRetainerListBase[2], slotId, nodeRetainerListRetainerName[1], nodeRetainerListRetainerName[2])
        if retainerName ~= "" then
            totalRetainers = totalRetainers + 1
            retainersToRun[totalRetainers] = i
            myRetainers[totalRetainers] = retainerName
        end
    end
    yield("/echo " .. scriptTag .. " Total retainers: " .. totalRetainers)
    return totalRetainers
end

function OpenRetainer(r)
    yield("/echo " .. scriptTag .. " Current Retainer (" .. nextRetainer .. "/" .. totalRetainers .. "): " .. myRetainers[nextRetainer])
    yield("/callback " .. addonRetainerList .. " true " .. buttonRetainerListSpecificRetainer[1] .. " " .. tostring(r - 1))
    while not Addons.GetAddon(addonSelectString).Ready do
        if Addons.GetAddon(addonTalk).Ready then yield("/callback " .. addonTalk .. " true " .. buttonTalkConfirm[1]) end
        yield("/wait " .. waitShort)
    end
    yield("/callback " .. addonSelectString .. " true " .. buttonSelectStringOpenItemList[1])
    while not Addons.GetAddon(addonRetainerSellList).Ready do yield("/wait " .. waitShort) end
end

function CloseRetainer()
    while not Addons.GetAddon(addonRetainerList).Ready do
        yield("/callback " .. addonRetainerSellList .. " true " .. buttonCloseWindow[1])
        yield("/callback " .. addonSelectString .. " true " .. buttonCloseWindow[1])
        if Addons.GetAddon(addonTalk).Ready then yield("/callback " .. addonTalk .. " true " .. buttonTalkConfirm[1]) end
        yield("/wait " .. waitShort)
    end
end

function CountItems()
    local rawItemCount = GetNodeText(addonRetainerSellList, table.unpack(nodeRetainerSellListTotalItemsCount))
    itemCount = string.gsub(string.sub(rawItemCount, 1, 2), "%D", "")
    return tonumber(itemCount) or 0
end

function GetItemQuantity(item)
    if item < 1 or item > #nodeRetainerSellListItemSlots then return 1 end
    local rawQuantity = GetNodeText(addonRetainerSellList, nodeRetainerSellListBase[1], nodeRetainerSellListBase[2], nodeRetainerSellListItemSlots[item], nodeRetainerSellListItemQuantity[1], nodeRetainerSellListItemQuantity[2])
    local cleanQuantity = string.gsub(rawQuantity, "%D", "")
    return tonumber(cleanQuantity) or 1
end

function ClickItem(item)
    while not Addons.GetAddon(addonRetainerSell).Ready do
        if Addons.GetAddon(addonContextMenu).Ready then
            yield("/callback " .. addonContextMenu .. " true " .. buttonContextMenuAdjustPrice[1] .. " " .. buttonContextMenuAdjustPrice[2])
        elseif Addons.GetAddon(addonRetainerSellList).Ready then
            yield("/callback " .. addonRetainerSellList .. " true " .. buttonRetainerSellListItemSlot[1] .. " " .. tostring(item - 1) .. " 1")
        end
        yield("/wait " .. waitShort)
    end
end

function ReadOpenItem()
    lastItem = openItem
    rawText = GetNodeText(addonRetainerSell, table.unpack(nodeRetainerSellItemName))
    cleanedText = string.gsub(rawText, "%W", "")
    openItem = cleanedText
end

function OpenComparePriceWindow()
    yield("/callback " .. addonRetainerSell .. " true " .. buttonRetainerSellCompare[1])
    while not Addons.GetAddon(addonItemSearchResult).Ready do yield("/wait " .. waitShort) end
end

function ReadMarketPrices()
    local ready = false
    local searchWaitTick = 0
    local firstPrice = ""
    
    while not ready and searchWaitTick < maxSearchWaitTicks do
        searchWaitTick = searchWaitTick + 1
        yield("/wait " .. waitShort)
        
        priceText = GetNodeText(addonItemSearchResult, nodeItemSearchResultBase[1], nodeItemSearchResultBase[2], nodeItemSearchResultItemSlots[1], nodeItemSearchResultPrice[1])
        cleanPrice = string.gsub(priceText, "%D", "")
        if cleanPrice ~= "" and cleanPrice ~= firstPrice then
            firstPrice = cleanPrice
            ready = true
        end
    end
    
    local prices = {}
    for i, slotId in ipairs(nodeItemSearchResultItemSlots) do
        if i > maxItemsToProcess then break end
        priceText = GetNodeText(addonItemSearchResult, nodeItemSearchResultBase[1], nodeItemSearchResultBase[2], slotId, nodeItemSearchResultPrice[1])
        if priceText ~= "" then
            cleanedPrice = string.gsub(priceText, "%D", "")
            priceValue = tonumber(cleanedPrice)
            if priceValue then 
                table.insert(prices, priceValue)
            end
        else
            break
        end
    end
    return prices
end

function OpenSaleHistoryWindow()
    yield("/callback " .. addonItemSearchResult .. " true " .. buttonItemSearchResultOpenHistory[1])
    while not Addons.GetAddon(addonItemHistory).Ready do yield("/wait " .. waitShort) end
end

function ReadSalesHistory()
    local sales = {}
    for i, slotId in ipairs(nodeItemHistoryItemSlots) do
        if i > maxItemsToProcess then break end
        priceText = GetNodeText(addonItemHistory, nodeItemHistoryBase[1], nodeItemHistoryBase[2], slotId, nodeItemHistoryPrice[1])
        if priceText ~= "" then
            cleanedPrice = string.gsub(priceText, "%D", "")
            priceValue = tonumber(cleanedPrice)
            if priceValue then table.insert(sales, priceValue) end
        else
            break
        end
    end
    return sales
end

function CloseSaleHistoryWindow()
    yield("/callback " .. addonItemHistory .. " true " .. buttonCloseWindow[1])
    while Addons.GetAddon(addonItemHistory).Ready do yield("/wait " .. waitShort) end
end

function CloseComparePriceWindow()
    yield("/callback " .. addonItemSearchResult .. " true " .. buttonCloseWindow[1])
    while Addons.GetAddon(addonItemSearchResult).Ready do yield("/wait " .. waitShort) end
end

function FilterLowballListings(marketPrices, salesHistory)
   local marketCount = #marketPrices
   local salesCount = #salesHistory
   
   if marketCount == 0 then return {} end
   
   local floorPrice = minPrice
   if salesCount > 0 then
       table.sort(salesHistory)
       local salesMedian = salesHistory[math.ceil(salesCount / 2)]
       floorPrice = math.max(minPrice, math.floor(salesMedian * salesMedianFloorMultiplier))
   end
   
   table.sort(marketPrices)
   if marketCount >= 5 then
       local percentile20Index = math.max(1, math.floor(marketCount * marketFloorPercentile))
       local marketFloor = marketPrices[percentile20Index]
       floorPrice = math.max(floorPrice, math.floor(marketFloor * marketFloorMultiplier))
   end
   
   local filteredPrices = {}
   for i, price in ipairs(marketPrices) do
       if price >= floorPrice then
           table.insert(filteredPrices, price)
       end
   end
   
   if #filteredPrices == 0 and marketCount > 0 then
       local keepCount = math.max(1, math.floor(marketCount * marketFloorMultiplier))
       for i = marketCount - keepCount + 1, marketCount do
           table.insert(filteredPrices, marketPrices[i])
       end
   end
   
   return filteredPrices
end

function CalculateTrimmedMean(prices)
    if #prices == 0 then return defaultPrice end
    if #prices <= 2 then 
        return prices[math.ceil(#prices / 2)]
    end
    
    local trimAmount
    if #prices <= 9 then
        trimAmount = 1
    else
        trimAmount = 2
    end
    
    local sum = 0
    local count = 0
    
    for i = trimAmount + 1, #prices - trimAmount do
        sum = sum + prices[i]
        count = count + 1
    end
    
    return count > 0 and math.floor(sum / count) or prices[math.ceil(#prices / 2)]
end

function CalculateFairPrice(filteredPrices, salesHistory)
    if #salesHistory == 0 then
        if #filteredPrices > 0 then
            return filteredPrices[math.ceil(#filteredPrices / 2)]
        else
            return defaultPrice
        end
    end
    if #filteredPrices == 0 then
        table.sort(salesHistory)
        return CalculateTrimmedMean(salesHistory)
    end
    
    local salesValue = CalculateTrimmedMean(salesHistory)
    local marketValue = CalculateTrimmedMean(filteredPrices)
    
    return math.floor(salesWeight * salesValue + marketWeight * marketValue)
end

function DetermineNewPrice(filteredPrices, fairPrice)
    local isLowValue = fairPrice < lowValueThreshold
    
    if #filteredPrices == 0 then 
        local newPrice = math.floor(fairPrice * noPricesMultiplier)
        return math.max(minPrice, newPrice)
    end
    
    table.sort(filteredPrices)
    local cheapest = filteredPrices[1]
    
    local marketBasedPrice = math.max(minPrice, cheapest - 1)
    
    if isLowValue then
        local reasonableFloor = math.max(minPrice, math.floor(fairPrice * lowValueFloorMultiplier))
        
        if cheapest >= reasonableFloor then
            return math.max(reasonableFloor, marketBasedPrice)
        else
            return math.max(marketBasedPrice, math.floor(reasonableFloor * lowValueAdjustmentMultiplier))
        end
    else
        local lowerBound = math.floor(fairPrice * highValueLowerBoundMultiplier)
        
        return math.max(marketBasedPrice, lowerBound)
    end
end

function CalculatePrice(marketPrices, salesHistory)
    local filteredPrices = FilterLowballListings(marketPrices, salesHistory)
    local fairPrice = CalculateFairPrice(filteredPrices, salesHistory)
    return DetermineNewPrice(filteredPrices, fairPrice)
end

function ReturnToInventory()
    yield("/callback " .. addonRetainerSell .. " true " .. buttonCloseWindow[1])
    while Addons.GetAddon(addonRetainerSell).Ready do yield("/wait " .. waitShort) end
    yield("/callback " .. addonRetainerSellList .. " true " .. buttonRetainerSellListItemSlot[1] .. " " .. tostring(targetSaleSlot - 1) .. " 1")
    while not Addons.GetAddon(addonContextMenu).Ready do yield("/wait " .. waitShort) end
    yield("/callback " .. addonContextMenu .. " true " .. buttonContextMenuReturnToInventory[1] .. " " .. buttonContextMenuReturnToInventory[2])
end

function SetPrice(newPrice)
    yield("/callback " .. addonRetainerSell .. " true " .. buttonRetainerSellSetPrice[1] .. " " .. tostring(newPrice))
    yield("/callback " .. addonRetainerSell .. " true " .. buttonRetainerSellConfirm[1])
end

function CloseSales()
    while Addons.GetAddon(addonRetainerSell).Ready do
        yield("/callback " .. addonRetainerSell .. " true " .. buttonCloseWindow[1])
        yield("/wait " .. waitShort)
    end
end

-- End of functions / Start of script

if Addons.GetAddon(addonRetainerList).Ready then
    CountRetainers()
    goto NextRetainer
elseif Addons.GetAddon(addonRetainerSell).Ready then
    goto RepeatItem
elseif Addons.GetAddon(addonSelectString).Ready then
    yield("/callback " .. addonSelectString .. " true " .. buttonSelectStringOpenItemList[1])
    while not Addons.GetAddon(addonRetainerSellList).Ready do yield("/wait " .. waitShort) end
    goto Sales
elseif Addons.GetAddon(addonRetainerSellList).Ready then
    goto Sales
else
    return
end

::NextRetainer::
if nextRetainer == totalRetainers then goto EndOfScript end
if nextRetainer < totalRetainers then nextRetainer = nextRetainer + 1 end
targetSaleSlot = 1
OpenRetainer(retainersToRun[nextRetainer])

::Sales::
itemCount = CountItems()
if itemCount == 0 then goto Loop end

::NextItem::
itemQuantity = GetItemQuantity(targetSaleSlot)

ClickItem(targetSaleSlot)

::RepeatItem::
ReadOpenItem()
if lastItem ~= "" and openItem == lastItem then goto Apply end

if targetSaleSlot > 1 then
    yield("/wait " .. waitBetweenItems)
end

currentPrice = string.gsub(GetNodeText(addonRetainerSell, table.unpack(nodeRetainerSellCurrentPrice)), "%D", "")

OpenComparePriceWindow()
marketPrices = ReadMarketPrices()
OpenSaleHistoryWindow()
salesHistory = ReadSalesHistory()
CloseSaleHistoryWindow()

price = CalculatePrice(marketPrices, salesHistory)

::Apply::
totalProcessed = totalProcessed + 1
if price < priceToReturn and tonumber(itemQuantity) < quantityCheck then
    yield("/echo " .. scriptTag .. " " .. openItem .. ": " .. (currentPrice ~= "" and currentPrice or "unknown") .. " -> Returned")
    table.insert(returnedItems, {itemName = openItem, wouldBePrice = price})
    CloseComparePriceWindow()
    ReturnToInventory()
    itemWasReturned = true
elseif price ~= tonumber(currentPrice) then
    yield("/echo " .. scriptTag .. " " .. openItem .. ": " .. (currentPrice ~= "" and currentPrice or "unknown") .. " -> " .. price)
    CloseComparePriceWindow()
    SetPrice(price)
    itemWasReturned = false
else
    yield("/echo " .. scriptTag .. " " .. openItem .. ": " .. (currentPrice ~= "" and currentPrice or "unknown"))
    CloseComparePriceWindow()
    itemWasReturned = false
end
CloseSales()

::Loop::
totalItems = CountItems()
if totalItems > targetSaleSlot then
    if itemWasReturned then
        yield("/wait " .. waitBetweenItems)
    end
    if not itemWasReturned then
        targetSaleSlot = targetSaleSlot + 1
    end
    goto NextItem
end
CloseRetainer()
goto NextRetainer

::EndOfScript::
yield("/echo " .. scriptTag .. " Total items processed: " .. totalProcessed)

if #returnedItems > 0 then
    yield("/echo " .. scriptTag .. " Items returned to inventory:")
    for _, item in ipairs(returnedItems) do
        yield("/echo " .. scriptTag .. " " .. item.itemName .. ": " .. item.wouldBePrice)
    end
end

yield("/echo Ultimate Undercut completed successfully!")