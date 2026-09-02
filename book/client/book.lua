--[[
    book/client/book.lua — ouverture NUI Carnet + mini HUD pins + artisans meet
]]

local bookOpen = false
local pins = {}
local miniHud = true
local pushPinsHud

local function bookEnabled()
    return Config.Book and Config.Book.Enabled ~= false
end

local function pinsFeatureOn()
    return bookEnabled()
        and Config.Book.Pins and Config.Book.Pins.Enabled ~= false
        and Config.Book.Pins.MiniHud ~= false
end

-- Kept for command / keybind; NUI owns hide via pinsVisible. Settings restore sets miniHud=true.
local function pinsHudEnabled()
    return pinsFeatureOn() and miniHud
end

function CloseSurvivalBook()
    if not bookOpen then return end
    bookOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'bookClose' })
    pushPinsHud()
end

local function bookFallbackMeta()
    local modules = {}
    local names = {
        'Dashboard', 'Progression', 'NextUnlocks', 'Objectives', 'Pins', 'Shopping', 'CraftTree',
        'Resources', 'Discoveries', 'Blueprints', 'Artisans', 'Network', 'Orders', 'Projects',
        'Notes', 'Search', 'Suggestions', 'CanCraft', 'Workshop', 'Maintenance', 'Productions',
        'Notifications', 'History', 'Stats',
    }
    for i = 1, #names do
        local key = names[i]
        local m = Config.Book and Config.Book[key]
        if m == nil then
            modules[key] = true
        elseif type(m) == 'table' then
            modules[key] = m.Enabled ~= false
        else
            modules[key] = true
        end
    end
    return {
        accent = (Config.Book and Config.Book.Accent) or '#9a8866',
        theme = (Config.Book and Config.Book.Theme) or 'field_manual',
        modules = modules,
        locale = Config.Locale or 'fr',
        title = (type(_) == 'function' and _('book_title')) or 'Carnet de survie',
        subtitle = (type(_) == 'function' and _('book_subtitle')) or 'Manuel de terrain',
    }
end

local function pushBookOpen(pageName, meta, lazy)
    SendNUIMessage({
        action = 'bookOpen',
        page = pageName,
        meta = meta or bookFallbackMeta(),
        lazy = lazy,
    })
end

function OpenSurvivalBook(page)
    if not bookEnabled() then
        lib.notify({ type = 'error', description = _('book_disabled') })
        return false
    end
    -- Close craft UI if open (clears craft focus)
    if CloseCraftNui then CloseCraftNui() end

    local pageName = page or 'dashboard'
    local lazy = Config.Book.LazyLoad ~= false
    local meta = bookFallbackMeta()

    -- Focus + repeated bookOpen (CEF often drops the first NUI message)
    bookOpen = true
    pushPinsHud()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    pushBookOpen(pageName, meta, lazy)
    pushBookOpen(pageName, meta, lazy)

    CreateThread(function()
        Wait(50)
        if not bookOpen then return end
        pushBookOpen(pageName, meta, lazy)
        Wait(150)
        if not bookOpen then return end
        pushBookOpen(pageName, meta, lazy)

        local okShell, shell = pcall(function()
            return lib.callback.await('sanctuary_crafting:book:shell', false)
        end)
        if okShell and type(shell) == 'table' and shell.meta then
            meta = shell.meta
            pushBookOpen(pageName, meta, lazy)
        elseif not okShell then
            print(('[^3sanctuary_crafting^0] book:shell failed: %s'):format(tostring(shell)))
        end

        local okPins, pinRes = pcall(function()
            return lib.callback.await('sanctuary_crafting:book:module', false, 'pins', {})
        end)
        if okPins and type(pinRes) == 'table' and pinRes.ok then
            pins = pinRes.data or {}
            SendNUIMessage({ action = 'bookPins', pins = pins })
        end
    end)

    return true
end

RegisterNetEvent('sanctuary_crafting:book:open', function(page)
    OpenSurvivalBook(page)
end)

RegisterNetEvent('sanctuary_crafting:book:pinsUpdated', function(list)
    pins = list or {}
    SendNUIMessage({ action = 'bookPins', pins = pins })
    pushPinsHud()
end)

RegisterNetEvent('sanctuary_crafting:book:resourceDiscovered', function(item, label)
    SendNUIMessage({ action = 'bookEvent', event = 'resourceDiscovered', item = item, label = label })
end)

RegisterNetEvent('sanctuary_crafting:book:artisanMet', function(contactId, name)
    SendNUIMessage({ action = 'bookEvent', event = 'artisanMet', contactId = contactId, name = name })
end)

RegisterNetEvent('sanctuary_crafting:book:objectiveCompleted', function(objId)
    SendNUIMessage({ action = 'bookEvent', event = 'objectiveCompleted', id = objId })
end)

-- NUI callbacks (lazy-load)
RegisterNUICallback('bookClose', function(_, cb)
    CloseSurvivalBook()
    cb({ ok = true })
end)

-- Never hold the NUI callback on a heavy lib.callback.await: in CEF a pending
-- NUI cb often stalls JS timers, so postWithTimeout never fires.
RegisterNUICallback('bookDashboard', function(_, cb)
    cb({ ok = true, pending = true })
    CreateThread(function()
        local ok, r = pcall(function()
            return lib.callback.await('sanctuary_crafting:book:dashboard', false)
        end)
        SendNUIMessage({
            action = 'bookDashboardResult',
            payload = (ok and type(r) == 'table' and r) or { ok = false },
        })
        Wait(0)
        local okE, extra = pcall(function()
            return lib.callback.await('sanctuary_crafting:book:module', false, 'dashboardExtra', {})
        end)
        if okE and type(extra) == 'table' then
            SendNUIMessage({
                action = 'bookDashboardExtra',
                payload = extra,
            })
        end
    end)
end)

RegisterNUICallback('bookModule', function(data, cb)
    local reqId = data and data.reqId
    cb({ ok = true, pending = true, reqId = reqId })
    CreateThread(function()
        local ok, r = pcall(function()
            return lib.callback.await('sanctuary_crafting:book:module', false, data.module, data.payload or {})
        end)
        SendNUIMessage({
            action = 'bookModuleResult',
            module = data and data.module,
            reqId = reqId,
            payload = (ok and type(r) == 'table' and r) or { ok = false },
        })
    end)
end)

RegisterNUICallback('bookAction', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:action', false, data.action, data.payload or {})
    if r and r.pins then
        pins = r.pins
        SendNUIMessage({ action = 'bookPins', pins = pins })
    end
    cb(r or { ok = false })
end)

RegisterNUICallback('bookToggleHud', function(data, cb)
    if data and data.toggle then
        miniHud = not miniHud
    elseif data and data.enabled == false then
        miniHud = false
    else
        miniHud = true
    end
    pcall(function()
        lib.callback.await('sanctuary_crafting:book:action', false, 'setPrefs', {
            prefs = { miniHud = miniHud },
        })
    end)
    pushPinsHud() -- real pins even if miniHud is false (NUI hides via display:none)
    cb({ ok = true, miniHud = miniHud })
end)

RegisterNUICallback('hudSettingsPins', function(data, cb)
    miniHud = not (data and data.visible == false)
    pcall(function()
        lib.callback.await('sanctuary_crafting:book:action', false, 'setPrefs', {
            prefs = { miniHud = miniHud },
        })
    end)
    pushPinsHud()
    cb({ ok = true, miniHud = miniHud })
end)

RegisterNUICallback('hudReset', function(_, cb)
    miniHud = true
    pcall(function()
        lib.callback.await('sanctuary_crafting:book:action', false, 'setPrefs', {
            prefs = { miniHud = true },
        })
    end)
    pushPinsHud()
    SendNUIMessage({ action = 'hud:reset' })
    cb({ ok = true, miniHud = true })
end)

-- Craft UI bridges: pin / objective / open book
RegisterNUICallback('bookPinRecipe', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:action', false, 'pin', { recipeId = data.recipeId })
    if r and r.pins then pins = r.pins; SendNUIMessage({ action = 'bookPins', pins = pins }); pushPinsHud() end
    cb(r or { ok = false })
end)

RegisterNUICallback('bookObjectiveRecipe', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:action', false, 'addObjectiveRecipe', {
        recipeId = data.recipeId,
        withMissing = data.withMissing,
    })
    cb(r or { ok = false })
end)

RegisterNUICallback('bookOpenFromCraft', function(data, cb)
    -- Acknowledge NUI callback before re-opening focus (avoids stalled CEF callback)
    cb({ ok = true })
    CloseCraftNui()
    Wait(50)
    OpenSurvivalBook(data and data.page or 'dashboard')
end)

local function collectActiveCrafts()
    if not (CraftTracker and CraftTracker.ListActive) then return {} end
    return CraftTracker.ListActive() or {}
end

pushPinsHud = function()
    local list = pins or {}
    local maxN = (Config.Book.Pins and Config.Book.Pins.HudMax) or 4
    local feature = pinsFeatureOn()
    -- Always send real pins + visible flag. Do NOT send pins=[] just because HUD hidden.
    SendNUIMessage({
        action = 'pinsHud',
        visible = feature and miniHud and not bookOpen and #list > 0,
        pins = list,
        crafts = collectActiveCrafts(),
        max = maxN,
        bookOpen = bookOpen,
        miniHud = miniHud,
        feature = feature,
    })
end

local function refreshPinsFromServer()
    local ok, pinRes = pcall(function()
        return lib.callback.await('sanctuary_crafting:book:module', false, 'pins', {})
    end)
    if ok and type(pinRes) == 'table' and pinRes.ok then
        pins = pinRes.data or pins
    end
end

-- Mini HUD NUI (no native text overlay)
CreateThread(function()
    Wait(2500)
    refreshPinsFromServer()
    pushPinsHud()
    while true do
        if pinsFeatureOn() then
            refreshPinsFromServer()
            pushPinsHud()
            Wait(bookOpen and 800 or 4000)
        else
            pushPinsHud()
            Wait(2000)
        end
    end
end)

-- Meet artisan: nearby player via ox_target (qualitative only)
CreateThread(function()
    if not bookEnabled() then return end
    if GetResourceState('ox_target') ~= 'started' then return end
    if not (Config.Book.Artisans and Config.Book.Artisans.Enabled ~= false) then return end

    exports.ox_target:addGlobalPlayer({
        {
            name = 'sanctuary_book_meet_artisan',
            icon = 'fas fa-address-book',
            label = _('book_meet_artisan'),
            distance = 2.0,
            onSelect = function(data)
                local entity = data.entity
                if not entity or not DoesEntityExist(entity) then return end
                local playerIdx = NetworkGetPlayerIndexFromPed(entity)
                if playerIdx == -1 then return end
                local targetSrc = GetPlayerServerId(playerIdx)
                local name = GetPlayerName(playerIdx) or ('Citoyen#' .. tostring(targetSrc))
                -- Qualitative only — no skill probe of other player
                lib.callback.await('sanctuary_crafting:book:action', false, 'addArtisan', {
                    contactId = 'player:' .. tostring(targetSrc),
                    displayName = name,
                    specialty = 'general',
                    tier = 'unknown',
                    source = 'ox_target',
                })
                lib.notify({ type = 'success', description = _('book_artisan_met', name) })
            end,
        },
    })
end)

-- Command convenience
RegisterCommand('carnet', function()
    OpenSurvivalBook('dashboard')
end, false)

RegisterCommand('carnet_pins', function()
    miniHud = not miniHud
    SendNUIMessage({ action = 'pinsHud:setVisible', visible = miniHud })
    pushPinsHud()
end, false)
RegisterKeyMapping('carnet_pins', 'Carnet — afficher/masquer épingles', 'keyboard', '')

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        CloseSurvivalBook()
        if GetResourceState('ox_target') == 'started' then
            pcall(function()
                exports.ox_target:removeGlobalPlayer('sanctuary_book_meet_artisan')
            end)
        end
    end
end)

-- Export client
-- ox_inventory CLIENT export (preferred for opening NUI from item use)
-- items: client = { export = 'sanctuary_crafting.useSurvivalBook' }
exports('useSurvivalBook', function(_data, _slot)
    OpenSurvivalBook('dashboard')
end)

exports('OpenSurvivalBook', OpenSurvivalBook)
exports('CloseSurvivalBook', CloseSurvivalBook)
