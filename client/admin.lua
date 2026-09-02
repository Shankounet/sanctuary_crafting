--[[
    client/admin.lua — /craftadmin NUI (NEW overlay, does not touch player craft UI)
]]

local adminOpen = false

local function cmdName()
    return (Config.Admin and Config.Admin.Command) or 'craftadmin'
end

local function closeAdmin()
    if not adminOpen then return end
    adminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'craftadminClose' })
end

local function openAdmin()
    local meta = lib.callback.await('sanctuary_crafting:craftadminMeta', false)
    if not meta or not meta.ok then
        lib.notify({ type = 'error', description = _(meta and meta.reason or 'admin_denied') })
        return
    end
    adminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'craftadminOpen', meta = meta.meta or {} })
end

RegisterCommand(cmdName(), function()
    if adminOpen then
        closeAdmin()
        return
    end
    openAdmin()
end, false)

RegisterNUICallback('craftadminClose', function(_, cb)
    closeAdmin()
    cb({ ok = true })
end)

local function proxy(name)
    RegisterNUICallback(name, function(data, cb)
        local r = lib.callback.await('sanctuary_crafting:' .. name, false,
            data and data.a, data and data.b, data and data.c, data and data.d)
        cb(r or { ok = false })
    end)
end

-- Named callbacks with explicit args (clearer than generic proxy)
RegisterNUICallback('craftadminList', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminList', false, data) or { ok = false })
end)
RegisterNUICallback('craftadminGet', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminGet', false, data and data.recipeId) or { ok = false })
end)
RegisterNUICallback('craftadminPreview', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminPreview', false, data) or { ok = false })
end)
RegisterNUICallback('craftadminValidate', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminValidate', false, data) or { ok = false })
end)
RegisterNUICallback('craftadminSave', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminSave', false, data, data and data.confirm == true) or { ok = false })
end)
RegisterNUICallback('craftadminCreate', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminCreate', false, data, data and data.confirm == true) or { ok = false })
end)
RegisterNUICallback('craftadminDisable', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminDisable', false, data and data.recipeId, data and data.disabled) or { ok = false })
end)
RegisterNUICallback('craftadminDelete', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminDelete', false, data and data.recipeId) or { ok = false })
end)
RegisterNUICallback('craftadminDuplicate', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminDuplicate', false, data and data.recipeId, data and data.newId) or { ok = false })
end)
RegisterNUICallback('craftadminSearchOx', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminSearchOx', false, data and data.q, data and data.limit) or { ok = true, items = {} })
end)
RegisterNUICallback('craftadminTest', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminTest', false, data and data.recipeId, data and data.benchKey, data and data.batch, data and data.real == true) or { ok = false })
end)
RegisterNUICallback('craftadminVersions', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminVersions', false, data and data.recipeId) or { ok = true, versions = {} })
end)
RegisterNUICallback('craftadminRestore', function(data, cb)
    cb(lib.callback.await('sanctuary_crafting:craftadminRestore', false, data and data.recipeId, data and data.version) or { ok = false })
end)

-- Client façade (OpenStation already exists via openBench event)
exports('OpenStation', function(benchKey)
    if OpenCraftMenu then OpenCraftMenu(benchKey) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then closeAdmin() end
end)
