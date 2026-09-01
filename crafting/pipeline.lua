--[[
    crafting/pipeline.lua — craftId UUID, anti-dupe, inventaire sécurisé
    Flow: start → (remove ingredients) → craftId → complete(craftId) one-shot | cancel refund
]]

CraftingPipeline = CraftingPipeline or {}

--- active[craftId] = { src, recipeId, benchKey, startedAt, duration, ingredients, batch, completed, craftUID }
local activeById = {}
local activeBySrc = {} -- [src] = { [craftId]=true }

local function snapshotIngredients(ingredients, batch)
    batch = batch or 1
    local snap = {}
    for i = 1, #ingredients do
        local ing = ingredients[i]
        snap[i] = { item = ing.item, count = (ing.count or 1) * batch, original = ing }
    end
    return snap
end

local function scaleIngredients(ingredients, batch)
    local list = {}
    for i = 1, #ingredients do
        list[i] = { item = ingredients[i].item, count = (ingredients[i].count or 1) * batch }
    end
    return list
end

function CraftingPipeline.HasActive(src)
    local set = activeBySrc[src]
    if not set then return false end
    for _ in pairs(set) do return true end
    return false
end

function CraftingPipeline.Get(craftId)
    return activeById[craftId]
end

local function registerActive(src, craft)
    activeById[craft.craftId] = craft
    activeBySrc[src] = activeBySrc[src] or {}
    activeBySrc[src][craft.craftId] = true
    Validation.IncCraftCount(src)
end

local function clearActive(craftId, refund)
    local craft = activeById[craftId]
    if not craft then return end
    activeById[craftId] = nil
    if activeBySrc[craft.src] then
        activeBySrc[craft.src][craftId] = nil
    end
    Validation.DecCraftCount(craft.src)
    if refund and craft.removed and craft.ingredients then
        for i = 1, #craft.ingredients do
            local ing = craft.ingredients[i]
            exports.ox_inventory:AddItem(craft.src, ing.item, ing.count)
        end
        -- restore tool durability if consumed
        if craft.toolRestore then
            -- best-effort; tools module may re-add
        end
    end
    return craft
end

function CraftingPipeline.Cancel(src, craftId, reason)
    local craft = activeById[craftId]
    if not craft or craft.src ~= src then return false, 'craft_invalid' end
    local doRefund = Config.Crafting and Config.Crafting.RefundOnCancel
    if doRefund and craft.removed and Config.Crafting.PartialRefund then
        local elapsed = GetGameTimer() - (craft.startedAt or 0)
        local prog = (craft.duration or 1) > 0 and (elapsed / craft.duration) or 0
        local threshold = Config.Crafting.PartialRefundAfter or 0.5
        if prog >= threshold then
            -- rembourse ~50% des stacks
            for i = 1, #(craft.ingredients or {}) do
                local ing = craft.ingredients[i]
                local give = math.max(0, math.floor((ing.count or 1) * 0.5))
                if give > 0 then exports.ox_inventory:AddItem(src, ing.item, give) end
            end
            craft.removed = false -- clearActive must not double-refund
            doRefund = false
        end
    end
    clearActive(craftId, doRefund and craft.removed)
    CraftingCore.Emit('craftCancelled', src, craftId, reason)
    TriggerClientEvent('sanctuary_crafting:client:craftCancelled', src, craftId, reason)
    return true
end

function CraftingPipeline.CancelAll(src, refund)
    local set = activeBySrc[src]
    if not set then return end
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    for i = 1, #ids do
        clearActive(ids[i], refund)
    end
end

--- Resolve substitutions if Tags.Substitution enabled
local function resolveIngredients(src, recipe, batch)
    local ingredients = scaleIngredients(recipe.ingredients, batch)
    if not Config.Tags or not Config.Tags.Enabled or not Config.Tags.Substitution then
        return ingredients, true
    end
    -- substitution: ingredient.substitutes = { 'alt_item', ... }
    local resolved = {}
    for i = 1, #recipe.ingredients do
        local ing = recipe.ingredients[i]
        local need = (ing.count or 1) * batch
        local have = exports.ox_inventory:GetItemCount(src, ing.item) or 0
        if have >= need then
            resolved[#resolved + 1] = { item = ing.item, count = need }
        else
            local filled = false
            for _, alt in ipairs(ing.substitutes or {}) do
                local ah = exports.ox_inventory:GetItemCount(src, alt) or 0
                if ah >= need then
                    resolved[#resolved + 1] = { item = alt, count = need }
                    filled = true
                    break
                end
            end
            if not filled then return nil, false end
        end
    end
    return resolved, true
end

local function rollQuality(src, recipe)
    if not Config.Quality or not Config.Quality.Enabled or not recipe.quality then
        return nil
    end
    local tiers = Config.Quality.Tiers or { 'poor', 'normal', 'good', 'excellent', 'masterwork' }
    local idx = 2 -- normal
    if Config.Quality.SkillInfluence then
        local bonus = CraftingSkills.GetCategoryBonus(Config.Skills.craftingCategory or 'crafting', src)
        idx = math.min(#tiers, math.max(1, idx + math.floor((bonus or 0) / 25)))
    end
    -- mastery nudge
    if Config.Mastery and Config.Mastery.Enabled and Mastery then
        local m = Mastery.Get(src, recipe.id)
        if m >= 50 then idx = math.min(#tiers, idx + 1) end
        if m >= 90 then idx = math.min(#tiers, idx + 1) end
    end
    return tiers[idx] or Config.Quality.DefaultTier or 'normal'
end

local function applyToolCost(src, recipe)
    if not Config.Tools or not Config.Tools.Enabled or not recipe.requireTool then
        return true
    end
    return Tools.Consume(src, recipe.requireTool)
end

local function giveByproducts(src, recipe)
    if not Config.Byproducts or not Config.Byproducts.Enabled then return end
    for _, bp in ipairs(recipe.byproducts or {}) do
        local chance = bp.chance or 1.0
        if math.random() <= chance then
            if Validation.CanCarry(src, bp.item, bp.count or 1) then
                exports.ox_inventory:AddItem(src, bp.item, bp.count or 1)
            end
        end
    end
end

local function emitNoise(src, recipe, bench)
    if not Config.Noise or not Config.Noise.Enabled then return end
    local level = recipe.noiseLevel or 0
    if level <= 0 then return end
    local coords = bench and bench.coords
    TriggerEvent(Config.Noise.ExportEvent or 'sanctuary_crafting:noise', src, level, coords, recipe.id)
    TriggerClientEvent('sanctuary_crafting:client:noise', -1, level, coords)
end

local function validateStart(src, recipeId, benchKey, batch)
    batch = math.floor(tonumber(batch) or 1)
    if batch < 1 then batch = 1 end
    if Config.Batch and Config.Batch.Enabled then
        local maxB = Config.Batch.MaxBatch or 10
        local recipe = Config.RecipeById[recipeId]
        if recipe and recipe.batchMax then maxB = math.min(maxB, recipe.batchMax) end
        if batch > maxB then return nil, 'craft_batch_max' end
    else
        batch = 1
    end

    if type(recipeId) ~= 'string' or type(benchKey) ~= 'string' then
        return nil, 'craft_invalid'
    end
    if not Validation.CanStartAnotherCraft(src) then
        return nil, 'craft_busy'
    end
    local okRate, rateReason = Validation.CheckRateLimit(src)
    if not okRate then return nil, rateReason end

    local recipe = Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end

    if recipe.dismantle and (not Config.Dismantling or not Config.Dismantling.Enabled) then
        return nil, 'dismantle_disabled'
    end

    local bench = Benches.Resolve(benchKey)
    if not bench then return nil, 'craft_invalid' end
    if recipe.category ~= bench.category then return nil, 'craft_wrong_bench' end
    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return nil, 'craft_too_far'
    end

    local okPerm, permReason = CraftingPermissions.CanUseStation(src, bench)
    if not okPerm then return nil, permReason or 'craft_denied' end

    if not CraftingPower.CanRunRecipe(bench, recipe) then return nil, 'craft_no_power' end
    if not Benches.MeetsStationLevel(bench, recipe) then return nil, 'craft_station_level' end

    local okSkill, skillReason, skillArgs = CraftingSkills.CheckRecipeGates(src, recipe)
    if not okSkill then return nil, skillReason, skillArgs end

    if recipe.requireBlueprint or recipe.blueprintId then
        local bpId = recipe.requireBlueprint or recipe.blueprintId
        if Config.Blueprints and Config.Blueprints.Enabled then
            if not Blueprints.Has(src, bpId) then
                return nil, 'craft_blueprint_required', { bpId }
            end
        end
    end

    local ingredients, okIng = resolveIngredients(src, recipe, batch)
    if not okIng or not ingredients then return nil, 'craft_no_ingredients' end
    if not Validation.HasIngredients(src, ingredients) then return nil, 'craft_no_ingredients' end

    local resultCount = (recipe.result.count or 1) * batch
    if not Validation.CanCarry(src, recipe.result.item, resultCount) then
        return nil, 'craft_inventory_full'
    end

    if not applyToolCost(src, recipe) then return nil, 'craft_tool_required' end

    return {
        recipe = recipe, bench = bench, batch = batch,
        ingredients = ingredients,
    }
end

lib.callback.register('sanctuary_crafting:startCraft', function(src, recipeId, benchKey, batch)
    local ctx, reason, args = validateStart(src, recipeId, benchKey, batch)
    if not ctx then return { ok = false, reason = reason, args = args } end

    local recipe, bench = ctx.recipe, ctx.bench
    local removed = false
    if Config.Crafting and Config.Crafting.RemoveIngredientsOnStart ~= false then
        for i = 1, #ctx.ingredients do
            local ing = ctx.ingredients[i]
            if not exports.ox_inventory:RemoveItem(src, ing.item, ing.count) then
                -- refund partial
                for j = 1, i - 1 do
                    local p = ctx.ingredients[j]
                    exports.ox_inventory:AddItem(src, p.item, p.count)
                end
                return { ok = false, reason = 'craft_no_ingredients' }
            end
        end
        removed = true
    end

    local duration = CraftingSkills.ApplyCraftTimeBonus(recipe.duration or 5000, src)
    if ctx.batch > 1 then
        duration = math.floor(duration * ctx.batch * 0.85) -- slight batch efficiency
    end

    local craftId = GenerateCraftId()
    local craftUID = ('%s:%s:%d'):format(recipe.id, craftId:sub(1, 8), os.time())
    local craft = {
        craftId = craftId, craftUID = craftUID, src = src,
        recipeId = recipe.id, benchKey = bench.key,
        startedAt = GetGameTimer(), startedUnix = os.time(),
        duration = duration, batch = ctx.batch,
        ingredients = ctx.ingredients, removed = removed,
        completed = false,
    }
    registerActive(src, craft)
    emitNoise(src, recipe, bench)
    CraftingCore.Emit('craftStarted', src, craft)

    DebugPrint('startCraft', src, craftId, recipe.id, duration)
    return {
        ok = true, craftId = craftId, craftUID = craftUID,
        duration = duration, label = recipe.label, batch = ctx.batch,
        cancelDistance = Config.CraftCancelDistance,
        benchCoords = { x = bench.coords.x, y = bench.coords.y, z = bench.coords.z },
        anim = (Config.Animations and Config.Animations.Default) or nil,
    }
end)

lib.callback.register('sanctuary_crafting:completeCraft', function(src, craftId)
    if type(craftId) ~= 'string' then return { ok = false, reason = 'craft_invalid' } end
    local craft = activeById[craftId]
    if not craft or craft.src ~= src or craft.completed then
        return { ok = false, reason = 'craft_invalid' }
    end

    -- one-shot lock
    craft.completed = true

    local elapsed = GetGameTimer() - (craft.startedAt or 0)
    local factor = (Config.Crafting and Config.Crafting.MinDurationFactor) or 0.85
    local minTime = math.floor((craft.duration or 0) * factor)
    if elapsed < minTime then
        clearActive(craftId, craft.removed and Config.Crafting.RefundOnCancel)
        return { ok = false, reason = 'craft_failed' }
    end

    local recipe = Config.RecipeById[craft.recipeId]
    local bench = Benches.Resolve(craft.benchKey)
    if not recipe or not bench then
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_invalid' }
    end

    if not Validation.IsNearBench(src, bench.coords, Config.CraftCancelDistance or 3.0) then
        clearActive(craftId, craft.removed and Config.Crafting.RefundOnCancel)
        return { ok = false, reason = 'craft_too_far' }
    end

    local okSkill = CraftingSkills.CheckRecipeGates(src, recipe)
    if not okSkill then
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_failed' }
    end

    -- Remove on complete if not removed at start
    if not craft.removed then
        if not Validation.HasIngredients(src, craft.ingredients) then
            clearActive(craftId, false)
            return { ok = false, reason = 'craft_no_ingredients' }
        end
        for i = 1, #craft.ingredients do
            local ing = craft.ingredients[i]
            if not exports.ox_inventory:RemoveItem(src, ing.item, ing.count) then
                clearActive(craftId, false)
                return { ok = false, reason = 'craft_no_ingredients' }
            end
        end
        craft.removed = true
    end

    local batch = craft.batch or 1
    local resultItem = recipe.result.item
    local resultCount = (recipe.result.count or 1) * batch

    -- Dismantle yields
    local given = {}
    if recipe.dismantle and Config.Dismantling and Config.Dismantling.Enabled and recipe.dismantleYields then
        local bonus = 0
        if Config.Dismantling.SkillYieldBonus then
            bonus = (CraftingSkills.GetCategoryBonus(Config.Skills.craftingCategory or 'crafting', src) or 0) / 100
        end
        for _, y in ipairs(recipe.dismantleYields) do
            local chance = math.min(1.0, (y.chance or 1.0) + bonus * 0.2)
            if math.random() <= chance then
                local c = y.count or 1
                if Validation.CanCarry(src, y.item, c) then
                    exports.ox_inventory:AddItem(src, y.item, c)
                    given[#given + 1] = { item = y.item, count = c }
                end
            end
        end
    else
        local meta = { craftUID = craft.craftUID, craftedBy = GetPlayerIdentifierSafe(src) }
        local quality = rollQuality(src, recipe)
        if quality then meta.quality = quality end

        if not Validation.CanCarry(src, resultItem, resultCount) then
            -- refund
            for i = 1, #craft.ingredients do
                local ing = craft.ingredients[i]
                exports.ox_inventory:AddItem(src, ing.item, ing.count)
            end
            clearActive(craftId, false)
            return { ok = false, reason = 'craft_inventory_full' }
        end

        local added = exports.ox_inventory:AddItem(src, resultItem, resultCount, meta)
        if not added then
            for i = 1, #craft.ingredients do
                local ing = craft.ingredients[i]
                exports.ox_inventory:AddItem(src, ing.item, ing.count)
            end
            clearActive(craftId, false)
            return { ok = false, reason = 'craft_inventory_full' }
        end
        given[#given + 1] = { item = resultItem, count = resultCount, quality = quality }
        giveByproducts(src, recipe)
    end

    -- XP ml_skills only
    if recipe.xp and recipe.xp.category and recipe.xp.amount then
        CraftingSkills.AddXP(recipe.xp.category, recipe.xp.amount * batch, src)
    end

    if Config.Mastery and Config.Mastery.Enabled and Mastery then
        Mastery.Add(src, recipe.id, (Config.Mastery.XpPerCraft or 1) * batch)
    end

    clearActive(craftId, false)
    CraftingCore.Emit('craftCompleted', src, craft, given)
    DebugPrint('completeCraft ok', src, craftId)

    return {
        ok = true, craftId = craftId, craftUID = craft.craftUID,
        result = given[1] or recipe.result, results = given,
        label = recipe.label, quality = given[1] and given[1].quality,
    }
end)

RegisterNetEvent('sanctuary_crafting:server:cancelCraft', function(craftId)
    local src = source
    if type(craftId) == 'string' then
        CraftingPipeline.Cancel(src, craftId, 'cancel')
    else
        -- legacy: cancel all
        local refund = Config.Crafting and Config.Crafting.RefundOnCancel
        CraftingPipeline.CancelAll(src, refund)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local refund = Config.Crafting and Config.Crafting.RefundOnDisconnect
    CraftingPipeline.CancelAll(src, refund)
    Validation.ClearPlayer(src)
end)

-- Menu / NUI data
local function buildRecipeEntry(src, r)
    local canCraft, lockReason, lockArgs = true, nil, nil
    local okSkill, skillReason, skillArgs = CraftingSkills.CheckRecipeGates(src, r)
    if not okSkill then
        canCraft, lockReason, lockArgs = false, skillReason, skillArgs
    end
    if r.requireBlueprint or r.blueprintId then
        local bpId = r.requireBlueprint or r.blueprintId
        if Config.Blueprints and Config.Blueprints.Enabled and Blueprints and not Blueprints.Has(src, bpId) then
            canCraft, lockReason, lockArgs = false, 'craft_blueprint_required', { bpId }
        end
    end
    local hasItems = Validation.HasIngredients(src, scaleIngredients(r.ingredients, 1))
    local mastery = (Config.Mastery and Config.Mastery.Enabled and Mastery) and Mastery.Get(src, r.id) or 0
    return {
        id = r.id, label = r.label, category = r.category, tags = r.tags or {},
        ingredients = r.ingredients, result = r.result, duration = r.duration,
        xp = r.xp, requireLevel = r.requireLevel, requireSkill = r.requireSkill,
        requireBlueprint = r.requireBlueprint or r.blueprintId,
        requireTool = r.requireTool, quality = r.quality, byproducts = r.byproducts,
        queueable = r.queueable, batchMax = r.batchMax, dismantle = r.dismantle,
        stationLevel = r.stationLevel, powerCost = r.powerCost, noiseLevel = r.noiseLevel,
        canCraft = canCraft and hasItems, locked = not canCraft,
        missingItems = not hasItems, lockReason = lockReason, lockArgs = lockArgs,
        mastery = mastery,
    }
end

lib.callback.register('sanctuary_crafting:getMenu', function(src, benchKey)
    local bench = Benches.Resolve(benchKey)
    if not bench then return { ok = false } end
    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return { ok = false, reason = 'craft_too_far' }
    end
    local okPerm = CraftingPermissions.CanUseStation(src, bench)
    if not okPerm then return { ok = false, reason = 'craft_denied' } end

    local recipes = GetRecipesForCategory(bench.category)
    local out = {}
    for i = 1, #recipes do
        out[#out + 1] = buildRecipeEntry(src, recipes[i])
    end

    local favorites = {}
    if Favorites then favorites = Favorites.Get(src) end

    return {
        ok = true, benchKey = benchKey, category = bench.category,
        label = _(Config.BenchLabels[bench.category] or 'bench_scrap'),
        stationLevel = bench.stationLevel or 1, modules = bench.modules or {},
        powered = CraftingPower.HasPower(bench),
        recipes = out, favorites = favorites,
        ui = Config.UI, flags = {
            quality = Config.Quality and Config.Quality.Enabled,
            blueprints = Config.Blueprints and Config.Blueprints.Enabled,
            queue = Config.Queue and Config.Queue.Enabled,
            batch = Config.Batch and Config.Batch.Enabled,
            mastery = Config.Mastery and Config.Mastery.Enabled,
            shopping = Config.ShoppingList and Config.ShoppingList.Enabled,
        },
    }
end)
