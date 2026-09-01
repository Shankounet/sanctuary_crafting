--[[
    tree/craft_tree.lua — arbre de craft (dépendances ingrédients → recettes)
]]

CraftTree = CraftTree or {}

--- Build dependency tree for a recipe (what recipes produce its ingredients)
function CraftTree.ForRecipe(recipeId, depth)
    depth = depth or 3
    local recipe = Config.RecipeById[recipeId]
    if not recipe then return nil end

    local function nodeFor(rid, d)
        local r = Config.RecipeById[rid]
        if not r then return nil end
        local children = {}
        if d > 0 then
            for i = 1, #r.ingredients do
                local item = r.ingredients[i].item
                -- find a recipe that produces this item
                local producer
                for id, rr in pairs(Config.RecipeById) do
                    if rr.result and rr.result.item == item then
                        producer = id
                        break
                    end
                end
                if producer then
                    children[#children + 1] = nodeFor(producer, d - 1)
                else
                    children[#children + 1] = {
                        type = 'raw', item = item, count = r.ingredients[i].count,
                    }
                end
            end
        end
        return {
            type = 'recipe', id = r.id, label = r.label,
            result = r.result, ingredients = r.ingredients, children = children,
        }
    end

    return nodeFor(recipeId, depth)
end

lib.callback.register('sanctuary_crafting:craftTree', function(src, recipeId, depth)
    local tree = CraftTree.ForRecipe(recipeId, depth or 3)
    if not tree then return { ok = false, reason = 'craft_invalid' } end
    return { ok = true, tree = tree }
end)
