--[[
    book/client/book.lua — ouverture NUI Carnet + mini HUD pins + artisans meet
]]

local bookOpen = false
local pins = {}
local miniHud = true

local function bookEnabled()
    return Config.Book and Config.Book.Enabled ~= false
end

local function pinsHudEnabled()
    return bookEnabled()
        and Config.Book.Pins and Config.Book.Pins.Enabled ~= false
        and Config.Book.Pins.MiniHud ~= false
        and miniHud
end

function CloseSurvivalBook()
    if not bookOpen then return end
    bookOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'bookClose' })
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
        title = _('book_title'),
        subtitle = _('book_subtitle'),
    }
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

    -- Show NUI FIRST, then focus — never leave mouse up with a blank page if shell awaits/errors
    bookOpen = true
    SendNUIMessage({
        action = 'bookOpen',
        page = pageName,
        meta = bookFallbackMeta(),
        lazy = lazy,
    })
    SetNuiFocus(true, true)

    local okShell, shell = pcall(function()
        return lib.callback.await('sanctuary_crafting:book:shell', false)
    end)
    if okShell and type(shell) == 'table' and shell.meta then
        SendNUIMessage({
            action = 'bookOpen',
            page = pageName,
            meta = shell.meta,
            lazy = lazy,
        })
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
    return true
end

RegisterNetEvent('sanctuary_crafting:book:open', function(page)
    OpenSurvivalBook(page)
end)

RegisterNetEvent('sanctuary_crafting:book:pinsUpdated', function(list)
    pins = list or {}
    SendNUIMessage({ action = 'bookPins', pins = pins })
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

RegisterNUICallback('bookDashboard', function(_, cb)
    local r = lib.callback.await('sanctuary_crafting:book:dashboard', false)
    cb(r or { ok = false })
end)

RegisterNUICallback('bookModule', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:module', false, data.module, data.payload or {})
    cb(r or { ok = false })
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
    miniHud = data.enabled ~= false
    local prefs = lib.callback.await('sanctuary_crafting:book:action', false, 'setPrefs', {
        prefs = { miniHud = miniHud },
    })
    cb({ ok = true, miniHud = miniHud })
end)

-- Craft UI bridges: pin / objective / open book
RegisterNUICallback('bookPinRecipe', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:action', false, 'pin', { recipeId = data.recipeId })
    if r and r.pins then pins = r.pins; SendNUIMessage({ action = 'bookPins', pins = pins }) end
    cb(r or { ok = false })
end)

RegisterNUICallback('bookObjectiveRecipe', function(data, cb)
    local r = lib.callback.await('sanctuary_crafting:book:action', false, 'addObjectiveRecipe', { recipeId = data.recipeId })
    cb(r or { ok = false })
end)

RegisterNUICallback('bookOpenFromCraft', function(data, cb)
    -- Acknowledge NUI callback before re-opening focus (avoids stalled CEF callback)
    cb({ ok = true })
    CloseCraftNui()
    Wait(50)
    OpenSurvivalBook(data and data.page or 'dashboard')
end)

-- Mini HUD draw
CreateThread(function()
    while true do
        if pinsHudEnabled() and not bookOpen and #pins > 0 then
            local y = 0.02
            SetTextFont(4)
            SetTextScale(0.32, 0.32)
            SetTextColour(154, 136, 102, 220)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(_('book_hud_title'))
            EndTextCommandDisplayText(0.84, y)
            y = y + 0.018
            for i = 1, math.min(#pins, 5) do
                SetTextFont(4)
                SetTextScale(0.28, 0.28)
                SetTextColour(230, 228, 223, 200)
                SetTextOutline()
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('• %s'):format(pins[i].label or pins[i].recipeId))
                EndTextCommandDisplayText(0.84, y)
                y = y + 0.016
            end
            Wait(0)
        else
            Wait(500)
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
exports('OpenSurvivalBook', OpenSurvivalBook)
exports('CloseSurvivalBook', CloseSurvivalBook)
