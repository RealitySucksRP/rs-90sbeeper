RSPagerBridge = RSPagerBridge or {}
local Bridge = RSPagerBridge
local QBCore, ESX
local customInventoryProvider

Bridge.Framework = 'standalone'
Bridge.Inventory = 'standalone'

local function resourceStarted(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function callConfiguredExport(field, ...)
    local cfg = Config.StandaloneInventory or {}
    if not cfg.Resource or not cfg[field] or not resourceStarted(cfg.Resource) then return nil end
    local args = { ... }
    local ok, result = pcall(function()
        return exports[cfg.Resource][cfg[field]](table.unpack(args))
    end)
    if ok then return result end
    return nil
end

function Bridge.Init()
    local requested = string.lower(tostring(Config.Framework or 'auto'))
    if requested == 'auto' then
        if resourceStarted('qbx_core') then requested = 'qbox'
        elseif resourceStarted('qb-core') then requested = 'qbcore'
        elseif resourceStarted('es_extended') then requested = 'esx'
        else requested = 'standalone' end
    end

    Bridge.Framework = requested
    QBCore, ESX = nil, nil

    if requested == 'qbcore' and resourceStarted('qb-core') then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then QBCore = core end
    elseif requested == 'esx' and resourceStarted('es_extended') then
        local ok, core = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok then ESX = core end
    end

    local inventory = string.lower(tostring(Config.Inventory or 'auto'))
    if inventory == 'auto' then
        if resourceStarted('ox_inventory') then inventory = 'ox_inventory'
        elseif requested == 'qbcore' or requested == 'esx' then inventory = 'framework'
        else inventory = 'standalone' end
    end
    Bridge.Inventory = inventory

    print(('[rs-90sbeeper] framework=%s inventory=%s'):format(Bridge.Framework, Bridge.Inventory))
end

local function normalizeName(first, last, fallback)
    local full = (('%s %s'):format(first or '', last or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return full ~= '' and full or fallback
end

function Bridge.GetPlayerData(src)
    src = tonumber(src)
    if not src then return nil end
    local fallback = GetPlayerName(src) or ('Player %s'):format(src)

    if Bridge.Framework == 'qbcore' and QBCore then
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return nil end
        local pd = player.PlayerData or {}
        return {
            name = normalizeName(pd.charinfo and pd.charinfo.firstname, pd.charinfo and pd.charinfo.lastname, fallback),
            citizenid = pd.citizenid,
            identifier = pd.citizenid,
            job = pd.job and pd.job.name or 'unemployed',
            jobGrade = pd.job and (pd.job.grade and (pd.job.grade.level or pd.job.grade) or 0) or 0,
            onduty = pd.job and pd.job.onduty == true,
            gang = pd.gang and pd.gang.name or 'none',
            gangGrade = pd.gang and (pd.gang.grade and (pd.gang.grade.level or pd.gang.grade) or 0) or 0,
            metadata = pd.metadata or {}
        }
    end

    if Bridge.Framework == 'qbox' and resourceStarted('qbx_core') then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if not ok or not player then return nil end
        local pd = player.PlayerData or {}
        return {
            name = normalizeName(pd.charinfo and pd.charinfo.firstname, pd.charinfo and pd.charinfo.lastname, fallback),
            citizenid = pd.citizenid,
            identifier = pd.citizenid,
            job = pd.job and pd.job.name or 'unemployed',
            jobGrade = pd.job and (pd.job.grade and (pd.job.grade.level or pd.job.grade) or 0) or 0,
            onduty = pd.job and pd.job.onduty == true,
            gang = pd.gang and pd.gang.name or 'none',
            gangGrade = pd.gang and (pd.gang.grade and (pd.gang.grade.level or pd.gang.grade) or 0) or 0,
            metadata = pd.metadata or {}
        }
    end

    if Bridge.Framework == 'esx' and ESX then
        local player = ESX.GetPlayerFromId(src)
        if not player then return nil end
        local job = player.job or {}
        return {
            name = player.getName and player.getName() or fallback,
            citizenid = player.identifier,
            identifier = player.identifier,
            job = job.name or 'unemployed',
            jobGrade = tonumber(job.grade) or 0,
            onduty = true,
            gang = 'none',
            gangGrade = 0,
            metadata = {}
        }
    end

    local identifier = GetPlayerIdentifierByType(src, 'license')
    if not identifier then
        local identifiers = GetPlayerIdentifiers(src)
        identifier = identifiers and identifiers[1] or tostring(src)
    end
    return {
        name = fallback,
        citizenid = identifier,
        identifier = identifier,
        job = 'unemployed',
        jobGrade = 0,
        onduty = true,
        gang = 'none',
        gangGrade = 0,
        metadata = {}
    }
end

function Bridge.GetIdentifier(src)
    local data = Bridge.GetPlayerData(src)
    return tostring((data and (data.identifier or data.citizenid)) or GetPlayerIdentifierByType(src, 'license') or src)
end

local deviceIdSequence = 0

local function stableDeviceId(src, itemName, slot)
    -- Fallback for inventory providers that cannot persist per-item metadata.
    -- Including the slot avoids the old owner+item collision when two physical
    -- beepers of the same item name are present at once. Metadata-capable
    -- inventories use newPhysicalDeviceId() below and keep that id on the item.
    local seed = ('%s:%s:%s'):format(Bridge.GetIdentifier(src), itemName or 'beeper', tostring(slot or 0))
    local hash = joaat(seed) & 0xffffffff
    return ('RSPG-%08X-%s'):format(hash, tostring(itemName or 'beeper'))
end

local function newPhysicalDeviceId(src, itemName, slot)
    deviceIdSequence = (deviceIdSequence + 1) % 0x7fffffff
    local seed = ('%s:%s:%s:%s:%s:%s'):format(
        Bridge.GetIdentifier(src),
        tostring(itemName or 'beeper'),
        tostring(slot or 0),
        tostring(os.time()),
        tostring(GetGameTimer()),
        tostring(deviceIdSequence)
    )
    local hi = joaat(seed) & 0xffffffff
    local lo = joaat(seed .. ':physical') & 0xffffffff
    return ('RSPG-%08X%08X'):format(hi, lo)
end

local function oxItemRegistered(itemName)
    if not resourceStarted('ox_inventory') then return false end
    local ok, item = pcall(function() return exports.ox_inventory:Items(itemName) end)
    return ok and type(item) == 'table'
end

local function oxFindItem(src, names)
    if not resourceStarted('ox_inventory') then return nil, 'not_running' end
    local anyRegistered, inventoryReady = false, false

    for _, itemName in ipairs(names or {}) do
        if oxItemRegistered(itemName) then anyRegistered = true end

        local ok, slotItem = pcall(function()
            return exports.ox_inventory:GetSlotWithItem(src, itemName, nil, false)
        end)
        if ok then
            inventoryReady = true
            if type(slotItem) == 'table' and (tonumber(slotItem.count) or 0) > 0 then
                slotItem.name = slotItem.name or itemName
                return slotItem
            end
        end

        local countOk, count = pcall(function()
            return exports.ox_inventory:GetItemCount(src, itemName, nil, false)
        end)
        if countOk then
            inventoryReady = true
            if (tonumber(count) or 0) > 0 then
                return { name = itemName, count = tonumber(count), slot = 0, metadata = {} }
            end
        end
    end

    if not anyRegistered then return nil, 'unregistered' end
    if not inventoryReady then return nil, 'not_ready' end
    return nil, 'missing'
end

local function qbFindItem(src, names)
    if not QBCore then return nil end
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return nil end
    for _, itemName in ipairs(names or {}) do
        local item = player.Functions.GetItemByName(itemName)
        if item then return item, player end
    end
    return nil, player
end

local function standaloneQuery(src)
    if customInventoryProvider and type(customInventoryProvider.HasItem) == 'function' then
        local ok, result, device = pcall(customInventoryProvider.HasItem, src, Config.PagerItems)
        if ok then return result == true, device end
    end

    local result = callConfiguredExport('HasItemExport', src, Config.PagerItems)
    if result ~= nil then
        if type(result) == 'table' then return result.hasItem == true, result end
        return result == true, nil
    end

    local answered, allowed, device = false, false, nil
    TriggerEvent('rs-90sbeeper:server:hasItem', src, Config.PagerItems, function(value, deviceData)
        answered, allowed, device = true, value == true, deviceData
    end)
    if answered then return allowed, device end
    return false, nil
end

function Bridge.GetPagerDevice(src)
    if not Config.RequirePagerItem then
        local data = Bridge.GetPlayerData(src)
        if Bridge.Framework ~= 'standalone' and not data then
            return { hasItem = false, reason = 'inventory_not_ready', provider = 'built-in' }
        end
        local identifier = tostring((data and (data.identifier or data.citizenid)) or Bridge.GetIdentifier(src))
        return {
            hasItem = true,
            id = ('PERSONAL:%s'):format(identifier),
            item = 'personal',
            slot = 0,
            metadata = {},
            provider = 'built-in'
        }
    end

    local metadataKey = (Config.Persistence and Config.Persistence.DeviceMetadataKey) or 'rs90BeeperId'

    if Bridge.Inventory == 'ox_inventory' then
        local item, reason = oxFindItem(src, Config.PagerItems)
        if item then
            local metadata = type(item.metadata) == 'table' and item.metadata or {}
            local deviceId = metadata[metadataKey]
            if not deviceId then
                local slot = tonumber(item.slot) or 0
                deviceId = slot > 0 and newPhysicalDeviceId(src, item.name, slot) or stableDeviceId(src, item.name, slot)
                metadata[metadataKey] = deviceId
                if slot > 0 then
                    local persisted = pcall(function() exports.ox_inventory:SetMetadata(src, slot, metadata) end)
                    if not persisted then
                        -- Never return an ephemeral random id if the inventory
                        -- refused metadata persistence; fall back to a stable id.
                        deviceId = stableDeviceId(src, item.name, slot)
                        metadata[metadataKey] = deviceId
                    end
                end
            end
            return { hasItem = true, id = tostring(deviceId), item = item.name, slot = item.slot, metadata = metadata, provider = 'ox_inventory' }
        end
        if reason == 'unregistered' then return { hasItem = false, reason = 'pager_item_unregistered', provider = 'ox_inventory' } end
        if reason == 'not_ready' then return { hasItem = false, reason = 'inventory_not_ready', provider = 'ox_inventory' } end
        return { hasItem = false, reason = 'no_item', provider = 'ox_inventory' }
    end

    if Bridge.Inventory == 'framework' and Bridge.Framework == 'qbcore' and QBCore then
        local item, player = qbFindItem(src, Config.PagerItems)
        if not item then return { hasItem = false, reason = 'no_item', provider = 'framework' } end
        item.info = type(item.info) == 'table' and item.info or {}
        local deviceId = item.info[metadataKey]
        if not deviceId then
            local slot = tonumber(item.slot) or 0
            deviceId = newPhysicalDeviceId(src, item.name, slot)
            item.info[metadataKey] = deviceId
            local persisted = player and player.Functions and player.Functions.SetPlayerData and
                pcall(function() player.Functions.SetPlayerData('items', player.PlayerData.items) end)
            if not persisted then
                deviceId = stableDeviceId(src, item.name, slot)
                item.info[metadataKey] = deviceId
            end
        end
        return { hasItem = true, id = tostring(deviceId), item = item.name, slot = item.slot, metadata = item.info, provider = 'framework' }
    end

    if Bridge.Inventory == 'framework' and Bridge.Framework == 'esx' and ESX then
        local player = ESX.GetPlayerFromId(src)
        if not player then return { hasItem = false, reason = 'inventory_not_ready', provider = 'framework' } end
        for _, itemName in ipairs(Config.PagerItems or {}) do
            local item = player.getInventoryItem(itemName)
            if item and (item.count or 0) > 0 then
                return {
                    hasItem = true,
                    id = ('ESX:%s:%s'):format(Bridge.GetIdentifier(src), itemName),
                    item = itemName,
                    slot = 0,
                    metadata = {},
                    provider = 'framework'
                }
            end
        end
        return { hasItem = false, reason = 'no_item', provider = 'framework' }
    end

    local allowed, supplied = standaloneQuery(src)
    if not allowed then return { hasItem = false, reason = 'no_item', provider = 'standalone' } end
    supplied = type(supplied) == 'table' and supplied or {}
    return {
        hasItem = true,
        id = tostring(supplied.id or supplied.deviceId or ('CUSTOM:%s'):format(Bridge.GetIdentifier(src))),
        item = supplied.item or supplied.name or 'beeper',
        slot = supplied.slot or 0,
        metadata = supplied.metadata or {},
        provider = 'standalone'
    }
end


function Bridge.ValidateConfiguredItems()
    if not Config.RequirePagerItem or Bridge.Inventory ~= 'ox_inventory' or not resourceStarted('ox_inventory') then return true end
    for _, itemName in ipairs(Config.PagerItems or {}) do
        if oxItemRegistered(itemName) then return true end
    end
    print(('^3[rs-90sbeeper] WARNING: none of Config.PagerItems are registered in ox_inventory (%s).^7')
        :format(table.concat(Config.PagerItems or {}, ', ')))
    return false
end

function Bridge.HasItem(src)
    if not Config.RequirePagerItem then return true end
    return Bridge.GetPagerDevice(src).hasItem == true
end

function Bridge.HasNamedItem(src, names)
    names = names or {}
    if Bridge.Inventory == 'ox_inventory' and resourceStarted('ox_inventory') then return oxFindItem(src, names) ~= nil end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'qbcore' and QBCore then return qbFindItem(src, names) ~= nil end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'esx' and ESX then
        local player = ESX.GetPlayerFromId(src)
        if not player then return false end
        for _, itemName in ipairs(names) do
            local item = player.getInventoryItem(itemName)
            if item and (item.count or 0) > 0 then return true end
        end
        return false
    end
    if customInventoryProvider then
        local checker = customInventoryProvider.HasNamedItem or customInventoryProvider.HasItem
        if type(checker) == 'function' then
            local ok, result = pcall(checker, src, names)
            if ok then
                if type(result) == 'table' then return result.hasItem == true end
                return result == true
            end
        end
    end
    local result = callConfiguredExport('HasNamedItemExport', src, names)
    if result == nil then result = callConfiguredExport('HasItemExport', src, names) end
    if type(result) == 'table' then return result.hasItem == true end
    return result == true
end

function Bridge.RemoveItem(src, itemName, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if Bridge.Inventory == 'ox_inventory' and resourceStarted('ox_inventory') then
        local ok, result = pcall(function() return exports.ox_inventory:RemoveItem(src, itemName, amount) end)
        return ok and result ~= false
    end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'qbcore' and QBCore then
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.Functions.RemoveItem(itemName, amount) == true
    end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'esx' and ESX then
        local player = ESX.GetPlayerFromId(src)
        if not player then return false end
        local item = player.getInventoryItem(itemName)
        if not item or (item.count or 0) < amount then return false end
        player.removeInventoryItem(itemName, amount)
        return true
    end
    if customInventoryProvider and type(customInventoryProvider.RemoveItem) == 'function' then
        local ok, result = pcall(customInventoryProvider.RemoveItem, src, itemName, amount)
        return ok and result == true
    end
    return callConfiguredExport('RemoveItemExport', src, itemName, amount) == true
end

function Bridge.AddItem(src, itemName, amount, metadata)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if Bridge.Inventory == 'ox_inventory' and resourceStarted('ox_inventory') then
        local ok, result = pcall(function() return exports.ox_inventory:AddItem(src, itemName, amount, metadata) end)
        return ok and result ~= false
    end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'qbcore' and QBCore then
        local player = QBCore.Functions.GetPlayer(src)
        return player and player.Functions.AddItem(itemName, amount, false, metadata) == true
    end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'esx' and ESX then
        local player = ESX.GetPlayerFromId(src)
        if not player then return false end
        player.addInventoryItem(itemName, amount)
        return true
    end
    if customInventoryProvider and type(customInventoryProvider.AddItem) == 'function' then
        local ok, result = pcall(customInventoryProvider.AddItem, src, itemName, amount, metadata)
        return ok and result == true
    end
    return callConfiguredExport('AddItemExport', src, itemName, amount, metadata) == true
end

function Bridge.RemoveFirstAvailableItem(src, names, amount)
    for _, itemName in ipairs(names or {}) do
        if Bridge.HasNamedItem(src, { itemName }) and Bridge.RemoveItem(src, itemName, amount or 1) then
            return itemName
        end
    end
    return nil
end


function Bridge.HasInventoryIntegration()
    if Bridge.Inventory == 'ox_inventory' and resourceStarted('ox_inventory') then return true end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'qbcore' and QBCore then return true end
    if Bridge.Inventory == 'framework' and Bridge.Framework == 'esx' and ESX then return true end
    if customInventoryProvider then return true end
    local cfg = Config.StandaloneInventory or {}
    return type(cfg.Resource) == 'string' and cfg.Resource ~= '' and resourceStarted(cfg.Resource)
end
exports('HasInventoryIntegration', Bridge.HasInventoryIntegration)

function Bridge.GetDiagnostics(src)
    local data = {
        framework = Bridge.Framework,
        inventory = Bridge.Inventory,
        requireItem = Config.RequirePagerItem == true,
        configuredItems = Config.PagerItems or {},
        items = {},
        device = Bridge.GetPagerDevice(src)
    }
    if resourceStarted('ox_inventory') then
        for _, itemName in ipairs(Config.PagerItems or {}) do
            local count = 0
            local ok, result = pcall(function() return exports.ox_inventory:GetItemCount(src, itemName, nil, false) end)
            if ok then count = tonumber(result) or 0 end
            data.items[#data.items + 1] = { name = itemName, registered = oxItemRegistered(itemName), count = count }
        end
    end
    return data
end
exports('GetDiagnostics', Bridge.GetDiagnostics)

function Bridge.RegisterUsableItems()
    if Bridge.Inventory == 'ox_inventory' then return end
    local registrations = {}
    if Config.RequirePagerItem then
        for _, item in ipairs(Config.PagerItems or {}) do
            registrations[#registrations + 1] = { item = item, event = 'rs-90sbeeper:client:use' }
        end
    end
    for _, item in ipairs((Config.Battery and Config.Battery.RechargeItems) or {}) do
        registrations[#registrations + 1] = { item = item, event = 'rs-90sbeeper:client:recharge' }
    end

    if Bridge.Framework == 'qbox' and resourceStarted('qbx_core') then
        local allOk = true
        for _, registration in ipairs(registrations) do
            local ok = pcall(function()
                exports.qbx_core:CreateUseableItem(registration.item, function(src)
                    TriggerClientEvent(registration.event, src)
                end)
            end)
            if not ok then allOk = false end
        end
        if allOk then return end
    end

    if Bridge.Framework == 'qbcore' and QBCore then
        for _, registration in ipairs(registrations) do
            QBCore.Functions.CreateUseableItem(registration.item, function(src)
                TriggerClientEvent(registration.event, src)
            end)
        end
    elseif Bridge.Framework == 'esx' and ESX then
        for _, registration in ipairs(registrations) do
            ESX.RegisterUsableItem(registration.item, function(src)
                TriggerClientEvent(registration.event, src)
            end)
        end
    end
end

function Bridge.SetCustomInventoryProvider(provider)
    customInventoryProvider = type(provider) == 'table' and provider or nil
    return customInventoryProvider ~= nil
end
exports('SetStandaloneInventoryProvider', Bridge.SetCustomInventoryProvider)

Bridge.Init()

AddEventHandler('onResourceStart', function(resource)
    if resource == 'qbx_core' or resource == 'qb-core' or resource == 'es_extended' or resource == 'ox_inventory' then
        SetTimeout(500, function()
            Bridge.Init()
            Bridge.RegisterUsableItems()
            Bridge.ValidateConfiguredItems()
        end)
    end
end)
