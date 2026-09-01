--[[
    Craft serveur-autoritaire
    1) client requestCraft → validate, set active, return duration
    2) client progress (ox_lib)
    3) client completeCraft / cancelCraft → re-validate, RemoveItem, AddItem, AddXp
]]

local function notify(src, ntype, key, fmtArgs)
    local desc = key
    if type(key) == 'string' and Locales then
        if fmtArgs then
            desc = _(key, table.unpack(fmtArgs))
        else
            desc = _(key)
        end
    end
    TriggerClientEvent('ox_lib:notify', src, { type = ntype or 'inform', description = desc })
end

---@param src number
---@param recipeId string
---@param benchKey string
lib.callback.register('sanctuary_crafting:startCraft', function(src, recipeId, benchKey)
    if type(recipeId) ~= 'string' or type(benchKey) ~= 'string' then
        return { ok = false, reason = 'craft_invalid' }
    end

    if Validation.IsCrafting(src) then
        return { ok = false, reason = 'craft_busy' }
    end

    local okRate, rateReason = Validation.CheckRateLimit(src)
    if not okRate then
        return { ok = false, reason = rateReason }
    end

    local recipe = Config.RecipeById[recipeId]
    if not recipe then
        return { ok = false, reason = 'craft_invalid' }
    end

    local bench = Benches.Resolve(benchKey)
    if not bench then
        return { ok = false, reason = 'craft_invalid' }
    end

    if recipe.category ~= bench.category then
        return { ok = false, reason = 'craft_wrong_bench' }
    end

    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return { ok = false, reason = 'craft_too_far' }
    end

    local okSkill, skillReason, skillArgs = Validation.CheckSkillGates(src, recipe)
    if not okSkill then
        return { ok = false, reason = skillReason, args = skillArgs }
    end

    if not Validation.HasIngredients(src, recipe.ingredients) then
        return { ok = false, reason = 'craft_no_ingredients' }
    end

    local duration = Skills.ApplyCraftTimeBonus(recipe.duration or 5000, src)

    Validation.SetActive(src, {
        recipeId = recipeId,
        benchKey = benchKey,
        startedAt = GetGameTimer(),
        duration = duration,
    })

    DebugPrint('startCraft', src, recipeId, duration)
    return {
        ok = true,
        duration = duration,
        label = recipe.label,
        cancelDistance = Config.CraftCancelDistance,
        benchCoords = { x = bench.coords.x, y = bench.coords.y, z = bench.coords.z },
    }
end)

lib.callback.register('sanctuary_crafting:completeCraft', function(src, recipeId, benchKey)
    local active = Validation.GetActive(src)
    if not active or active.recipeId ~= recipeId or active.benchKey ~= benchKey then
        Validation.ClearActive(src)
        return { ok = false, reason = 'craft_invalid' }
    end

    -- Timing floor (anti speedhack) — allow 10% early for latency
    local elapsed = GetGameTimer() - (active.startedAt or 0)
    local minTime = math.floor((active.duration or 0) * 0.85)
    if elapsed < minTime then
        Validation.ClearActive(src)
        DebugPrint('completeCraft too early', src, elapsed, minTime)
        return { ok = false, reason = 'craft_failed' }
    end

    local recipe = Config.RecipeById[recipeId]
    local bench = Benches.Resolve(benchKey)
    if not recipe or not bench then
        Validation.ClearActive(src)
        return { ok = false, reason = 'craft_invalid' }
    end

    if not Validation.IsNearBench(src, bench.coords, Config.CraftCancelDistance or 3.0) then
        Validation.ClearActive(src)
        return { ok = false, reason = 'craft_too_far' }
    end

    local okSkill = Validation.CheckSkillGates(src, recipe)
    if not okSkill then
        Validation.ClearActive(src)
        return { ok = false, reason = 'craft_failed' }
    end

    if not Validation.HasIngredients(src, recipe.ingredients) then
        Validation.ClearActive(src)
        return { ok = false, reason = 'craft_no_ingredients' }
    end

    -- Remove ingredients
    for i = 1, #recipe.ingredients do
        local ing = recipe.ingredients[i]
        local removed = exports.ox_inventory:RemoveItem(src, ing.item, ing.count)
        if not removed then
            -- rollback previous removals is hard without transaction; stop and fail
            Validation.ClearActive(src)
            return { ok = false, reason = 'craft_no_ingredients' }
        end
    end

    local result = recipe.result
    local added = exports.ox_inventory:AddItem(src, result.item, result.count or 1)
    if not added then
        -- restore ingredients
        for i = 1, #recipe.ingredients do
            local ing = recipe.ingredients[i]
            exports.ox_inventory:AddItem(src, ing.item, ing.count)
        end
        Validation.ClearActive(src)
        return { ok = false, reason = 'craft_inventory_full' }
    end

    -- XP
    if recipe.xp and recipe.xp.category and recipe.xp.amount then
        Skills.AddXp(recipe.xp.category, recipe.xp.amount, src)
    end

    Validation.ClearActive(src)
    DebugPrint('completeCraft ok', src, recipeId)

    return {
        ok = true,
        result = result,
        label = recipe.label,
    }
end)

RegisterNetEvent('sanctuary_crafting:server:cancelCraft', function()
    local src = source
    Validation.ClearActive(src)
end)

-- Menu data helper (recipes filtered for bench + skill display)
lib.callback.register('sanctuary_crafting:getMenu', function(src, benchKey)
    local bench = Benches.Resolve(benchKey)
    if not bench then return { ok = false } end
    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return { ok = false, reason = 'craft_too_far' }
    end

    local recipes = GetRecipesForCategory(bench.category)
    local out = {}
    for i = 1, #recipes do
        local r = recipes[i]
        local canCraft = true
        local lockReason = nil
        local okSkill, skillReason, skillArgs = Validation.CheckSkillGates(src, r)
        if not okSkill then
            canCraft = false
            lockReason = skillReason
        end
        local hasItems = Validation.HasIngredients(src, r.ingredients)

        out[#out + 1] = {
            id = r.id,
            label = r.label,
            category = r.category,
            ingredients = r.ingredients,
            result = r.result,
            duration = r.duration,
            xp = r.xp,
            requireLevel = r.requireLevel,
            requireSkill = r.requireSkill,
            canCraft = canCraft and hasItems,
            locked = not canCraft,
            missingItems = not hasItems,
            lockReason = lockReason,
            lockArgs = skillArgs,
        }
    end

    return {
        ok = true,
        benchKey = benchKey,
        category = bench.category,
        label = _(Config.BenchLabels[bench.category] or 'bench_scrap'),
        recipes = out,
    }
end)
