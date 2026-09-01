--[[
    core/boot.lua — bootstrap serveur
]]

local function registerPlaceableHooks()
    for itemName, def in pairs(Config.PlaceableItems or {}) do
        DebugPrint('Placeable item:', itemName, def.category)
    end
end

exports('useBenchItem', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        local src = inventory.id
        local itemName = item.name
        local def = Config.PlaceableItems[itemName]
        if not def then return false end
        TriggerClientEvent('sanctuary_crafting:client:startPlace', src, def.category, itemName)
        return false
    end
end)

-- Public exports for other resources
exports('GetRecipe', function(id)
    return RecipeRegistry and RecipeRegistry.Get(id)
end)

exports('GetRecipesForCategory', function(category)
    return GetRecipesForCategory(category)
end)

exports('IsCrafting', function(src)
    return CraftingPipeline and CraftingPipeline.HasActive(src)
end)

CreateThread(function()
    registerPlaceableHooks()
    local nRecipes = RecipeRegistry and select(1, RecipeRegistry.Rebuild()) or #(Config.Recipes or {})
    print(('[^2sanctuary_crafting^0] v%s — %d recettes, %d bancs monde | NUI=%s Blueprints=%s Quality=%s Queue=%s'):format(
        Config.Version or '?',
        type(nRecipes) == 'number' and nRecipes or #(Config.Recipes or {}),
        #(Config.WorldBenches or {}),
        tostring(Config.UI and Config.UI.UseNui),
        tostring(Config.Blueprints and Config.Blueprints.Enabled),
        tostring(Config.Quality and Config.Quality.Enabled),
        tostring(Config.Queue and Config.Queue.Enabled)
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
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('admin_place_usage') })
            return
        end
        TriggerClientEvent('sanctuary_crafting:client:adminPreviewBench', src, category)
    end, false)
end
