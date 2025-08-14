--[=====[
[[SND Metadata]]
author: Stack
version: 2.0.0
description: Intelligently undercuts your retainer listings!

[[End Metadata]]
--]=====]

---

undercutAmount = 1

---

local nodeRetainerListBase = {1, 27}
local nodeRetainerListRetainerSlots = {4, 41001, 41002, 41003, 41004, 41005, 41006, 41007, 41008, 41009}
local nodeRetainerListRetainerName = {2, 3}

local nodeSelectString = {1, 3, 51002}

local nodeRetainerSellListBase = {1, 11}
local nodeRetainerSellListItemSlots = {5, 51001, 51002, 51003, 51004, 51005, 51006, 51007, 51008, 51009, 51010, 51011, 51012, 51013, 51014, 51015, 51016, 51017, 51018, 51019}
local nodeRetainerSellListItemName = {3}
local nodeRetainerSellListTotalItemsCount = {1, 14, 19}

local nodeContextMenuAdjustPrice = {1, 2, 3}

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

---

local buttonRetainerListSpecificRetainer = {2}
local buttonSelectStringOpenItemList = {2}
local buttonRetainerSellListItemSlot = {0}
local buttonContextMenuAdjustPrice = {0, 0}
local buttonRetainerSellCompare = {4}
local buttonRetainerSellConfirm = {0}
local buttonItemSearchResultOpenHistory = {0}

---

nextRetainer = 0
targetSaleSlot = 1
totalRetainers = 0
retainersToRun = {}
lastItem = ""
openItem = ""
price = 0
itemCount = 0
totalItems = 0
marketPrices = {}
salesHistory = {}
fairPrice = 0
currentPrice = ""

---

function GetNodeText(addon, ...)
    if Addons.GetAddon(addon).Ready then
        local node = Addons.GetAddon(addon):GetNode(...)
        return node and node.Text and tostring(node.Text) or ""
    end
    return ""
end

function CountRetainers()
    while not Addons.GetAddon("RetainerList").Ready do yield("/wait 0.1") end
    totalRetainers = 0
    retainersToRun = {}
    myRetainers = {}
    for i, slotId in ipairs(nodeRetainerListRetainerSlots) do
        retainerName = GetNodeText("RetainerList", nodeRetainerListBase[1], nodeRetainerListBase[2], slotId, nodeRetainerListRetainerName[1], nodeRetainerListRetainerName[2])
        if retainerName ~= "" then
            totalRetainers = totalRetainers + 1
            retainersToRun[totalRetainers] = i
            myRetainers[totalRetainers] = retainerName
        end
    end
    yield("/echo [UU] Total retainers: " .. totalRetainers)
    return totalRetainers
end

function OpenRetainer(r)
    yield("/echo [UU] Current Retainer: " .. myRetainers[nextRetainer])
    yield("/callback RetainerList true " .. buttonRetainerListSpecificRetainer[1] .. " " .. tostring(r - 1))
    while not Addons.GetAddon("SelectString").Ready do
        if Addons.GetAddon("Talk").Ready then yield("/callback Talk true 0") end
        yield("/wait 0.1")
    end
    yield("/callback SelectString true " .. buttonSelectStringOpenItemList[1])
    while not Addons.GetAddon("RetainerSellList").Ready do yield("/wait 0.1") end
end

function CloseRetainer()
    while not Addons.GetAddon("RetainerList").Ready do
        yield("/callback RetainerSellList true -1")
        yield("/callback SelectString true -1")
        if Addons.GetAddon("Talk").Ready then yield("/callback Talk true 0") end
        yield("/wait 0.1")
    end
end

function CountItems()
    while not Addons.GetAddon("RetainerSellList").Ready do yield("/wait 0.1") end
    rawItemCount = GetNodeText("RetainerSellList", table.unpack(nodeRetainerSellListTotalItemsCount))
    itemCountTrimmed = string.sub(rawItemCount, 1, 2)
    itemCount = string.gsub(itemCountTrimmed, "%D", "")
    return tonumber(itemCount) or 0
end

function ClickItem(item)
    while not Addons.GetAddon("RetainerSell").Ready do
        if Addons.GetAddon("ContextMenu").Ready then
            yield("/callback ContextMenu true 0 0")
            yield("/wait 0.1")
        elseif Addons.GetAddon("RetainerSellList").Ready then
            yield("/callback RetainerSellList true " .. buttonRetainerSellListItemSlot[1] .. " " .. tostring(item - 1) .. " 1")
        end
        yield("/wait 0.1")
    end
end

function ReadOpenItem()
    lastItem = openItem
    rawText = GetNodeText("RetainerSell", table.unpack(nodeRetainerSellItemName))
    cleanedText = string.gsub(rawText, "%W", "")
    if string.len(cleanedText) > 3 then
        openItem = string.sub(cleanedText, 1, -1)
    else
        openItem = cleanedText
    end
end

function OpenComparePriceWindow()
    yield("/callback RetainerSell true " .. buttonRetainerSellCompare[1])
    while not Addons.GetAddon("ItemSearchResult").Ready do yield("/wait 0.1") end
end

function ReadMarketPrices()
    ready = false
    searchWaitTick = 0
    firstPrice = ""
    
    while not ready and searchWaitTick < 50 do
        searchWaitTick = searchWaitTick + 1
        yield("/wait 0.1")
        
        priceText = GetNodeText("ItemSearchResult", nodeItemSearchResultBase[1], nodeItemSearchResultBase[2], nodeItemSearchResultItemSlots[1], nodeItemSearchResultPrice[1])
        cleanPrice = string.gsub(priceText, "%D", "")
        if cleanPrice ~= "" and cleanPrice ~= firstPrice then
            firstPrice = cleanPrice
            ready = true
        end
    end
    
    prices = {}
    for i, slotId in ipairs(nodeItemSearchResultItemSlots) do
        if i > 20 then break end
        priceText = GetNodeText("ItemSearchResult", nodeItemSearchResultBase[1], nodeItemSearchResultBase[2], slotId, nodeItemSearchResultPrice[1])
        if priceText ~= "" then
            cleanedPrice = string.gsub(priceText, "%D", "")
            priceValue = tonumber(cleanedPrice)
            if priceValue then table.insert(prices, priceValue) end
        else
            break
        end
    end
    return prices
end

function OpenSaleHistoryWindow()
    yield("/callback ItemSearchResult true " .. buttonItemSearchResultOpenHistory[1])
    while not Addons.GetAddon("ItemHistory").Ready do yield("/wait 0.1") end
end

function ReadSalesHistory()
    sales = {}
    for i, slotId in ipairs(nodeItemHistoryItemSlots) do
        if i > 20 then break end
        priceText = GetNodeText("ItemHistory", nodeItemHistoryBase[1], nodeItemHistoryBase[2], slotId, nodeItemHistoryPrice[1])
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
    yield("/callback ItemHistory true -1")
    while Addons.GetAddon("ItemHistory").Ready do yield("/wait 0.1") end
end

function CloseComparePriceWindow()
    yield("/callback ItemSearchResult true -1")
    while Addons.GetAddon("ItemSearchResult").Ready do yield("/wait 0.1") end
end

function FilterLowballListings(marketPrices, salesHistory)
    if #marketPrices == 0 then return {} end
    
    local floorPrice = 1
    if #salesHistory > 0 then
        table.sort(salesHistory)
        local salesMedian = salesHistory[math.ceil(#salesHistory / 2)]
        floorPrice = math.max(1, math.floor(salesMedian * 0.3))
    end
    
    table.sort(marketPrices)
    local marketCopy = {}
    for i, price in ipairs(marketPrices) do
        table.insert(marketCopy, price)
    end
    
    if #marketCopy >= 5 then
        local percentile20Index = math.max(1, math.floor(#marketCopy * 0.2))
        local marketFloor = marketCopy[percentile20Index]
        floorPrice = math.max(floorPrice, math.floor(marketFloor * 0.5))
    end
    
    local filteredPrices = {}
    for _, price in ipairs(marketPrices) do
        if price >= floorPrice then
            table.insert(filteredPrices, price)
        end
    end
    
    if #filteredPrices == 0 and #marketPrices > 0 then
        local keepCount = math.max(1, math.floor(#marketPrices * 0.5))
        for i = #marketPrices - keepCount + 1, #marketPrices do
            table.insert(filteredPrices, marketPrices[i])
        end
    end
    
    return filteredPrices
end

function CalculateTrimmedMean(prices)
    if #prices == 0 then return 1000 end
    if #prices <= 4 then 
        return prices[math.ceil(#prices / 2)]
    end
    
    local trimAmount = math.floor(#prices * 0.1)
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
            table.sort(filteredPrices)
            return filteredPrices[math.ceil(#filteredPrices / 2)]
        else
            return 1000
        end
    end
    if #filteredPrices == 0 then
        table.sort(salesHistory)
        return CalculateTrimmedMean(salesHistory)
    end
    
    table.sort(salesHistory)
    table.sort(filteredPrices)
    
    local salesValue = CalculateTrimmedMean(salesHistory)
    local marketValue = CalculateTrimmedMean(filteredPrices)
    
    return math.floor(0.6 * salesValue + 0.4 * marketValue)
end

function DetermineNewPrice(filteredPrices, fairPrice)
    local isLowValue = fairPrice < 5000
    
    if #filteredPrices == 0 then 
        local newPrice = math.floor(fairPrice * 0.95)
        return math.max(1, newPrice)
    end
    
    table.sort(filteredPrices)
    local cheapest = filteredPrices[1]
    
    if isLowValue then
        local reasonableFloor = math.max(1, math.floor(fairPrice * 0.4))
        
        if cheapest >= reasonableFloor then
            return math.max(reasonableFloor, cheapest - 1)
        else
            return math.floor(reasonableFloor * 1.1)
        end
    else
        local lowerBound = math.floor(fairPrice * 0.7)
        local upperBound = math.floor(fairPrice * 1.1)
        
        if cheapest >= lowerBound and cheapest <= upperBound then
            local newPrice = math.max(1, cheapest - 1)
            return math.max(lowerBound, newPrice)
        end
        
        if cheapest < lowerBound then
            return lowerBound
        end
        
        local newPrice = math.max(1, cheapest - 1)
        return math.max(lowerBound, math.min(newPrice, upperBound))
    end
end

function CalculatePrice(marketPrices, salesHistory, undercutAmount)
    local filteredPrices = FilterLowballListings(marketPrices, salesHistory)
    local fairPrice = CalculateFairPrice(filteredPrices, salesHistory)
    return DetermineNewPrice(filteredPrices, fairPrice)
end

function SetPrice(newPrice)
    yield("/callback RetainerSell true 2 " .. tostring(newPrice))
    yield("/wait 0.1")
    yield("/callback RetainerSell true " .. buttonRetainerSellConfirm[1])
    yield("/wait 0.1")
end

function CloseSales()
    while Addons.GetAddon("RetainerSell").Ready do
        yield("/callback RetainerSell true -1")
        yield("/wait 0.1")
    end
end

if Addons.GetAddon("RetainerList").Ready then
    CountRetainers()
    goto NextRetainer
elseif Addons.GetAddon("RetainerSell").Ready then
    goto RepeatItem
elseif Addons.GetAddon("SelectString").Ready then
    yield("/callback SelectString true " .. buttonSelectStringOpenItemList[1])
    while not Addons.GetAddon("RetainerSellList").Ready do yield("/wait 0.1") end
    goto Sales
elseif Addons.GetAddon("RetainerSellList").Ready then
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
if targetSaleSlot > 1 then
    yield("/wait 2")
end
ClickItem(targetSaleSlot)

::RepeatItem::
ReadOpenItem()
if lastItem ~= "" and openItem == lastItem then goto Apply end

currentPrice = string.gsub(GetNodeText("RetainerSell", table.unpack(nodeRetainerSellCurrentPrice)), "%D", "")

OpenComparePriceWindow()
marketPrices = ReadMarketPrices()
OpenSaleHistoryWindow()
salesHistory = ReadSalesHistory()
CloseSaleHistoryWindow()

price = CalculatePrice(marketPrices, salesHistory, 1)

::Apply::
if price ~= tonumber(currentPrice) then
    yield("/echo [UU] " .. openItem .. ": " .. (currentPrice ~= "" and currentPrice or "unknown") .. " -> " .. price)
else
    yield("/echo [UU] " .. openItem .. ": " .. (currentPrice ~= "" and currentPrice or "unknown"))
end

CloseComparePriceWindow()
if price ~= tonumber(currentPrice) then
    SetPrice(price)
end
CloseSales()

::Loop::
totalItems = CountItems()
if totalItems > targetSaleSlot then
    targetSaleSlot = targetSaleSlot + 1
    goto NextItem
end
CloseRetainer()
goto NextRetainer

::EndOfScript::
yield("/echo Ultimate Undercut completed!")