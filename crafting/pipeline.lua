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


local function recipeHasSteps(recipe)
    return recipe and type(recipe.steps) == 'table' and #recipe.steps > 0
end

---@return table|nil step, number index, number total
local function currentStepInfo(recipe, stepIndex)
    if not recipeHasSteps(recipe) then return nil, 1, 1 end
    local idx = stepIndex or 1
    return recipe.steps[idx], idx, #recipe.steps
end

local function stepIngredients(recipe, stepIndex, batch)
    batch = batch or 1
    local step = recipeHasSteps(recipe) and recipe.steps[stepIndex or 1] or nil
    local src = (step and step.ingredients) or recipe.ingredients or {}
    return scaleIngredients(src, batch)
end

local function stepDuration(recipe, stepIndex)
    local step = recipeHasSteps(recipe) and recipe.steps[stepIndex or 1] or nil
    if step and type(step.duration) == 'number' then return step.duration end
    if recipeHasSteps(recipe) then
        -- split total duration across steps if step has no own duration
        local n = #recipe.steps
        return math.max(500, math.floor((recipe.duration or 5000) / n))
    end
    return recipe.duration or 5000
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
    if Validation and Validation.DecCraftCount then Validation.DecCraftCount(craft.src) end
    if refund and craft.removed then
        -- multi-step: rembourser tout l'historique d'ingrédients retirés
        local hist = craft.removedHistory
        if type(hist) == 'table' and #hist > 0 then
            for _, list in ipairs(hist) do
                for i = 1, #list do
                    exports.ox_inventory:AddItem(craft.src, list[i].item, list[i].count)
                end
            end
        elseif craft.ingredients then
            for i = 1, #craft.ingredients do
                local ing = craft.ingredients[i]
                exports.ox_inventory:AddItem(craft.src, ing.item, ing.count)
            end
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
    -- Nouveau schéma tools[] (import) : consume=false → présence seule
    if recipe.tools and type(recipe.tools) == 'table' then
        for i = 1, #recipe.tools do
            local t = recipe.tools[i]
            if t and t.item then
                if not Tools or not Tools.Has or not Tools.Has(src, t.item) then
                    return false
                end
                if t.consume and Config.Tools and Config.Tools.Enabled and Tools.Consume then
                    if not Tools.Consume(src, { item = t.item, durabilityCost = t.durabilityCost or 1 }) then
                        return false
                    end
                end
            end
        end
        return true
    end
    if not Config.Tools or not Config.Tools.Enabled or not recipe.requireTool then
        return true
    end
    if not Tools or not Tools.Consume then return true end
    -- durabilityCost 0 → présence seule
    if (recipe.requireTool.durabilityCost or 0) <= 0 then
        return Tools.Has and Tools.Has(src, recipe.requireTool.item) or false
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
    local recipeStation = recipe.station or recipe.category
    if recipeStation ~= bench.category then return nil, 'craft_wrong_bench' end
    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return nil, 'craft_too_far'
    end

    local okPerm, permReason = true, nil
    if CraftingPermissions and CraftingPermissions.CanUseStation then
        okPerm, permReason = CraftingPermissions.CanUseStation(src, bench)
    end
    if not okPerm then return nil, permReason or 'craft_denied' end

    if CraftingPower and CraftingPower.CanRunRecipe and not CraftingPower.CanRunRecipe(bench, recipe) then return nil, 'craft_no_power' end
    if not Benches.MeetsStationLevel(bench, recipe) then return nil, 'craft_station_level' end

    local okSkill, skillReason, skillArgs = true, nil, nil
    if CraftingSkills and CraftingSkills.CheckRecipeGates then
        okSkill, skillReason, skillArgs = CraftingSkills.CheckRecipeGates(src, recipe)
    end
    if not okSkill then return nil, skillReason, skillArgs end

    if recipe.requireBlueprint or recipe.blueprintId then
        local bpId = recipe.requireBlueprint or recipe.blueprintId
        if Config.Blueprints and Config.Blueprints.Enabled then
            if not Blueprints.Has(src, bpId) then
                return nil, 'craft_blueprint_required', { bpId }
            end
        end
    end

    local ingredients, okIng
    if recipeHasSteps(recipe) then
        -- start: valider + consommer uniquement l'étape 1 ; étapes suivantes à l'avance
        ingredients = stepIngredients(recipe, 1, batch)
        okIng = Validation.HasIngredients(src, ingredients)
        if not okIng then return nil, 'craft_no_ingredients' end
    else
        ingredients, okIng = resolveIngredients(src, recipe, batch)
        if not okIng or not ingredients then return nil, 'craft_no_ingredients' end
        if not Validation.HasIngredients(src, ingredients) then return nil, 'craft_no_ingredients' end
    end

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

    if CraftingSkills and CraftingSkills.NotifyBypassIfNeeded then
        CraftingSkills.NotifyBypassIfNeeded(src)
    end

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

    local stepIndex = 1
    local totalSteps = recipeHasSteps(recipe) and #recipe.steps or 1
    local rawDur = stepDuration(recipe, stepIndex)
    local duration = CraftingSkills.ApplyCraftTimeBonus(rawDur, src)
    if ctx.batch > 1 then
        duration = math.floor(duration * ctx.batch * 0.85) -- slight batch efficiency
    end

    local step = select(1, currentStepInfo(recipe, stepIndex))
    local stepLabel = (step and step.label) or recipe.label

    local craftId = GenerateCraftId()
    local craftUID = ('%s:%s:%d'):format(recipe.id, craftId:sub(1, 8), os.time())
    local craft = {
        craftId = craftId, craftUID = craftUID, src = src,
        recipeId = recipe.id, benchKey = bench.key,
        startedAt = GetGameTimer(), startedUnix = os.time(),
        duration = duration, batch = ctx.batch,
        ingredients = ctx.ingredients, removed = removed,
        completed = false,
        stepIndex = stepIndex, totalSteps = totalSteps,
        removedHistory = removed and { ctx.ingredients } or {},
    }
    registerActive(src, craft)
    emitNoise(src, recipe, bench)
    CraftingCore.Emit('craftStarted', src, craft)

    DebugPrint('startCraft', src, craftId, recipe.id, duration, 'step', stepIndex, '/', totalSteps)
    return {
        ok = true, craftId = craftId, craftUID = craftUID,
        duration = duration, label = stepLabel, batch = ctx.batch,
        stepIndex = stepIndex, totalSteps = totalSteps,
        stepLabel = stepLabel,
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
    local bench = Benches and Benches.Resolve and Benches.Resolve(craft.benchKey)
    if not recipe or not bench then
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_invalid' }
    end

    if not Validation.IsNearBench(src, bench.coords, Config.CraftCancelDistance or 3.0) then
        clearActive(craftId, craft.removed and Config.Crafting.RefundOnCancel)
        return { ok = false, reason = 'craft_too_far' }
    end

    local okSkill = CraftingSkills and CraftingSkills.CheckRecipeGates and CraftingSkills.CheckRecipeGates(src, recipe)
    if not okSkill then
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_failed' }
    end

    -- Remove on complete if not removed at start (single-step or current step)
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
        craft.removedHistory = craft.removedHistory or {}
        craft.removedHistory[#craft.removedHistory + 1] = craft.ingredients
    end

    -- Multi-step: advance under SAME craftId (pas de nouveau UUID)
    local stepIndex = craft.stepIndex or 1
    local totalSteps = craft.totalSteps or (recipeHasSteps(recipe) and #recipe.steps or 1)
    if recipeHasSteps(recipe) and stepIndex < totalSteps then
        local nextIndex = stepIndex + 1
        local nextIngs = stepIngredients(recipe, nextIndex, craft.batch or 1)
        if not Validation.HasIngredients(src, nextIngs) then
            -- ne consomme pas ; reste sur l'étape courante terminée → annule avec refund historique
            clearActive(craftId, false)
            -- refund all previously removed step ingredients
            for _, hist in ipairs(craft.removedHistory or {}) do
                for i = 1, #hist do
                    exports.ox_inventory:AddItem(src, hist[i].item, hist[i].count)
                end
            end
            return { ok = false, reason = 'craft_no_ingredients' }
        end
        for i = 1, #nextIngs do
            local ing = nextIngs[i]
            if not exports.ox_inventory:RemoveItem(src, ing.item, ing.count) then
                for j = 1, i - 1 do
                    exports.ox_inventory:AddItem(src, nextIngs[j].item, nextIngs[j].count)
                end
                clearActive(craftId, false)
                for _, hist in ipairs(craft.removedHistory or {}) do
                    for hi = 1, #hist do
                        exports.ox_inventory:AddItem(src, hist[hi].item, hist[hi].count)
                    end
                end
                return { ok = false, reason = 'craft_no_ingredients' }
            end
        end
        craft.removedHistory = craft.removedHistory or {}
        craft.removedHistory[#craft.removedHistory + 1] = nextIngs
        craft.ingredients = nextIngs
        craft.removed = true
        craft.stepIndex = nextIndex
        craft.completed = false -- réouvre one-shot pour l'étape suivante
        local nextStep = recipe.steps[nextIndex]
        local rawDur = stepDuration(recipe, nextIndex)
        local duration = CraftingSkills.ApplyCraftTimeBonus(rawDur, src)
        if (craft.batch or 1) > 1 then
            duration = math.floor(duration * craft.batch * 0.85)
        end
        craft.duration = duration
        craft.startedAt = GetGameTimer()
        craft.startedUnix = os.time()
        local stepLabel = (nextStep and nextStep.label) or recipe.label
        CraftingCore.Emit('craftStepAdvanced', src, craft, nextIndex, totalSteps)
        DebugPrint('advanceStep', src, craftId, nextIndex, '/', totalSteps)
        return {
            ok = true, advanced = true, craftId = craftId, craftUID = craft.craftUID,
            stepIndex = nextIndex, totalSteps = totalSteps,
            duration = duration, label = stepLabel, stepLabel = stepLabel,
            batch = craft.batch,
        }
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

    -- chain: id(s) suivants sous même craftUID (client / project peut enchaîner)
    local chainNext = nil
    if type(recipe.chain) == 'table' and #recipe.chain > 0 then
        chainNext = recipe.chain[1]
    end

    return {
        ok = true, craftId = craftId, craftUID = craft.craftUID,
        result = given[1] or recipe.result, results = given,
        label = recipe.label, quality = given[1] and given[1].quality,
        stepIndex = craft.stepIndex or totalSteps, totalSteps = totalSteps,
        chainNext = chainNext, chain = recipe.chain,
        advanced = false,
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
    if CraftingSkills and CraftingSkills.CheckRecipeGates then
        local okSkill, skillReason, skillArgs = CraftingSkills.CheckRecipeGates(src, r)
        if not okSkill then
            canCraft, lockReason, lockArgs = false, skillReason, skillArgs
        end
    end
    if r.requireBlueprint or r.blueprintId then
        local bpId = r.requireBlueprint or r.blueprintId
        if Config.Blueprints and Config.Blueprints.Enabled and Blueprints and not Blueprints.Has(src, bpId) then
            canCraft, lockReason, lockArgs = false, 'craft_blueprint_required', { bpId }
        end
    end
    local checkIngs = recipeHasSteps(r) and stepIngredients(r, 1, 1) or scaleIngredients(r.ingredients or {}, 1)
    local hasItems = Validation and Validation.HasIngredients and Validation.HasIngredients(src, checkIngs) or false
    local mastery = (Config.Mastery and Config.Mastery.Enabled and Mastery and Mastery.Get) and Mastery.Get(src, r.id) or 0
    local stepsOut = nil
    if recipeHasSteps(r) then
        stepsOut = {}
        for i = 1, #r.steps do
            stepsOut[i] = {
                label = r.steps[i].label, ingredients = r.steps[i].ingredients,
                duration = r.steps[i].duration,
            }
        end
    end

    -- NUI display enrichment (additive; callbacks unchanged)
    local ingsSrc = (checkIngs and #checkIngs > 0)
        and (recipeHasSteps(r) and r.steps[1].ingredients or r.ingredients)
        or (r.ingredients or {})
    local ingsOut = {}
    for i = 1, #ingsSrc do
        local ing = ingsSrc[i]
        local owned = 0
        if GetResourceState('ox_inventory') == 'started' then
            owned = exports.ox_inventory:GetItemCount(src, ing.item) or 0
        end
        ingsOut[i] = { item = ing.item, count = ing.count or 1, owned = owned }
    end

    local skillCategory = nil
    local playerSkillLevel = nil
    local hasSpecialization = nil
    if CraftingSkills and CraftingSkills.LevelCategoryForRecipe then
        skillCategory = CraftingSkills.LevelCategoryForRecipe(r)
    elseif r.xp and r.xp.category then
        skillCategory = r.xp.category
    end
    if CraftingSkills and CraftingSkills.IsAvailable and CraftingSkills.IsAvailable() then
        if skillCategory and CraftingSkills.GetLevel then
            playerSkillLevel = CraftingSkills.GetLevel(skillCategory, src)
        end
        if r.requireSkill and CraftingSkills.HasSkill then
            hasSpecialization = CraftingSkills.HasSkill(skillCategory, r.requireSkill, src)
        end
    elseif lockReason == 'craft_level_required' and lockArgs and lockArgs[2] ~= nil then
        playerSkillLevel = lockArgs[2]
    end

    -- Missing / almost-craftable enrichment for NUI badges
    local missingCount = 0
    local primaryMissing = nil
    for i = 1, #ingsOut do
        local ing = ingsOut[i]
        local need = ing.count or 1
        local owned = ing.owned or 0
        if owned < need then
            missingCount = missingCount + 1
            if not primaryMissing then
                primaryMissing = { item = ing.item, owned = owned, count = need }
            end
        end
    end

    local toolDurability = nil
    if Config.Tools and Config.Tools.Enabled and r.requireTool then
        local toolItem = type(r.requireTool) == 'string' and r.requireTool or r.requireTool.item
        if toolItem and GetResourceState('ox_inventory') == 'started' then
            local slots = exports.ox_inventory:Search(src, 'slots', toolItem) or {}
            local key = (Config.Tools.DurabilityKey) or 'durability'
            for _, it in pairs(slots) do
                if it then
                    local meta = it.metadata or {}
                    toolDurability = meta[key]
                    if toolDurability == nil then
                        toolDurability = Config.Tools.DefaultDurability or 100
                    end
                    break
                end
            end
        end
    end

    local levelGap = nil
    if lockReason == 'craft_level_required' then
        local need = (lockArgs and lockArgs[1]) or r.requireLevel
        local cur = (lockArgs and lockArgs[2]) or playerSkillLevel
        if need ~= nil and cur ~= nil then
            levelGap = math.max(0, (tonumber(need) or 0) - (tonumber(cur) or 0))
        end
    elseif lockReason == 'craft_station_level' and r.stationLevel then
        -- bench level filled at menu level; gap computed client-side if needed
        levelGap = nil
    end

    local almostCraftable = false
    if not (canCraft and hasItems) then
        if canCraft and not hasItems and missingCount == 1 then
            almostCraftable = true
        elseif levelGap ~= nil and levelGap > 0 and levelGap <= 2 and hasItems then
            almostCraftable = true
        elseif toolDurability ~= nil and toolDurability > 0 and toolDurability <= 15 and hasItems and canCraft == false then
            -- tool nearly broken while other gates may vary — hint only when tools matter
            almostCraftable = true
        elseif not canCraft and hasItems and lockReason == 'craft_tool_required' and toolDurability ~= nil and toolDurability <= 15 then
            almostCraftable = true
        end
    end

    local tags = r.tags or {}
    local isNew = r.isNew == true
    local newlyUnlocked = r.newlyUnlocked == true
    if type(tags) == 'table' then
        for _, t in ipairs(tags) do
            local tl = type(t) == 'string' and string.lower(t) or ''
            if tl == 'new' or tl == 'nouveau' then isNew = true end
            if tl == 'newlyunlocked' or tl == 'newly_unlocked' then newlyUnlocked = true end
        end
    end

    return {
        id = r.id, label = r.label, category = r.category, tags = tags,
        description = r.description,
        ingredients = ingsOut,
        result = r.result, duration = r.duration,
        xp = r.xp, requireLevel = r.requireLevel, requireSkill = r.requireSkill,
        requireBlueprint = r.requireBlueprint or r.blueprintId,
        requireTool = r.requireTool, tools = r.tools, station = r.station, rarity = r.rarity,
        hideIfSkillLocked = r.hideIfSkillLocked, quality = r.quality, byproducts = r.byproducts,
        queueable = r.queueable, batchMax = r.batchMax, dismantle = r.dismantle,
        stationLevel = r.stationLevel, powerCost = r.powerCost, noiseLevel = r.noiseLevel,
        steps = stepsOut, chain = r.chain,
        canCraft = canCraft and hasItems, locked = not canCraft,
        missingItems = not hasItems, lockReason = lockReason, lockArgs = lockArgs,
        mastery = mastery,
        skillCategory = skillCategory,
        playerSkillLevel = playerSkillLevel,
        hasSpecialization = hasSpecialization,
        missingCount = missingCount,
        primaryMissing = primaryMissing,
        toolDurability = toolDurability,
        levelGap = levelGap,
        almostCraftable = almostCraftable,
        isNew = isNew,
        newlyUnlocked = newlyUnlocked,
        compareWith = r.compareWith,
        relatedRecipeId = r.relatedRecipeId,
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

    local pinned = {}
    if SurvivalBook and SurvivalBook.ListPins then
        local pins = SurvivalBook.ListPins(src) or {}
        for i = 1, #pins do
            local rid = pins[i].recipeId or pins[i]
            if type(rid) == 'string' then pinned[#pinned + 1] = rid end
        end
    end

    -- station-level almost gap fill for stationLevel locks
    local benchLevel = bench.stationLevel or 1
    for i = 1, #out do
        local e = out[i]
        if e.lockReason == 'craft_station_level' and e.stationLevel then
            local gap = math.max(0, (tonumber(e.stationLevel) or 0) - benchLevel)
            e.levelGap = gap
            if not e.canCraft and e.missingItems == false and gap > 0 and gap <= 2 then
                e.almostCraftable = true
            end
        end
    end

    local ux = (Config.UI and Config.UI.Ux) or {}
    local compareCfg = Config.Compare or {}

    return {
        ok = true, benchKey = benchKey, category = bench.category,
        label = bench.label or _(Config.BenchLabels[bench.category] or 'bench_scrap'),
        stationLevel = benchLevel, modules = bench.modules or {},
        powered = (CraftingPower and CraftingPower.HasPower and CraftingPower.HasPower(bench)) or false,
        recipes = out, favorites = favorites, pinned = pinned,
        ui = Config.UI, ux = ux,
        compare = {
            enabled = compareCfg.Enabled == true,
            map = compareCfg.Map or {},
        },
        queueMax = (Config.Queue and Config.Queue.MaxQueuePerPlayer) or 5,
        flags = {
            quality = Config.Quality and Config.Quality.Enabled,
            blueprints = Config.Blueprints and Config.Blueprints.Enabled,
            queue = Config.Queue and Config.Queue.Enabled,
            batch = Config.Batch and Config.Batch.Enabled,
            mastery = Config.Mastery and Config.Mastery.Enabled,
            shopping = Config.ShoppingList and Config.ShoppingList.Enabled,
            almostCraftable = ux.AlmostCraftable ~= false,
            badgeTooltips = ux.BadgeTooltips ~= false,
            nouveauIndicator = ux.NouveauIndicator ~= false,
            selectionTransition = ux.SelectionTransition ~= false,
            masteryDots = ux.MasteryDots ~= false,
            pinFollow = ux.PinFollow ~= false,
            fabReadyConsole = ux.FabReadyConsole ~= false,
            microToasts = ux.MicroToasts ~= false,
            compare = compareCfg.Enabled == true,
        },
    }
end)
