--[[
    hooks/exports.lua — public façade
    KEEP old names. Add v2.16.0 architecture exports (see docs/EXPORTS.md).
    LearnRecipe is SERVER only — never a client bypass of learnBlueprint.
]]

-- ── old names (kept) ────────────────────────────────────────────────────────

exports('AddCraftingHook', function(name, fn)
    CraftingCore.On(name, fn)
end)

exports('HasBlueprint', function(src, bpId)
    return Blueprints and Blueprints.Has(src, bpId)
end)

exports('LearnBlueprint', function(src, bpId)
    return Blueprints and Blueprints.Learn(src, bpId)
end)

exports('GetMastery', function(src, recipeId)
    return Mastery and Mastery.Get(src, recipeId) or 0
end)

exports('GetStation', function(key)
    return Benches and Benches.Resolve(key)
end)

exports('OpenCraftingForPlayer', function(src, benchKey)
    TriggerClientEvent('sanctuary_crafting:client:openBench', src, benchKey)
end)

-- ── v2.16 façade (16 documented) ────────────────────────────────────────────

--- OpenStation(src, benchKey) → nil
exports('OpenStation', function(src, benchKey)
    TriggerClientEvent('sanctuary_crafting:client:openBench', src, benchKey)
end)

--- OpenRecipe(src, recipeId) → boolean
exports('OpenRecipe', function(src, recipeId)
    local recipe = RecipeRegistry and RecipeRegistry.Get(recipeId)
    if not recipe then return false, 'craft_invalid' end
    local want = recipe.station or recipe.category
    local best, bestDist
    if Benches and Benches.ForEach then
        local ped = GetPlayerPed(src)
        local pcoords = ped and ped ~= 0 and GetEntityCoords(ped) or nil
        Benches.ForEach(function(b)
            local cat = b.category or b.station
            if cat == want or b.station == want then
                local d = (pcoords and b.coords) and Dist3(pcoords, b.coords) or 99999
                if not bestDist or d < bestDist then
                    best, bestDist = b, d
                end
            end
        end)
    end
    if not best then return false, 'craft_invalid' end
    TriggerClientEvent('sanctuary_crafting:client:openBench', src, best.key, recipeId)
    return true
end)

--- AddRecipe(recipe, src?) → ok, version
exports('AddRecipe', function(recipe, src)
    if not RecipeOverlay or not RecipeOverlay.Save then return false, 'craft_invalid' end
    return RecipeOverlay.Save(recipe, src)
end)

--- RemoveRecipe(recipeId, src?) — soft-disable
exports('RemoveRecipe', function(recipeId, src)
    if not RecipeOverlay or not RecipeOverlay.SetDisabled then return false, 'craft_invalid' end
    return RecipeOverlay.SetDisabled(recipeId, true, src)
end)

--- GetRecipe(id) → table|nil  (also registered in boot.lua)
exports('GetRecipe', function(id)
    return RecipeRegistry and RecipeRegistry.Get(id)
end)

--- GetRecipes(filter?) → table[]
exports('GetRecipes', function(filter)
    local list = RecipeRegistry and RecipeRegistry.GetAll and RecipeRegistry.GetAll() or {}
    if type(filter) ~= 'table' then return list end
    local out = {}
    for i = 1, #list do
        local r = list[i]
        local ok = true
        if filter.station and (r.station or r.category) ~= filter.station then ok = false end
        if filter.category and r.category ~= filter.category then ok = false end
        if ok then out[#out + 1] = r end
    end
    return out
end)

--- CanCraft(src, recipeId, benchKey, batch?) → boolean, reason, args
exports('CanCraft', function(src, recipeId, benchKey, batch)
    if not CraftingPipeline or not CraftingPipeline.ValidateStart then
        return false, 'craft_invalid'
    end
    local ctx, reason, args = CraftingPipeline.ValidateStart(src, recipeId, benchKey, batch or 1)
    return ctx ~= nil, reason, args
end)

--- StartCraft(src, recipeId, benchKey, batch?) → result table
exports('StartCraft', function(src, recipeId, benchKey, batch)
    if not CraftingPipeline or not CraftingPipeline.Start then
        return { ok = false, reason = 'craft_invalid' }
    end
    return CraftingPipeline.Start(src, recipeId, benchKey, batch or 1)
end)

--- CancelCraft(src, craftId, reason?) → boolean, reason
exports('CancelCraft', function(src, craftId, reason)
    if not CraftingPipeline or not CraftingPipeline.Cancel then return false, 'craft_invalid' end
    return CraftingPipeline.Cancel(src, craftId, reason or 'export')
end)

--- GetQueue(src) → entries[]
exports('GetQueue', function(src)
    if not CraftQueue or not CraftQueue.List then return {} end
    return CraftQueue.List(src)
end)

--- FollowRecipe(src, recipeId) → boolean
exports('FollowRecipe', function(src, recipeId)
    if SurvivalBook and SurvivalBook.PinRecipe then
        local ok, err = SurvivalBook.PinRecipe(src, recipeId)
        return ok and true or false, err
    end
    return false, 'book_disabled'
end)

--- UnfollowRecipe(src, recipeId) → boolean
exports('UnfollowRecipe', function(src, recipeId)
    if SurvivalBook and SurvivalBook.UnpinRecipe then
        SurvivalBook.UnpinRecipe(src, recipeId)
        return true
    end
    return false, 'book_disabled'
end)

--- IsRecipeKnown(src, recipeId) → boolean
exports('IsRecipeKnown', function(src, recipeId)
    local recipe = RecipeRegistry and RecipeRegistry.Get(recipeId)
    if not recipe then return false end
    if Blueprints and Blueprints.KnowsRecipe then
        return Blueprints.KnowsRecipe(src, recipe) == true
    end
    return true
end)

--- LearnRecipe(src, recipeId) SERVER only — not a client bypass of learnBlueprint
exports('LearnRecipe', function(src, recipeId)
    local recipe = RecipeRegistry and RecipeRegistry.Get(recipeId)
    if not recipe then return false, 'craft_invalid' end
    if Blueprints and Blueprints.GrantKnowledge then
        return Blueprints.GrantKnowledge(src, recipe, 'export')
    end
    if Blueprints and Blueprints.Learn then
        local bpId = recipe.requireBlueprint or recipe.blueprintId or recipe.id
        return Blueprints.Learn(src, bpId)
    end
    return false, 'blueprints_disabled'
end)

--- GetRecipeMastery(src, recipeId) → number
exports('GetRecipeMastery', function(src, recipeId)
    return Mastery and Mastery.Get(src, recipeId) or 0
end)

--- GetStationState(benchKey, src?) → snapshot
exports('GetStationState', function(key, src)
    local bench = Benches and Benches.Resolve and Benches.Resolve(key)
    if not bench then return nil end
    if StationRuntime and StationRuntime.Snapshot then
        return StationRuntime.Snapshot(bench, src)
    end
    return {
        key = bench.key, category = bench.category, level = bench.stationLevel or 1,
        kind = bench.kind, modules = bench.modules or {},
    }
end)

-- Noise re-export
AddEventHandler('sanctuary_crafting:noise', function(src, level, coords, recipeId)
    DebugPrint('noise', src, level, recipeId)
end)
