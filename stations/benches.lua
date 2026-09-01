--[[
    stations/benches.lua — monde + SQL placeables + niveaux/upgrades/modules
]]

Benches = Benches or {}

local worldEntities = {}
local placedBenches = {} -- [id] = bench

local function benchKey(kind, id)
    return ('%s:%s'):format(kind, tostring(id))
end

function Benches.GetWorld(id) return worldEntities[id] end
function Benches.GetPlaced(id) return placedBenches[id] end

---@param key string
---@return table|nil
function Benches.Resolve(key)
    if not key or type(key) ~= 'string' then return nil end
    local kind, id = key:match('^(%w+):(.+)$')
    if kind == 'world' then return worldEntities[id] end
    if kind == 'placed' then
        local num = tonumber(id)
        return num and placedBenches[num] or nil
    end
    return nil
end

function Benches.GetAllForClient()
    local list = {}
    for id, b in pairs(worldEntities) do
        list[#list + 1] = {
            key = b.key, kind = 'world', id = id, category = b.category,
            coords = b.coords, heading = b.heading, model = b.model,
            stationLevel = b.stationLevel or 1, modules = b.modules or {},
            powered = CraftingPower.HasPower(b),
        }
    end
    for id, b in pairs(placedBenches) do
        list[#list + 1] = {
            key = b.key, kind = 'placed', id = id, owner = b.owner,
            category = b.category, coords = b.coords, heading = b.heading,
            model = b.model, stationLevel = b.stationLevel or 1,
            modules = b.modules or {}, powered = CraftingPower.HasPower(b),
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
            key = benchKey('world', id), kind = 'world', id = id,
            category = w.category, coords = w.coords, heading = w.heading or 0.0,
            model = w.model or GetBenchModel(w.category),
            stationLevel = w.stationLevel or (Config.Stations and Config.Stations.DefaultLevel) or 1,
            modules = w.modules or {},
        }
    end
end

local function decodeJson(s, fallback)
    if not s or s == '' then return fallback end
    local ok, data = pcall(json.decode, s)
    if ok and data then return data end
    return fallback
end

local function rowToBench(row)
    local id = tonumber(row.id)
    return {
        key = benchKey('placed', id), kind = 'placed', id = id,
        owner = row.owner, category = row.category,
        coords = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0),
        heading = row.heading + 0.0,
        model = joaat(row.model), modelName = row.model,
        stationLevel = tonumber(row.station_level) or 1,
        modules = decodeJson(row.modules, {}),
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

local PROP_NAMES = {
    scrap = 'prop_tool_bench02', medical = 'prop_table_03',
    weapons = 'prop_toolchest_05', survival = 'prop_washer_01',
    mechanic = 'prop_toolchest_01',
}

function Benches.InsertPlaced(owner, category, modelHash, coords, heading, stationLevel, modules)
    local modelName = PROP_NAMES[category] or tostring(modelHash)
    local level = stationLevel or (Config.Stations and Config.Stations.DefaultLevel) or 1
    local mods = modules or {}
    local insertId = MySQL.insert.await(
        'INSERT INTO sanctuary_placed_benches (owner, category, model, x, y, z, heading, station_level, modules) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { owner, category, modelName, coords.x, coords.y, coords.z, heading, level, json.encode(mods) }
    )
    if not insertId then return nil end
    local b = {
        key = benchKey('placed', insertId), kind = 'placed', id = insertId,
        owner = owner, category = category, coords = coords, heading = heading,
        model = modelHash, modelName = modelName, stationLevel = level, modules = mods,
    }
    placedBenches[insertId] = b
    return b
end

function Benches.DeletePlaced(id)
    id = tonumber(id)
    if not id or not placedBenches[id] then return false end
    MySQL.query.await('DELETE FROM sanctuary_placed_benches WHERE id = ?', { id })
    placedBenches[id] = nil
    return true
end

--- Upgrade station level (Config.Stations.UpgradesEnabled)
function Benches.Upgrade(src, key)
    if not Config.Stations or not Config.Stations.UpgradesEnabled then
        return false, 'upgrade_disabled'
    end
    local bench = Benches.Resolve(key)
    if not bench or bench.kind ~= 'placed' then return false, 'craft_invalid' end
    local max = Config.Stations.MaxLevel or 5
    if (bench.stationLevel or 1) >= max then return false, 'upgrade_max' end

    local nextLevel = (bench.stationLevel or 1) + 1
    local upgrades = (Config.Stations.Upgrades or {})[bench.category]
    local req = upgrades and upgrades[nextLevel]
    if req and req.costItems then
        if not Validation.HasIngredients(src, req.costItems) then
            return false, 'craft_no_ingredients'
        end
        for i = 1, #req.costItems do
            local c = req.costItems[i]
            if not exports.ox_inventory:RemoveItem(src, c.item, c.count) then
                return false, 'craft_no_ingredients'
            end
        end
    end
    if req and req.requireLevel then
        local ok = CraftingSkills.HasRequiredLevel(Config.Skills.craftingCategory, req.requireLevel, src)
        if not ok then return false, 'craft_level_required' end
    end

    bench.stationLevel = nextLevel
    MySQL.update.await('UPDATE sanctuary_placed_benches SET station_level = ? WHERE id = ?', { nextLevel, bench.id })
    Benches.BroadcastSync()
    CraftingCore.Emit('stationUpgraded', src, bench)
    return true, nextLevel
end

--- Attach module to station
function Benches.AddModule(src, key, moduleId)
    if not Config.Stations or not Config.Stations.UpgradesEnabled then
        return false, 'upgrade_disabled'
    end
    local bench = Benches.Resolve(key)
    if not bench or bench.kind ~= 'placed' then return false, 'craft_invalid' end
    bench.modules = bench.modules or {}
    for i = 1, #bench.modules do
        if bench.modules[i] == moduleId then return false, 'module_exists' end
    end
    bench.modules[#bench.modules + 1] = moduleId
    MySQL.update.await('UPDATE sanctuary_placed_benches SET modules = ? WHERE id = ?', {
        json.encode(bench.modules), bench.id
    })
    Benches.BroadcastSync()
    return true
end

function Benches.MeetsStationLevel(bench, recipe)
    if not recipe.stationLevel then return true end
    return (bench.stationLevel or 1) >= recipe.stationLevel
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
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_placed_benches` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(60) NOT NULL,
            `category` VARCHAR(32) NOT NULL DEFAULT 'scrap',
            `model` VARCHAR(64) NOT NULL,
            `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
            `heading` FLOAT NOT NULL DEFAULT 0,
            `station_level` INT NOT NULL DEFAULT 1,
            `modules` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), KEY `idx_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    -- migrate columns if table existed without them
    pcall(function()
        MySQL.query.await('ALTER TABLE sanctuary_placed_benches ADD COLUMN station_level INT NOT NULL DEFAULT 1')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE sanctuary_placed_benches ADD COLUMN modules LONGTEXT NULL')
    end)
    Benches.LoadPlaced()
    Wait(1000)
    Benches.BroadcastSync()
end)

RegisterNetEvent('sanctuary_crafting:server:requestSync', function()
    Benches.BroadcastSync(source)
end)

RegisterNetEvent('sanctuary_crafting:server:placeBench', function(category, coords, heading)
    local src = source
    if type(category) ~= 'string' or not IsValidBenchCategory(category) then return end
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end
    local x, y, z = coords.x or coords[1], coords.y or coords[2], coords.z or coords[3]
    if not x then return end
    heading = tonumber(heading) or 0.0
    local ped = GetPlayerPed(src)
    if Dist3(GetEntityCoords(ped), vector3(x, y, z)) > (Config.Place.maxDistance or 5.0) + 2.0 then return end

    local itemName
    for name, def in pairs(Config.PlaceableItems) do
        if def.category == category then itemName = name break end
    end
    if not itemName then return end
    if (exports.ox_inventory:GetItemCount(src, itemName) or 0) < 1 then return end
    if not exports.ox_inventory:RemoveItem(src, itemName, 1) then return end

    local owner = GetPlayerIdentifierSafe(src) or ('src:' .. src)
    local model = GetBenchModel(category)
    local bench = Benches.InsertPlaced(owner, category, model, vector3(x+0.0,y+0.0,z+0.0), heading+0.0)
    if not bench then
        exports.ox_inventory:AddItem(src, itemName, 1)
        return
    end
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = _('place_success') })
    CraftingCore.Emit('stationPlaced', src, bench)
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
    local identifier = GetPlayerIdentifierSafe(src)
    if not CraftingPermissions.CanPickupStation(src, bench, identifier) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('pickup_denied') })
        return
    end
    local itemName
    for name, def in pairs(Config.PlaceableItems) do
        if def.category == bench.category then itemName = name break end
    end
    if not itemName then return end
    if not Benches.DeletePlaced(placedId) then return end
    if not exports.ox_inventory:AddItem(src, itemName, 1) then
        Benches.InsertPlaced(bench.owner, bench.category, bench.model, bench.coords, bench.heading, bench.stationLevel, bench.modules)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('craft_inventory_full') })
        Benches.BroadcastSync()
        return
    end
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = _('pickup_success') })
    CraftingCore.Emit('stationPickedUp', src, placedId)
    Benches.BroadcastSync()
end)

lib.callback.register('sanctuary_crafting:upgradeStation', function(src, key)
    local ok, result = Benches.Upgrade(src, key)
    return { ok = ok, result = result }
end)

lib.callback.register('sanctuary_crafting:addStationModule', function(src, key, moduleId)
    local ok, err = Benches.AddModule(src, key, moduleId)
    return { ok = ok, reason = err }
end)
