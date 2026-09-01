--[[
    Bancs monde + placeables (SQL)
]]

Benches = Benches or {}

--- world:<id> | placed:<dbId>
local worldEntities = {}  -- [worldId] = { coords, heading, category, model, key }
local placedBenches = {}  -- [id] = row + key

local function benchKey(kind, id)
    return ('%s:%s'):format(kind, tostring(id))
end

function Benches.GetWorld(id)
    return worldEntities[id]
end

function Benches.GetPlaced(id)
    return placedBenches[id]
end

---@param key string  "world:xxx" | "placed:123"
---@return table|nil benchData with .coords .category .heading
function Benches.Resolve(key)
    if not key or type(key) ~= 'string' then return nil end
    local kind, id = key:match('^(%w+):(.+)$')
    if kind == 'world' then
        return worldEntities[id]
    elseif kind == 'placed' then
        local num = tonumber(id)
        return num and placedBenches[num] or nil
    end
    return nil
end

function Benches.GetAllForClient()
    local list = {}
    for id, b in pairs(worldEntities) do
        list[#list + 1] = {
            key = b.key,
            kind = 'world',
            id = id,
            category = b.category,
            coords = b.coords,
            heading = b.heading,
            model = b.model,
        }
    end
    for id, b in pairs(placedBenches) do
        list[#list + 1] = {
            key = b.key,
            kind = 'placed',
            id = id,
            owner = b.owner,
            category = b.category,
            coords = b.coords,
            heading = b.heading,
            model = b.model,
        }
    end
    return list
end

local function loadWorld()
    worldEntities = {}
    for i = 1, #(Config.WorldBenches or {}) do
        local w = Config.WorldBenches[i]
        local id = w.id or ('world_' .. i)
        worldEntities[id] = {
            key = benchKey('world', id),
            kind = 'world',
            id = id,
            category = w.category,
            coords = w.coords,
            heading = w.heading or 0.0,
            model = w.model or GetBenchModel(w.category),
        }
    end
end

local function rowToBench(row)
    local id = tonumber(row.id)
    return {
        key = benchKey('placed', id),
        kind = 'placed',
        id = id,
        owner = row.owner,
        category = row.category,
        coords = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0),
        heading = row.heading + 0.0,
        model = joaat(row.model),
        modelName = row.model,
    }
end

function Benches.LoadPlaced()
    placedBenches = {}
    local rows = MySQL.query.await('SELECT * FROM sanctuary_placed_benches', {}) or {}
    for i = 1, #rows do
        local b = rowToBench(rows[i])
        placedBenches[b.id] = b
    end
    DebugPrint('Loaded placed benches:', #rows)
end

---@param owner string identifier
---@param category string
---@param modelHash number
---@param coords vector3
---@param heading number
---@return table|nil
function Benches.InsertPlaced(owner, category, modelHash, coords, heading)
    local modelName = nil
    for cat, hash in pairs(Config.BenchModels) do
        if hash == modelHash or cat == category then
            -- resolve name from PlaceableItems
        end
    end
    -- Prefer model name from placeable config
    for itemName, def in pairs(Config.PlaceableItems) do
        if def.category == category then
            modelName = itemName -- fallback label; real prop name below
            break
        end
    end
    -- Store hash as string hex-ish or known prop names
    local propNames = {
        scrap = 'prop_tool_bench02',
        medical = 'prop_table_03',
        weapons = 'prop_toolchest_05',
        survival = 'prop_washer_01',
    }
    modelName = propNames[category] or tostring(modelHash)

    local insertId = MySQL.insert.await(
        'INSERT INTO sanctuary_placed_benches (owner, category, model, x, y, z, heading) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { owner, category, modelName, coords.x, coords.y, coords.z, heading }
    )
    if not insertId then return nil end

    local b = {
        key = benchKey('placed', insertId),
        kind = 'placed',
        id = insertId,
        owner = owner,
        category = category,
        coords = coords,
        heading = heading,
        model = modelHash,
        modelName = modelName,
    }
    placedBenches[insertId] = b
    return b
end

---@param id number
---@return boolean
function Benches.DeletePlaced(id)
    id = tonumber(id)
    if not id or not placedBenches[id] then return false end
    MySQL.query.await('DELETE FROM sanctuary_placed_benches WHERE id = ?', { id })
    placedBenches[id] = nil
    return true
end

function Benches.BroadcastSync(target)
    local payload = Benches.GetAllForClient()
    if target then
        TriggerClientEvent('sanctuary_crafting:client:syncBenches', target, payload)
    else
        TriggerClientEvent('sanctuary_crafting:client:syncBenches', -1, payload)
    end
end

CreateThread(function()
    loadWorld()
    MySQL.ready.await()
    -- ensure table
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_placed_benches` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(60) NOT NULL,
            `category` VARCHAR(32) NOT NULL DEFAULT 'scrap',
            `model` VARCHAR(64) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `heading` FLOAT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    Benches.LoadPlaced()
    Wait(1000)
    Benches.BroadcastSync()
end)

-- Sync on join
RegisterNetEvent('sanctuary_crafting:server:requestSync', function()
    local src = source
    Benches.BroadcastSync(src)
end)

RegisterNetEvent('sanctuary_crafting:server:placeBench', function(category, coords, heading)
    local src = source
    if type(category) ~= 'string' or not IsValidBenchCategory(category) then return end
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end
    local x, y, z = coords.x or coords[1], coords.y or coords[2], coords.z or coords[3]
    if not x or not y or not z then return end
    heading = tonumber(heading) or 0.0

    local ped = GetPlayerPed(src)
    local pcoords = GetEntityCoords(ped)
    if Dist3(pcoords, vector3(x, y, z)) > (Config.Place.maxDistance or 5.0) + 2.0 then
        return
    end

    -- Find which item corresponds
    local itemName = nil
    for name, def in pairs(Config.PlaceableItems) do
        if def.category == category then
            itemName = name
            break
        end
    end
    if not itemName then return end

    local count = exports.ox_inventory:GetItemCount(src, itemName) or 0
    if count < 1 then return end

    local removed = exports.ox_inventory:RemoveItem(src, itemName, 1)
    if not removed then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    local owner = xPlayer and xPlayer.identifier or GetPlayerIdentifierByType(src, 'license') or ('src:' .. src)

    local model = GetBenchModel(category)
    local bench = Benches.InsertPlaced(owner, category, model, vector3(x + 0.0, y + 0.0, z + 0.0), heading + 0.0)
    if not bench then
        exports.ox_inventory:AddItem(src, itemName, 1)
        return
    end

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = _('place_success') })
    Benches.BroadcastSync()
end)

RegisterNetEvent('sanctuary_crafting:server:pickupBench', function(placedId)
    local src = source
    placedId = tonumber(placedId)
    local bench = placedId and Benches.GetPlaced(placedId)
    if not bench then return end

    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance + 1.0) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('craft_too_far') })
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local identifier = xPlayer and xPlayer.identifier or GetPlayerIdentifierByType(src, 'license')
    local isOwner = Config.Place.allowPickupOwner and identifier == bench.owner
    local isAdmin = Config.Place.allowPickupAdmin and Validation.IsAdmin(src)

    if not isOwner and not isAdmin then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('pickup_denied') })
        return
    end

    local itemName = nil
    for name, def in pairs(Config.PlaceableItems) do
        if def.category == bench.category then
            itemName = name
            break
        end
    end
    if not itemName then return end

    if not Benches.DeletePlaced(placedId) then return end

    local added = exports.ox_inventory:AddItem(src, itemName, 1)
    if not added then
        -- rollback insert
        Benches.InsertPlaced(bench.owner, bench.category, bench.model, bench.coords, bench.heading)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('craft_inventory_full') })
        Benches.BroadcastSync()
        return
    end

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = _('pickup_success') })
    Benches.BroadcastSync()
end)
