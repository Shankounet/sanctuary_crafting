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

--- ox_inventory server export
exports('useSurvivalBook', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        local src = inventory.id
        openBookFor(src, 'dashboard')
        return false -- don't consume
    end
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
