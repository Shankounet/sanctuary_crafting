--[[
    client/nui.lua — bridge NUI (UI brief: industrial dark, accent #9a8866)
]]

local nuiOpen = false
local lastBenchKey = nil

local function useNui()
    return Config.UI and Config.UI.UseNui ~= false
end

local function trackerEnabled()
    return Config.CraftTracker and Config.CraftTracker.Enabled ~= false and CraftTracker
end

function CloseCraftNui()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    -- Keep tracker alive: main craft UI close only (do NOT cancel active crafts)
    SendNUIMessage({ action = 'close', keepTracker = true })
    if trackerEnabled() then
        CraftTracker.SetMenuOpen(false)
    end
end

local function applySessionToTracker(session, benchKey)
    if not trackerEnabled() or type(session) ~= 'table' then return end
    local key = benchKey or lastBenchKey
    if CraftTracker.SetLastBench and key then
        CraftTracker.SetLastBench(key)
    end
    if CraftTracker.ApplySession then
        CraftTracker.ApplySession(key, session)
    else
        -- Fallback: upsert active + queued individually
        for _, a in ipairs(session.active or {}) do
            if CraftTracker.FromSessionActive then
                local e = CraftTracker.FromSessionActive(a)
                if e then CraftTracker.Upsert(e) end
            end
        end
        for _, q in ipairs(session.queued or {}) do
            local e = CraftTracker.FromQueueEntry and CraftTracker.FromQueueEntry(q)
            if e then CraftTracker.Upsert(e) end
        end
    end
end

function OpenCraftNui(menuData)
    if not useNui() then return false end
    nuiOpen = true
    if menuData and menuData.benchKey then
        lastBenchKey = menuData.benchKey
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = menuData })
    if trackerEnabled() then
        if lastBenchKey and CraftTracker.SetLastBench then
            CraftTracker.SetLastBench(lastBenchKey)
        end
        -- Upsert station session so tracker RAM matches pipeline (replace jobs for this bench)
        if menuData and menuData.session then
            applySessionToTracker(menuData.session, lastBenchKey)
        end
        CraftTracker.SetMenuOpen(true)
        CraftTracker.Sync()
    end
    return true
end

RegisterNUICallback('close', function(_, cb)
    CloseCraftNui()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(data, cb)
    local benchKey = data and data.benchKey or lastBenchKey
    if benchKey then lastBenchKey = benchKey end
    local menu = lib.callback.await('sanctuary_crafting:getMenu', false, benchKey)
    if menu and menu.ok and menu.session then
        applySessionToTracker(menu.session, benchKey)
    end
    cb(menu or { ok = false })
end)

RegisterNUICallback('getCraftSession', function(data, cb)
    local benchKey = (data and data.benchKey) or lastBenchKey
    if benchKey then lastBenchKey = benchKey end
    local r = lib.callback.await('sanctuary_crafting:getCraftSession', false, benchKey)
    if r and r.ok and r.session then
        applySessionToTracker(r.session, benchKey)
    end
    cb(r or { ok = false })
end)

RegisterNUICallback('craft', function(data, cb)
    local start = lib.callback.await('sanctuary_crafting:startCraft', false, data.recipeId, data.benchKey, data.batch)
    if start and start.ok and trackerEnabled() then
        local entry = CraftTracker.FromStart(start, {
            recipeId = data.recipeId,
            benchKey = data.benchKey,
            batch = data.batch,
            label = start.label,
            item = start.resultItem,
            count = start.resultCount,
            category = start.category or start.phaseFamily,
            benchLabel = start.benchLabel,
        })
        if entry then
            CraftTracker.Upsert(entry)
        end
    end
    cb(start or { ok = false })
end)

RegisterNUICallback('complete', function(data, cb)
    local result = lib.callback.await('sanctuary_crafting:completeCraft', false, data.craftId)
    if trackerEnabled() and data.craftId then
        if result and result.ok and result.advanced then
            local duration = tonumber(result.duration) or 0
            local started = GetGameTimer()
            CraftTracker.Upsert({
                craftId = data.craftId,
                status = 'active',
                startedAt = started,
                endsAt = started + duration,
                duration = duration,
                stepIndex = result.stepIndex,
                totalSteps = result.totalSteps,
                stepLabel = result.stepLabel or result.label,
                label = result.label,
                clientTimer = started,
                wallNow = (os.time and os.time() or 0) * 1000,
            })
        elseif result and result.ok then
            CraftTracker.Upsert({
                craftId = data.craftId,
                status = 'done',
                stepLabel = 'FABRICATION TERMINÉE',
                label = result.label,
                item = result.result and result.result.item,
                count = result.result and result.result.count,
            })
        elseif result and result.reason ~= 'craft_invalid' then
            CraftTracker.Upsert({
                craftId = data.craftId,
                status = 'error',
                stepLabel = 'Erreur',
            })
        end
    end
    cb(result or { ok = false })
end)

RegisterNUICallback('cancel', function(data, cb)
    TriggerServerEvent('sanctuary_crafting:server:cancelCraft', data.craftId)
    if trackerEnabled() and data.craftId then
        CraftTracker.Remove(data.craftId)
    end
    cb({ ok = true })
end)

RegisterNUICallback('favorite', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:toggleFavorite', false, data.recipeId)
    cb(r or { ok = false })
end)

RegisterNUICallback('queue', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:queueCraft', false, data.recipeId, data.benchKey, data.batch)
    if r and r.ok and r.entry and trackerEnabled() then
        local qe = CraftTracker.FromQueueEntry(r.entry, {
            recipeId = data.recipeId,
            benchKey = data.benchKey,
            batch = data.batch,
        })
        if qe then CraftTracker.Upsert(qe) end
    end
    cb(r or { ok = false })
end)

RegisterNUICallback('queueList', function(_, cb)
    local r = lib.callback.await('sanctuary_crafting:queueList', false)
    cb(r or { ok = true, queue = {} })
end)

RegisterNUICallback('queueCollect', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:queueCollect', false, data.craftId)
    if trackerEnabled() and data.craftId and r and r.ok then
        CraftTracker.Remove(data.craftId)
    end
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

RegisterNUICallback('pathHints', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:pathHints', false, data and data.recipeId)
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

RegisterNetEvent('sanctuary_crafting:client:craftCancelled', function(craftId)
    if trackerEnabled() and craftId then
        CraftTracker.Remove(craftId)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then CloseCraftNui() end
end)
