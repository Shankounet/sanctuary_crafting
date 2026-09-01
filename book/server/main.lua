--[[
    book/server/main.lua — boot + item export survival_book + public exports
]]

CreateThread(function()
    if not BookDB.Enabled() then
        print('[^3sanctuary_crafting^0] Survival Book désactivé (Config.Book.Enabled=false)')
        return
    end
    BookDB.Ensure()
    print(('[^2sanctuary_crafting^0] Survival Book prêt — item=%s accent=%s'):format(
        (Config.Book and Config.Book.ItemName) or 'survival_book',
        (Config.Book and Config.Book.Accent) or '#9a8866'
    ))
end)

local function openBookFor(src, page)
    if not BookDB.Enabled() then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('book_disabled') })
        return false
    end
    TriggerClientEvent('sanctuary_crafting:book:open', src, page or 'dashboard')
    return true
end

--- ox_inventory SERVER export (also keep client export — see book/client/book.lua)
--- Prefer CLIENT export for UI: client = { export = 'sanctuary_crafting.useSurvivalBook' }
exports('useSurvivalBook', function(event, item, inventory, slot, data)
    if event == 'usingItem' or event == 'usedItem' then
        local src = inventory and inventory.id
        if type(src) ~= 'number' then
            src = source
        end
        if type(src) == 'number' and src > 0 then
            openBookFor(src, 'dashboard')
        end
        return false -- don't consume
    end
end)

-- ESX usable fallback if item has no ox export wired
CreateThread(function()
    local itemName = (Config.Book and Config.Book.ItemName) or 'survival_book'
    if GetResourceState('es_extended') ~= 'started' then return end
    pcall(function()
        local ESX = exports['es_extended']:getSharedObject()
        if ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(itemName, function(src)
                openBookFor(src, 'dashboard')
            end)
            print(('[^2sanctuary_crafting^0] ESX usable item registered: %s'):format(itemName))
        end
    end)
end)

exports('OpenSurvivalBook', function(src, page)
    return openBookFor(src, page)
end)

exports('DiscoverResource', function(src, item, label, reason)
    return SurvivalBook.DiscoverResource(src, item, label, reason)
end)

exports('HasDiscoveredResource', function(src, item)
    return SurvivalBook.HasDiscoveredResource(src, item)
end)

exports('AddObjective', function(src, title, kind, payload)
    return SurvivalBook.AddObjective(src, title, kind, payload)
end)

exports('PinRecipe', function(src, recipeId)
    return SurvivalBook.PinRecipe(src, recipeId)
end)

exports('UnpinRecipe', function(src, recipeId)
    return SurvivalBook.UnpinRecipe(src, recipeId)
end)

exports('AddArtisanContact', function(src, contact)
    return SurvivalBook.AddArtisanContact(src, contact)
end)

exports('GetBookPins', function(src)
    return SurvivalBook.ListPins(src)
end)

exports('GetBookStats', function(src)
    return SurvivalBook.Stats(src)
end)

lib.callback.register('sanctuary_crafting:book:openAllowed', function(src)
    return BookDB.Enabled()
end)

RegisterNetEvent('sanctuary_crafting:book:requestOpen', function(page)
    local src = source
    openBookFor(src, page)
end)
