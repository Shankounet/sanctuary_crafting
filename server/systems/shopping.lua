--[[
    shopping/shopping.lua — liste d'achats serveur (ingrédients manquants)
]]

ShoppingList = ShoppingList or {}
local lists = {} -- [src] = { [item]=count }

function ShoppingList.BuildFromRecipe(src, recipeId, batch)
    if not Config.ShoppingList or not Config.ShoppingList.Enabled then
        return nil, 'shopping_disabled'
    end
    local recipe = Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end
    batch = math.max(1, math.floor(tonumber(batch) or 1))
    local missing = {}
    for i = 1, #recipe.ingredients do
        local ing = recipe.ingredients[i]
        local need = (ing.count or 1) * batch
        local have = exports.ox_inventory:GetItemCount(src, ing.item) or 0
        if have < need then
            missing[ing.item] = (missing[ing.item] or 0) + (need - have)
        end
    end
    lists[src] = lists[src] or {}
    for item, count in pairs(missing) do
        lists[src][item] = (lists[src][item] or 0) + count
    end
    return lists[src]
end

function ShoppingList.Get(src)
    return lists[src] or {}
end

function ShoppingList.Clear(src)
    lists[src] = {}
    return true
end

function ShoppingList.Remove(src, item)
    if lists[src] then lists[src][item] = nil end
end

AddEventHandler('playerDropped', function()
    lists[source] = nil
end)

local function enrichShopMap(map)
    local out = {}
    for item, count in pairs(map or {}) do
        out[item] = {
            count = count,
            need = count,
            label = (OxItemCatalog and OxItemCatalog.Label and OxItemCatalog.Label(item)) or item,
        }
    end
    return out
end

lib.callback.register('sanctuary_crafting:shoppingBuild', function(src, recipeId, batch)
    local list, err = ShoppingList.BuildFromRecipe(src, recipeId, batch)
    if not list then return { ok = false, reason = err } end
    return { ok = true, list = enrichShopMap(list) }
end)

lib.callback.register('sanctuary_crafting:shoppingGet', function(src)
    return { ok = true, list = enrichShopMap(ShoppingList.Get(src)) }
end)

lib.callback.register('sanctuary_crafting:shoppingClear', function(src)
    ShoppingList.Clear(src)
    return { ok = true }
end)
