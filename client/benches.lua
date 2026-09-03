--[[
    Spawn / sync bancs monde + placeables, ox_target
    type = "coords" / spawnProp = false → zone ox_target (pas de prop)
]]

local spawned = {}       -- [key] = { entity|nil, zoneId|nil, data }
local targetIds = {}     -- [key] = true

local function removeBench(key)
    local entry = spawned[key]
    if not entry then return end
    if entry.entity and DoesEntityExist(entry.entity) then
        exports.ox_target:removeLocalEntity(entry.entity)
        DeleteEntity(entry.entity)
    end
    if entry.zoneId then
        exports.ox_target:removeZone(entry.zoneId)
    end
    spawned[key] = nil
    targetIds[key] = nil
end

local function addTarget(entity, data)
    local options = {
        {
            name = 'sanctuary_craft_open_' .. data.key,
            icon = 'fa-solid fa-hammer',
            label = _('open_craft'),
            distance = Config.InteractDistance or 2.5,
            onSelect = function()
                OpenCraftMenu(data.key)
            end,
        },
    }

    if data.kind == 'placed' then
        options[#options + 1] = {
            name = 'sanctuary_craft_pickup_' .. data.key,
            icon = 'fa-solid fa-hand',
            label = _('pickup_bench'),
            distance = Config.InteractDistance or 2.5,
            onSelect = function()
                TriggerServerEvent('sanctuary_crafting:server:pickupBench', data.id)
            end,
        }
    end

    exports.ox_target:addLocalEntity(entity, options)
end

local function addZoneTarget(data)
    local c = data.coords
    local radius = Config.InteractDistance or 2.5
    local zoneId = exports.ox_target:addSphereZone({
        coords = vec3(c.x, c.y, c.z),
        radius = radius,
        debug = Config.Debug or false,
        options = {
            {
                name = 'sanctuary_craft_open_' .. data.key,
                icon = 'fa-solid fa-hammer',
                label = data.label or _('open_craft'),
                distance = radius,
                onSelect = function()
                    OpenCraftMenu(data.key)
                end,
            },
        },
    })
    return zoneId
end

local function spawnBench(data)
    if spawned[data.key] then
        removeBench(data.key)
    end

    local useZone = (data.spawnProp == false) or (data.type == 'coords') or (data.model == nil and data.kind == 'world')
    if useZone and data.kind == 'world' then
        local zoneId = addZoneTarget(data)
        spawned[data.key] = { entity = nil, zoneId = zoneId, data = data }
        targetIds[data.key] = true
        return
    end

    local model = data.model
    if type(model) == 'string' then
        model = joaat(model)
    end
    if not model or model == 0 then
        model = GetBenchModel(data.category) or `prop_tool_bench02`
    end

    lib.requestModel(model, 5000)
    local c = data.coords
    local obj = CreateObject(model, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(obj, data.heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(model)

    -- re-read coords after ground snap for world benches with fixed z preference
    if data.kind == 'world' then
        SetEntityCoords(obj, c.x, c.y, c.z, false, false, false, false)
        SetEntityHeading(obj, data.heading or 0.0)
        FreezeEntityPosition(obj, true)
    end

    spawned[data.key] = { entity = obj, data = data }
    addTarget(obj, data)
end

function SyncBenches(list)
    local keep = {}
    for i = 1, #(list or {}) do
        local data = list[i]
        keep[data.key] = true
        local existing = spawned[data.key]
        if not existing then
            spawnBench(data)
        else
            -- update coords if moved (rare)
            existing.data = data
        end
    end
    for key in pairs(spawned) do
        if not keep[key] then
            removeBench(key)
        end
    end
end

RegisterNetEvent('sanctuary_crafting:client:syncBenches', function(list)
    SyncBenches(list)
end)

CreateThread(function()
    Wait(500)
    TriggerServerEvent('sanctuary_crafting:server:requestSync')
end)


--- Resolve bench coords for proximity checks (tracker click → open RÉCUP).
---@param benchKey string
---@return vector3|table|nil
function GetClientBenchCoords(benchKey)
    if type(benchKey) ~= 'string' or benchKey == '' then return nil end
    local entry = spawned[benchKey]
    if entry then
        if entry.entity and DoesEntityExist(entry.entity) then
            return GetEntityCoords(entry.entity)
        end
        if entry.data and entry.data.coords then
            return entry.data.coords
        end
    end
    local worldId = benchKey:match('^world:(.+)$')
    if worldId then
        for i = 1, #(Config.WorldBenches or {}) do
            local w = Config.WorldBenches[i]
            if w and w.id == worldId and w.coords then
                return w.coords
            end
        end
    end
    -- bare id without world: prefix
    for i = 1, #(Config.WorldBenches or {}) do
        local w = Config.WorldBenches[i]
        if w and (w.id == benchKey or w.key == benchKey) and w.coords then
            return w.coords
        end
    end
    return nil
end

-- Blips monde (si Config.WorldBenches[].blip)
CreateThread(function()
    Wait(1000)
    for i = 1, #(Config.WorldBenches or {}) do
        local w = Config.WorldBenches[i]
        if w.blip and w.coords then
            local blip = AddBlipForCoord(w.coords.x, w.coords.y, w.coords.z)
            SetBlipSprite(blip, w.blip.sprite or 566)
            SetBlipScale(blip, w.blip.size or 0.8)
            SetBlipColour(blip, w.blip.color or 5)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(w.blip.name or w.label or 'Craft')
            EndTextCommandSetBlipName(blip)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(spawned) do
        removeBench(key)
    end
end)

--- Admin preview: print coords for Config.WorldBenches
RegisterNetEvent('sanctuary_crafting:client:adminPreviewBench', function(category)
    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local model = GetBenchModel(category)
    lib.requestModel(model, 5000)
    local obj = CreateObject(model, coords.x, coords.y, coords.z - 1.0, false, false, false)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)

    local c = GetEntityCoords(obj)
    lib.notify({
        type = 'success',
        description = _('admin_place_ok', category),
        duration = 8000,
    })
    print(('[sanctuary_crafting] WorldBench %s → coords = vec3(%.2f, %.2f, %.2f), heading = %.1f'):format(
        category, c.x, c.y, c.z, heading
    ))

    SetTimeout(15000, function()
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end)
end)

-- Heat particles (Config.Stations.Heat.Particles, default off)
RegisterNetEvent('sanctuary_crafting:client:heatFx', function(coords, temp)
    local h = Config.Stations and Config.Stations.Heat
    if not h or h.Particles ~= true then return end
    if not coords then return end
    -- Light smoke only when explicitly enabled; no mix-blend / extra assets.
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('ent_sht_steam', coords.x or coords[1], coords.y or coords[2], (coords.z or coords[3] or 0) + 0.4, 0.0, 0.0, 0.0, 0.4, false, false, false)
end)
