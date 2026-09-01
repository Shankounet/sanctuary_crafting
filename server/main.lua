--[[
    sanctuary_crafting — server bootstrap
]]

local function registerPlaceableHooks()
    for itemName, def in pairs(Config.PlaceableItems or {}) do
        -- ox_inventory export-style usable via event from client item use
        -- We also support server export called from items.lua
        DebugPrint('Placeable item registered:', itemName, def.category)
    end
end

--- Export pour ox_inventory items.lua : server.export = 'sanctuary_crafting.useBenchItem'
exports('useBenchItem', function(event, item, inventory, slot, data)
    -- ox_inventory server export pattern
    if event == 'usingItem' then
        local src = inventory.id
        local itemName = item.name
        local def = Config.PlaceableItems[itemName]
        if not def then return false end
        TriggerClientEvent('sanctuary_crafting:client:startPlace', src, def.category, itemName)
        return false -- ne consomme pas ici ; consommé à la confirmation serveur
    end
end)

CreateThread(function()
    registerPlaceableHooks()
    print(('[^2sanctuary_crafting^0] démarré — %d recettes, %d bancs monde'):format(
        #Config.Recipes,
        #(Config.WorldBenches or {})
    ))
end)

if Config.EnableWorldBenchCommand then
    RegisterCommand(Config.WorldBenchCommand or 'placeworldbench', function(src, args)
        if src == 0 then
            print('Commande in-game uniquement')
            return
        end
        if not Validation.IsAdmin(src) then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('admin_denied') })
            return
        end
        local category = args[1] or 'scrap'
        if not IsValidBenchCategory(category) then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                description = _('admin_place_usage'),
            })
            return
        end
        TriggerClientEvent('sanctuary_crafting:client:adminPreviewBench', src, category)
    end, false)
end
