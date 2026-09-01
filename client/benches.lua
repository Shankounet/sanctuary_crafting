--[[
    Spawn / sync bancs monde + placeables, ox_target
]]

local spawned = {}       -- [key] = { entity, data }
local targetIds = {}     -- [key] = true

local function removeBench(key)
    local entry = spawned[key]
    if entry and entry.entity and DoesEntityExist(entry.entity) then
        exports.ox_target:removeLocalEntity(entry.entity)
        DeleteEntity(entry.entity)
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

local function spawnBench(data)
    if spawned[data.key] then
        removeBench(data.key)
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
