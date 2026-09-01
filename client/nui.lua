--[[
    client/nui.lua — bridge NUI (UI brief: industrial dark, accent #9a8866)
]]

local nuiOpen = false

local function useNui()
    return Config.UI and Config.UI.UseNui ~= false
end

function CloseCraftNui()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

function OpenCraftNui(menuData)
    if not useNui() then return false end
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = menuData })
    return true
end

RegisterNUICallback('close', function(_, cb)
    CloseCraftNui()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(data, cb)
    local menu = lib.callback.await('sanctuary_crafting:getMenu', false, data.benchKey)
    cb(menu or { ok = false })
end)

RegisterNUICallback('craft', function(data, cb)
    local start = lib.callback.await('sanctuary_crafting:startCraft', false, data.recipeId, data.benchKey, data.batch)
    cb(start or { ok = false })
end)

RegisterNUICallback('complete', function(data, cb)
    local result = lib.callback.await('sanctuary_crafting:completeCraft', false, data.craftId)
    cb(result or { ok = false })
end)

RegisterNUICallback('cancel', function(data, cb)
    TriggerServerEvent('sanctuary_crafting:server:cancelCraft', data.craftId)
    cb({ ok = true })
end)

RegisterNUICallback('favorite', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:toggleFavorite', false, data.recipeId)
    cb(r or { ok = false })
end)

RegisterNUICallback('queue', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:queueCraft', false, data.recipeId, data.benchKey, data.batch)
    cb(r or { ok = false })
end)

RegisterNUICallback('queueList', function(_, cb)
    local r = lib.callback.await('sanctuary_crafting:queueList', false)
    cb(r or { ok = true, queue = {} })
end)

RegisterNUICallback('queueCollect', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:queueCollect', false, data.craftId)
    cb(r or { ok = false })
end)

RegisterNUICallback('shopping', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:shoppingBuild', false, data.recipeId, data.batch)
    cb(r or { ok = false })
end)

RegisterNUICallback('shoppingClear', function(_, cb)
    local r = lib.callback.await('sanctuary_crafting:shoppingClear', false)
    cb(r or { ok = true })
end)

RegisterNUICallback('tree', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:craftTree', false, data.recipeId, 3)
    cb(r or { ok = false })
end)


RegisterNUICallback('bookUnpinRecipe', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:action', false, 'unpin', { recipeId = data.recipeId })
    cb(r or { ok = false })
end)

RegisterNUICallback('notify', function(data, cb)
    local desc = data.reason or 'craft_failed'
    if data.reason == 'craft_success' and data.label then
        desc = _('craft_success', 1, data.label)
    elseif type(data.args) == 'table' and #data.args > 0 then
        desc = _(desc, table.unpack(data.args))
    else
        desc = _(desc)
    end
    lib.notify({ type = data.type or 'inform', description = desc })
    cb({ ok = true })
end)

RegisterNetEvent('sanctuary_crafting:client:openBench', function(benchKey)
    OpenCraftMenu(benchKey)
end)

RegisterNetEvent('sanctuary_crafting:client:craftCancelled', function()
    -- NUI progress cleared by cancel callback
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then CloseCraftNui() end
end)
