--[[
    crafting/pipeline.lua — craftId UUID, anti-dupe, inventaire sécurisé
    Flow: start → running → FinalizeCraft (client | watchdog | session) → completed
    FINALISATION is a visual NUI phase only. When remainingMs<=0 the craft MUST complete.
    Timing: craft.startedAt / craft.duration are GetGameTimer() MILLISECONDS.
            craft.startedUnix / completedAt / log finishesAt are Unix SECONDS.
]]

CraftingPipeline = CraftingPipeline or {}

--- active[craftId] = { src, recipeId, benchKey, startedAt (ms), duration (ms), state, ingredients, batch, completed, craftUID }
--- state: queued | running | completing | completed | cancelled | failed
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

local function itemLabelOf(item, override, fallback)
    if OxItemCatalog and OxItemCatalog.Label then
        return OxItemCatalog.Label(item, override, fallback)
    end
    return fallback or item
end

local function recipeFacingLabel(recipe)
    if OxItemCatalog and OxItemCatalog.RecipeLabel then
        return OxItemCatalog.RecipeLabel(recipe)
    end
    return recipe and recipe.label
end

local function recipeFacingDesc(recipe)
    if OxItemCatalog and OxItemCatalog.RecipeDescription then
        return OxItemCatalog.RecipeDescription(recipe)
    end
    return (recipe and recipe.description) or 'Aucune description disponible.'
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

--- remainingMs: duration(ms) - elapsed(ms). Never mix with os.time() seconds.
local function remainingMsOf(craft)
    if not craft then return 0 end
    local nowMs = GetGameTimer() -- ms
    local startedAtMs = tonumber(craft.startedAt) or nowMs -- GetGameTimer ms
    local durationMs = tonumber(craft.duration) or 0 -- ms
    return math.max(0, durationMs - (nowMs - startedAtMs))
end

local function elapsedMsOf(craft)
    if not craft then return 0 end
    local nowMs = GetGameTimer() -- ms
    local startedAtMs = tonumber(craft.startedAt) or nowMs
    return nowMs - startedAtMs
end

local function finishesAtUnixOf(craft)
    local startedUnix = craft and craft.startedUnix
    if type(startedUnix) ~= 'number' then
        startedUnix = os.time()
    end
    return startedUnix + math.ceil(remainingMsOf(craft) / 1000)
end

local function finalizeLogsOn()
    return not Config.Crafting or Config.Crafting.FinalizeLogs ~= false
end

local function craftLog(msg)
    if finalizeLogsOn() then
        print(msg)
    end
end

function CraftingPipeline.Cancel(src, craftId, reason)
    local craft = activeById[craftId]
    if not craft or craft.src ~= src then return false, 'craft_invalid' end
    if craft.state == 'completed' or (craft.completed and craft.state ~= 'running') then
        return true
    end
    if craft.state == 'completing' then
        return false, 'craft_busy'
    end
    -- At 100% / remainingMs<=0: complete instead of refund (player may have closed UI)
    if remainingMsOf(craft) <= 0 and (not craft.state or craft.state == 'running') then
        local r = CraftingPipeline.FinalizeCraft(src, craftId, { reason = 'watchdog', requireNear = false })
        return r and r.ok or false, r and r.reason
    end
    craft.state = 'cancelled'
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
        local craft = activeById[ids[i]]
        if craft and (craft.state == 'completed' or craft.state == 'completing' or craft.completed) then
            clearActive(ids[i], false)
        else
            if craft then craft.state = 'cancelled' end
            clearActive(ids[i], refund)
        end
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
        local bonus = CraftingSkills.GetCategoryBonus(Config.Skills.defaultCategory or 'engineer', src)
        idx = math.min(#tiers, math.max(1, idx + math.floor((bonus or 0) / 25)))
    end
    -- mastery nudge
    if Config.Mastery and Config.Mastery.Enabled and Mastery then
        local m = Mastery.Get(src, recipe.id)
        if m >= 50 then idx = math.min(#tiers, idx + 1) end
        if m >= 90 then idx = math.min(#tiers, idx + 1) end
    end
    if StationRuntime and StationRuntime.QualityNudge then
        -- bench optional via recipe._benchHint set by caller
        local nudge = StationRuntime.QualityNudge(recipe._benchHint)
        idx = math.min(#tiers, math.max(1, idx + nudge))
    end
    return tiers[idx] or Config.Quality.DefaultTier or 'normal'
end

function CraftingPipeline.RollQuality(src, recipe, bench)
    if recipe and bench then recipe._benchHint = bench end
    local q = rollQuality(src, recipe)
    if recipe then recipe._benchHint = nil end
    return q
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


--- Spec + knowledge (identity). NEVER skipped by BypassRequirements.
local function checkIdentityGates(src, recipe, bench)
    if Specializations and Specializations.CanUseStation and bench then
        local okS, reasonS, argsS = Specializations.CanUseStation(src, bench.category or bench)
        if not okS then return false, reasonS, argsS end
    end
    if Specializations and Specializations.CanCraftRecipe then
        local okC, reasonC, argsC = Specializations.CanCraftRecipe(src, recipe)
        if not okC then return false, reasonC, argsC end
    end
    if Blueprints and Blueprints.KnowsRecipe then
        if not Blueprints.KnowsRecipe(src, recipe) then
            local bpId = recipe.requireBlueprint or recipe.blueprintId
            if bpId then
                return false, 'craft_blueprint_required', { bpId }
            end
            return false, 'craft_knowledge_required', { recipe.id }
        end
    end
    return true
end

function CraftingPipeline.CheckIdentityGates(src, recipe, bench)
    return checkIdentityGates(src, recipe, bench)
end

local function validateStart(src, recipeId, benchKey, batch, opts)
    opts = opts or {}
    local queued = opts.queued == true

    if type(recipeId) ~= 'string' or type(benchKey) ~= 'string' then
        return nil, 'craft_invalid'
    end
    if not queued and not Validation.CanStartAnotherCraft(src) then
        return nil, 'craft_busy'
    end
    local okRate, rateReason = Validation.CheckRateLimit(src)
    if not okRate then return nil, rateReason end

    local recipe = Config.RecipeById[recipeId]
    if not recipe then
        if CraftingAnomaly then CraftingAnomaly.Warn('unknown_recipe', src, { recipeId = recipeId }) end
        return nil, 'craft_invalid'
    end
    if recipe._disabled then
        if CraftingAnomaly then CraftingAnomaly.Warn('unknown_recipe', src, { recipeId = recipeId, disabled = true }) end
        return nil, 'craft_invalid'
    end
    local reqBatch = math.floor(tonumber(batch) or 1)
    if reqBatch ~= reqBatch or reqBatch < 1 then
        if CraftingAnomaly then CraftingAnomaly.Warn('bad_qty', src, { batch = batch, recipeId = recipeId }) end
        return nil, 'craft_invalid'
    end
    local hardCap = (CraftBatch and CraftBatch.HardCap and CraftBatch.HardCap()) or 100
    if reqBatch > hardCap then
        if CraftingAnomaly then CraftingAnomaly.Warn('batch_over_cap', src, { batch = reqBatch, cap = hardCap, recipeId = recipeId }) end
    end
    if OxItemCatalog and OxItemCatalog.Get then
        local ri = recipe.result and recipe.result.item
        if ri and not OxItemCatalog.Get(ri) then
            if CraftingAnomaly then CraftingAnomaly.Warn('missing_ox_item', src, { item = ri, recipeId = recipe.id }) end
        end
        for i = 1, #(recipe.ingredients or {}) do
            local it = recipe.ingredients[i] and recipe.ingredients[i].item
            if it and not OxItemCatalog.Get(it) then
                if CraftingAnomaly then CraftingAnomaly.Warn('missing_ox_item', src, { item = it, recipeId = recipe.id }) end
            end
        end
    end

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
    if StationRuntime and StationRuntime.CanRun then
        local okRun, runReason = StationRuntime.CanRun(bench, recipe)
        if not okRun then return nil, runReason or 'craft_failed' end
    end

    if CraftBatch and CraftBatch.Clamp then
        local clamped, lim = CraftBatch.Clamp(src, recipe, bench, batch, { queued = queued })
        if Config.Batch and Config.Batch.Enabled == false then
            clamped = 1
        end
        if clamped < 1 then
            if lim and lim.queue == 0 and queued then return nil, 'queue_full' end
            if lim and lim.tools == 0 then return nil, 'craft_tool_required' end
            if lim and lim.energy == 0 then return nil, 'craft_no_power' end
            if lim and lim.mats == 0 then return nil, 'craft_no_ingredients' end
            return nil, 'craft_batch_max'
        end
        local hard = CraftBatch.HardCap and CraftBatch.HardCap() or 100
        local req = math.floor(tonumber(batch) or 1)
        if req > hard or req > (lim and lim.recipe or hard) then
            -- requested above cap
            batch = clamped
        else
            batch = clamped
        end
    else
        batch = math.max(1, math.floor(tonumber(batch) or 1))
    end

    local okSkill, skillReason, skillArgs = true, nil, nil
    if CraftingSkills and CraftingSkills.CheckRecipeGates then
        okSkill, skillReason, skillArgs = CraftingSkills.CheckRecipeGates(src, recipe)
    end
    if not okSkill then return nil, skillReason, skillArgs end

    local okIdent, identReason, identArgs = checkIdentityGates(src, recipe, bench)
    if not okIdent then return nil, identReason, identArgs end

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

    if Tools and Tools.HasRecipe and not Tools.HasRecipe(src, recipe) then
        return nil, 'craft_tool_required'
    end

    return {
        recipe = recipe, bench = bench, batch = batch,
        ingredients = ingredients,
    }
end

function CraftingPipeline.ValidateStart(src, recipeId, benchKey, batch, opts)
    return validateStart(src, recipeId, benchKey, batch, opts)
end

function CraftingPipeline._startInner(src, recipeId, benchKey, batch)
    local ctx, reason, args = validateStart(src, recipeId, benchKey, batch)
    if not ctx then return { ok = false, reason = reason, args = args } end

    if CraftingSkills and CraftingSkills.NotifyBypassIfNeeded then
        CraftingSkills.NotifyBypassIfNeeded(src)
    end

    local recipe, bench = ctx.recipe, ctx.bench
    local removed = false
    if CraftingMaterials and CraftingMaterials.ConsumeOnStart and CraftingMaterials.ConsumeOnStart() then
        local okTake = CraftingMaterials.Take(src, ctx.ingredients)
        if not okTake then
            return { ok = false, reason = 'craft_no_ingredients' }
        end
        removed = true
    end

    local stepIndex = 1
    local totalSteps = recipeHasSteps(recipe) and #recipe.steps or 1
    local rawDur = stepDuration(recipe, stepIndex)
    local duration = CraftingSkills.ApplyCraftTimeBonus(rawDur, src)
    if StationRuntime and StationRuntime.ApplyDuration then
        duration = StationRuntime.ApplyDuration(duration, bench)
    end
    if ctx.batch > 1 then
        duration = math.floor(duration * ctx.batch * 0.85) -- slight batch efficiency
    end

    local step = select(1, currentStepInfo(recipe, stepIndex))
    local facing = recipeFacingLabel(recipe)
    local stepLabel = (step and step.label) or facing

    local craftId = GenerateCraftId()
    local craftUID = ('%s:%s:%d'):format(recipe.id, craftId:sub(1, 8), os.time())
    local craft = {
        craftId = craftId, craftUID = craftUID, src = src,
        recipeId = recipe.id, benchKey = bench.key,
        startedAt = GetGameTimer(), startedUnix = os.time(),
        duration = duration, batch = ctx.batch,
        ingredients = ctx.ingredients, removed = removed,
        completed = false,
        state = 'running',
        stepIndex = stepIndex, totalSteps = totalSteps,
        removedHistory = removed and { ctx.ingredients } or {},
    }
    if RecipeSnapshot and RecipeSnapshot.Capture then
        local snap, ver = RecipeSnapshot.Capture(recipe)
        craft.snapshot = snap
        craft.recipeVersion = ver or 0
    else
        craft.snapshot = recipe
        craft.recipeVersion = tonumber(recipe._version) or 0
    end
    if type(craft.startedUnix) ~= 'number' or craft.startedUnix <= 0 then
        if CraftingAnomaly then CraftingAnomaly.Warn('bad_timestamp', src, { recipeId = recipe.id }) end
    end
    registerActive(src, craft)
    emitNoise(src, recipe, bench)
    CraftingCore.Emit('craftStarted', src, craft)

    do
        local startedUnix = craft.startedUnix -- unix s
        local finishesAtUnix = startedUnix + math.ceil(duration / 1000) -- duration is ms
        craftLog(('[CRAFT] start id=%s startedAt=%s finishesAt=%s durationMs=%s'):format(
            craftId, tostring(startedUnix), tostring(finishesAtUnix), tostring(duration)
        ))
    end
    DebugPrint('startCraft', src, craftId, recipe.id, duration, 'step', stepIndex, '/', totalSteps)
    local resultItem = recipe.result and recipe.result.item or nil
    local resultCount = recipe.result and ((recipe.result.count or 1) * ctx.batch) or ctx.batch
    local phaseFamily = recipe.category or bench.category
    return {
        ok = true, craftId = craftId, craftUID = craftUID,
        duration = duration, label = facing, batch = ctx.batch,
        stepIndex = stepIndex, totalSteps = totalSteps,
        stepLabel = stepLabel,
        recipeId = recipe.id,
        resultItem = resultItem,
        resultCount = resultCount,
        benchKey = bench.key,
        benchLabel = bench.label,
        category = recipe.category or bench.category,
        phaseFamily = phaseFamily,
        cancelDistance = Config.CraftCancelDistance,
        benchCoords = { x = bench.coords.x, y = bench.coords.y, z = bench.coords.z },
        anim = (Config.Animations and Config.Animations.Default) or nil,
    }
end

function CraftingPipeline.Start(src, recipeId, benchKey, batch)
    if type(recipeId) ~= 'string' or type(benchKey) ~= 'string' then
        if CraftingAnomaly then CraftingAnomaly.Warn('unknown_recipe', src, { recipeId = recipeId }) end
        return { ok = false, reason = 'craft_invalid' }
    end
    local lockOk, lockErr = true, nil
    if CraftLocks and CraftLocks.Acquire then
        lockOk, lockErr = CraftLocks.Acquire(src, benchKey)
        if not lockOk then return { ok = false, reason = lockErr or 'craft_busy' } end
    end
    local okRun, result = pcall(CraftingPipeline._startInner, src, recipeId, benchKey, batch)
    if CraftLocks and CraftLocks.Release then
        CraftLocks.Release(src, benchKey)
    end
    if not okRun then
        print(('[sanctuary_crafting] startCraft error: %s'):format(tostring(result)))
        return { ok = false, reason = 'craft_failed' }
    end
    return result
end

lib.callback.register('sanctuary_crafting:startCraft', function(src, recipeId, benchKey, batch)
    -- client sends only recipeId / qty / station
    return CraftingPipeline.Start(src, recipeId, benchKey, batch)
end)

function CraftingPipeline.FinalizeCraft(src, craftId, opts)
    opts = opts or {}
    local reason = opts.reason or 'client'
    craftLog(('[CRAFT] finalizeCraft called id=%s src=%s reason=%s'):format(tostring(craftId), tostring(src), tostring(reason)))

    if type(craftId) ~= 'string' then
        return { ok = false, reason = 'craft_invalid' }
    end
    local craft = activeById[craftId]
    if not craft then
        return { ok = false, reason = 'craft_invalid' }
    end
    if craft.src ~= src then
        return { ok = false, reason = 'craft_invalid' }
    end

    -- Idempotent / double-grant protection (KEEP completing-lock)
    if craft.state == 'completed' or craft.completed == true then
        if CraftingAnomaly then CraftingAnomaly.Warn('double_complete', src, { craftId = craftId, state = craft.state }) end
        return { ok = true, already = true, craftId = craftId }
    end
    if craft.state == 'completing' then
        if CraftingAnomaly then CraftingAnomaly.Warn('double_complete', src, { craftId = craftId, state = 'completing' }) end
        return { ok = true, already = true, pending = true, craftId = craftId }
    end
    if craft.state and craft.state ~= 'running' then
        return { ok = false, reason = 'craft_invalid' }
    end

    -- Timing: startedAt = GetGameTimer() ms; duration = ms
    local elapsedMs = elapsedMsOf(craft)
    local remainingMs = remainingMsOf(craft)
    local durationMs = tonumber(craft.duration) or 0
    local factor = (Config.Crafting and Config.Crafting.MinDurationFactor) or 0.85
    local minTime = math.floor(durationMs * factor)
    -- Anti-cheat: elapsed < duration * MinDurationFactor → reject early complete.
    -- Watchdog / session only call when remainingMs<=0 (elapsed >= duration >= minTime).
    if elapsedMs < minTime then
        if reason == 'watchdog' or reason == 'session' then
            return { ok = false, reason = 'craft_not_ready' }
        end
        craft.state = 'failed'
        clearActive(craftId, craft.removed and Config.Crafting.RefundOnCancel)
        return { ok = false, reason = 'craft_failed' }
    end

    -- SNAPSHOT at start isolates in-flight crafts from live admin edits
    local recipe = RecipeSnapshot and RecipeSnapshot.Of(craft) or craft.snapshot
    if type(recipe) ~= 'table' then
        if CraftingAnomaly then CraftingAnomaly.Warn('unknown_recipe', src, { craftId = craftId, recipeId = craft.recipeId, where = 'finalize_no_snapshot' }) end
        craft.state = 'failed'
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_invalid' }
    end
    local bench = Benches and Benches.Resolve and Benches.Resolve(craft.benchKey)
    if not bench then
        craft.state = 'failed'
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_invalid' }
    end

    -- Distance: remainingMs<=0 OR watchdog/session → never craft_too_far, never refund.
    -- Client early complete (remainingMs > 0) keeps the near-bench check.
    local requireNear = opts.requireNear
    if remainingMs <= 0 or reason == 'watchdog' or reason == 'session' then
        requireNear = false
    elseif requireNear == nil then
        requireNear = remainingMs > 0
    end
    if requireNear then
        if not Validation.IsNearBench(src, bench.coords, Config.CraftCancelDistance or 3.0) then
            craft.state = 'failed'
            clearActive(craftId, craft.removed and Config.Crafting.RefundOnCancel)
            return { ok = false, reason = 'craft_too_far' }
        end
    end

    local okSkill = CraftingSkills and CraftingSkills.CheckRecipeGates and CraftingSkills.CheckRecipeGates(src, recipe)
    if not okSkill then
        craft.state = 'failed'
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_failed' }
    end
    local okIdent = checkIdentityGates(src, recipe, bench)
    if not okIdent then
        craft.state = 'failed'
        clearActive(craftId, craft.removed)
        return { ok = false, reason = 'craft_failed' }
    end

    -- Optional wear/heat fail (not frustrating; small chance when damaged/overheat)
    if StationRuntime then
        local fail = StationRuntime.FailChance and StationRuntime.FailChance(bench) or 0
        if StationRuntime.HeatEnabled and StationRuntime.HeatEnabled(bench) then
            local h = Config.Stations and Config.Stations.Heat or {}
            if StationRuntime.GetTemp(bench) >= (h.OverheatAt or 85) then
                fail = fail + (h.BreakdownChanceOverheat or 0.04)
            end
        end
        if fail > 0 and math.random() < math.min(0.25, fail) then
            craft.state = 'failed'
            clearActive(craftId, craft.removed)
            if StationRuntime.Degrade then StationRuntime.Degrade(bench, recipe, craft.batch or 1) end
            return { ok = false, reason = 'craft_failed' }
        end
    end

    -- Lock BEFORE rewards so a second call cannot grant twice
    craft.state = 'completing'
    craft.completed = true

    -- Remove on complete if not removed at start (single-step or current step)
    if not craft.removed then
        if not Validation.HasIngredients(src, craft.ingredients) then
            craft.state = 'failed'
            clearActive(craftId, false)
            return { ok = false, reason = 'craft_no_ingredients' }
        end
        for i = 1, #craft.ingredients do
            local ing = craft.ingredients[i]
            if not exports.ox_inventory:RemoveItem(src, ing.item, ing.count) then
                craft.state = 'failed'
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
            craft.state = 'failed'
            clearActive(craftId, false)
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
                craft.state = 'failed'
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
        craft.completed = false
        craft.state = 'running'
        local nextStep = recipe.steps[nextIndex]
        local rawDur = stepDuration(recipe, nextIndex)
        local duration = CraftingSkills.ApplyCraftTimeBonus(rawDur, src)
        if StationRuntime and StationRuntime.ApplyDuration then
            duration = StationRuntime.ApplyDuration(duration, bench)
        end
        if (craft.batch or 1) > 1 then
            duration = math.floor(duration * craft.batch * 0.85)
        end
        craft.duration = duration -- ms
        craft.startedAt = GetGameTimer() -- ms
        craft.startedUnix = os.time() -- unix s
        local stepLabel = (nextStep and nextStep.label) or recipe.label
        CraftingCore.Emit('craftStepAdvanced', src, craft, nextIndex, totalSteps)
        DebugPrint('advanceStep', src, craftId, nextIndex, '/', totalSteps)
        local payload = {
            ok = true, advanced = true, craftId = craftId, craftUID = craft.craftUID,
            stepIndex = nextIndex, totalSteps = totalSteps,
            duration = duration, label = stepLabel, stepLabel = stepLabel,
            batch = craft.batch,
            benchKey = craft.benchKey,
        }
        TriggerClientEvent('sanctuary_crafting:client:craftAdvanced', src, payload)
        return payload
    end

    local batch = craft.batch or 1
    local resultItem = recipe.result.item
    local resultCount = (recipe.result.count or 1) * batch

    local given = {}
    if recipe.dismantle and Config.Dismantling and Config.Dismantling.Enabled and recipe.dismantleYields then
        local bonus = 0
        if Config.Dismantling.SkillYieldBonus then
            bonus = (CraftingSkills.GetCategoryBonus(Config.Skills.defaultCategory or 'engineer', src) or 0) / 100
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
        local quality = CraftingPipeline.RollQuality(src, recipe, bench)

        if not Validation.CanCarry(src, resultItem, resultCount) then
            if CraftingMaterials and CraftingMaterials.Give then
                CraftingMaterials.Give(src, craft.ingredients)
            else
                for i = 1, #craft.ingredients do
                    local ing = craft.ingredients[i]
                    exports.ox_inventory:AddItem(src, ing.item, ing.count)
                end
            end
            craft.state = 'failed'
            clearActive(craftId, false)
            return { ok = false, reason = 'craft_inventory_full' }
        end

        local okGive = false
        if CraftSignature and CraftSignature.GiveResult then
            okGive = CraftSignature.GiveResult(src, recipe, bench, quality, craft.craftId, resultCount)
        else
            local meta = { craftedBy = GetPlayerIdentifierSafe(src) }
            if quality then meta.quality = quality end
            okGive = exports.ox_inventory:AddItem(src, resultItem, resultCount, meta) and true or false
        end
        if not okGive then
            if CraftingMaterials and CraftingMaterials.Give then
                CraftingMaterials.Give(src, craft.ingredients)
            else
                for i = 1, #craft.ingredients do
                    local ing = craft.ingredients[i]
                    exports.ox_inventory:AddItem(src, ing.item, ing.count)
                end
            end
            craft.state = 'failed'
            clearActive(craftId, false)
            return { ok = false, reason = 'craft_inventory_full' }
        end
        given[#given + 1] = { item = resultItem, count = resultCount, quality = quality }
        giveByproducts(src, recipe)
        if Tools and Tools.WearRecipe then
            Tools.WearRecipe(src, recipe, batch)
        end
        if StationRuntime and StationRuntime.Degrade then
            StationRuntime.Degrade(bench, recipe, batch)
        end
    end

    craftLog(('[CRAFT] reward granted id=%s item=%s count=%s'):format(
        craftId, tostring(given[1] and given[1].item or resultItem), tostring(given[1] and given[1].count or resultCount)
    ))

    if recipe.xp and recipe.xp.category and recipe.xp.amount then
        CraftingSkills.AddCraftXp(src, recipe.xp.category, recipe.xp.amount * batch)
        if NewlyLearned and NewlyLearned.ScanLevelUnlocks then
            NewlyLearned.ScanLevelUnlocks(src)
        end
    end

    if Config.Mastery and Config.Mastery.Enabled and Mastery then
        Mastery.Add(src, recipe.id, (Config.Mastery.XpPerCraft or 1) * batch)
    end

    craft.state = 'completed'
    craft.completedAt = os.time() -- unix s
    craftLog(('[CRAFT] state completed id=%s completedAt=%s'):format(craftId, tostring(craft.completedAt)))

    clearActive(craftId, false)
    CraftingCore.Emit('craftCompleted', src, craft, given)
    DebugPrint('completeCraft ok', src, craftId)

    local chainNext = nil
    if type(recipe.chain) == 'table' and #recipe.chain > 0 then
        chainNext = recipe.chain[1]
    end

    local resultPayload = {
        ok = true, craftId = craftId, craftUID = craft.craftUID,
        result = given[1] or recipe.result, results = given,
        label = recipeFacingLabel(recipe), quality = given[1] and given[1].quality,
        stepIndex = craft.stepIndex or totalSteps, totalSteps = totalSteps,
        chainNext = chainNext, chain = recipe.chain,
        advanced = false,
        batch = batch,
        benchKey = craft.benchKey,
    }
    TriggerClientEvent('sanctuary_crafting:client:craftFinished', src, {
        craftId = craftId,
        label = recipeFacingLabel(recipe),
        result = resultPayload.result,
        batch = batch,
        benchKey = craft.benchKey,
    })

    -- Queue-next: CraftQueue entries already have their own finishAt + collect path.
    -- Do not force-start a queued job as an interactive craft. Auto-promote of the
    -- next interactive job is deferred (no existing Enqueue→startCraft hook).

    return resultPayload
end

lib.callback.register('sanctuary_crafting:completeCraft', function(src, craftId)
    if type(craftId) ~= 'string' then return { ok = false, reason = 'craft_invalid' } end
    local craft = activeById[craftId]
    local remainingMs = craft and remainingMsOf(craft) or 0
    -- Client at 100% (remainingMs<=0) skips the near-bench gate — player may have closed UI.
    return CraftingPipeline.FinalizeCraft(src, craftId, {
        reason = 'client',
        requireNear = remainingMs > 0,
    })
end)

--- Watchdog: never leave a craft running at remainingMs<=0 (100% / 0s / FINALISATION).
CreateThread(function()
    while true do
        Wait(2000)
        local ids = {}
        for craftId in pairs(activeById) do
            ids[#ids + 1] = craftId
        end
        for i = 1, #ids do
            local craft = activeById[ids[i]]
            if craft and craft.state == 'running' and remainingMsOf(craft) <= 0 then
                craftLog(('[CRAFT] finished timestamp reached id=%s finishesAt=%s'):format(
                    craft.craftId, tostring(finishesAtUnixOf(craft))
                ))
                CraftingPipeline.FinalizeCraft(craft.src, craft.craftId, {
                    reason = 'watchdog',
                    requireNear = false,
                })
            end
        end
    end
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
    local set = activeBySrc[src]
    if set then
        local ids = {}
        for id in pairs(set) do ids[#ids + 1] = id end
        for i = 1, #ids do
            local craft = activeById[ids[i]]
            if craft and remainingMsOf(craft) <= 0 and (craft.state == 'running' or not craft.state) then
                CraftingPipeline.FinalizeCraft(src, craft.craftId, { reason = 'session', requireNear = false })
            end
        end
    end
    local refund = Config.Crafting and Config.Crafting.RefundOnDisconnect
    CraftingPipeline.CancelAll(src, refund)
    Validation.ClearPlayer(src)
end)



-- Interactive crafts live in RAM (GetGameTimer). Close/reopen NUI rehydrates via GetSession.
-- Disconnect still cancels interactive crafts (playerDropped). Queue SQL covers queued/offline.
-- Persisting interactive crafts across reconnect is deferred (not in this version).

local function craftSessionDebug()
    return Config.Debug or (Config.CraftTracker and Config.CraftTracker.Debug)
end

local function serializeActiveCraft(craft)
    local nowMs = GetGameTimer() -- ms
    local startedAtMs = craft.startedAt or nowMs -- GetGameTimer ms
    local durationMs = tonumber(craft.duration) or 0 -- ms
    local remainingMs = remainingMsOf(craft) -- ms
    local nowUnix = os.time() -- unix s
    local startedUnix = craft.startedUnix
    if type(startedUnix) ~= 'number' then
        startedUnix = nowUnix - math.floor(math.max(0, nowMs - startedAtMs) / 1000)
    end
    -- finishesAt unix seconds from remaining (GetGameTimer ms)
    local finishesAt = startedUnix + math.ceil(remainingMs / 1000)

    local recipe = (RecipeSnapshot and RecipeSnapshot.Of(craft)) or craft.snapshot or (Config.RecipeById and Config.RecipeById[craft.recipeId])
    local bench = Benches and Benches.Resolve and Benches.Resolve(craft.benchKey)
    local batch = craft.batch or 1
    local resultItem = recipe and recipe.result and recipe.result.item or nil
    local resultCount = recipe and recipe.result and ((recipe.result.count or 1) * batch) or batch
    local label = (recipe and recipeFacingLabel(recipe)) or craft.recipeId
    local step = recipe and select(1, currentStepInfo(recipe, craft.stepIndex or 1)) or nil
    local stepLabel = (step and step.label) or label
    local category = (recipe and recipe.category) or (bench and bench.category)
    local benchLabel = (bench and bench.label) or nil

    return {
        craftId = craft.craftId,
        recipeId = craft.recipeId,
        benchKey = craft.benchKey,
        benchLabel = benchLabel,
        label = label,
        resultItem = resultItem,
        resultCount = resultCount,
        batch = batch,
        quantity = batch,
        state = craft.state or 'running',
        startedAt = startedUnix,
        finishesAt = finishesAt,
        duration = remainingMs,
        durationMs = durationMs,
        remainingMs = remainingMs,
        stepIndex = craft.stepIndex or 1,
        totalSteps = craft.totalSteps or 1,
        stepLabel = stepLabel,
        category = category,
        phaseFamily = category,
    }
end

--- Serialize in-memory interactive crafts for src.
--- @param src number
--- @param benchKey string|nil  if set, first return is this station only; second is other benches
--- @return table matching, table other
function CraftingPipeline.SerializeActive(src, benchKey)
    local matching, other = {}, {}
    local set = activeBySrc[src]
    if not set then return matching, other end
    for craftId in pairs(set) do
        local craft = activeById[craftId]
        if craft and craft.src == src and (craft.state == 'running' or not craft.state) and not craft.completed then
            local row = serializeActiveCraft(craft)
            if benchKey and craft.benchKey ~= benchKey then
                other[#other + 1] = row
            else
                matching[#matching + 1] = row
            end
        end
    end
    return matching, other
end

--- Station-scoped session (source of truth for NUI rehydrate).
--- Interactive = RAM pipeline; queued = CraftQueue (SQL-backed offline).
function CraftingPipeline.GetSession(src, benchKey)
    -- Finalize expired running crafts BEFORE serialize so the client never
    -- rehydrates a 100%/0s/FINALISATION interactive job.
    local set = activeBySrc[src]
    if set then
        local ids = {}
        for craftId in pairs(set) do ids[#ids + 1] = craftId end
        for i = 1, #ids do
            local craft = activeById[ids[i]]
            if craft and craft.src == src and (craft.state == 'running' or not craft.state) then
                if remainingMsOf(craft) <= 0 then
                    CraftingPipeline.FinalizeCraft(src, craft.craftId, {
                        reason = 'session',
                        requireNear = false,
                    })
                end
            end
        end
    end
    local active, other = CraftingPipeline.SerializeActive(src, benchKey)
    local queued = {}
    if CraftQueue and CraftQueue.List then
        local list = CraftQueue.List(src) or {}
        for i = 1, #list do
            local e = list[i]
            if not benchKey or e.benchKey == benchKey then
                local finishAt = tonumber(e.finishAt) or 0
                local createdAt = tonumber(e.createdAt) or finishAt
                local durationMs = tonumber(e.duration) or math.max(0, (finishAt - createdAt) * 1000)
                local remainingMs = math.max(0, (finishAt - os.time()) * 1000)
                queued[#queued + 1] = {
                    craftId = e.craftId,
                    recipeId = e.recipeId,
                    benchKey = e.benchKey,
                    batch = e.batch or 1,
                    quantity = e.batch or 1,
                    ingredients = e.ingredients,
                    finishAt = finishAt,
                    finishesAt = finishAt,
                    createdAt = createdAt,
                    startedAt = createdAt,
                    duration = durationMs,
                    durationMs = durationMs,
                    remainingMs = remainingMs,
                    label = e.label,
                    state = 'queued',
                }
            end
        end
    end
    local session = {
        stationId = benchKey,
        active = active,
        queued = queued,
        other = other,
    }
    if craftSessionDebug() then
        local first = active[1]
        print(('[sanctuary_crafting] opening station=%s stationId=%s active=%d queued=%d craftId=%s startedAt=%s finishesAt=%s'):format(
            tostring(benchKey),
            tostring(session.stationId),
            #active,
            #queued,
            first and first.craftId or '-',
            first and tostring(first.startedAt) or '-',
            first and tostring(first.finishesAt) or '-'
        ))
    end
    return session
end

lib.callback.register('sanctuary_crafting:getCraftSession', function(src, benchKey)
    if type(benchKey) ~= 'string' then
        return { ok = false, reason = 'craft_invalid' }
    end
    return { ok = true, session = CraftingPipeline.GetSession(src, benchKey) }
end)

-- Menu / NUI data

local BP_TIER_LABEL = {
    military = 'PLAN MILITAIRE',
    industriel = 'PLAN INDUSTRIEL',
    industrial = 'PLAN INDUSTRIEL',
    medical = 'PLAN MÉDICAL',
    experimental = 'PLAN EXPÉRIMENTAL',
    ['expérimental'] = 'PLAN EXPÉRIMENTAL',
}

local function blueprintMetaOf(r)
    local meta = type(r.blueprintMeta) == 'table' and r.blueprintMeta or {}
    local tier = meta.tier or meta.type or r.blueprintTier or r.blueprintType
    if type(tier) == 'string' then
        tier = tier:lower()
    else
        tier = nil
    end
    local label = meta.label or (tier and BP_TIER_LABEL[tier]) or nil
    if not tier and not label and not next(meta) then
        return nil
    end
    return {
        tier = tier,
        type = tier,
        label = label,
    }
end

local function resolveKnowledge(src, r, mastery, hasBp, lockReason)
    local kn = Config.Knowledge
    if not kn or kn.Enabled == false or kn.States == false then
        return nil, nil
    end
    local threshold = (Config.Mastery and (Config.Mastery.MasteredThreshold or Config.Mastery.MaxMastery)) or 100
    local bpId = r.requireBlueprint or r.blueprintId
    local source = r.knowledgeSource
    if type(source) ~= 'string' or source == '' then
        if bpId and hasBp then
            source = 'blueprint'
        elseif r.trainerId or r.knowledgeFrom == 'trainer' then
            source = 'trainer'
        else
            source = bpId and nil or 'default'
        end
    end

    local state
    if Config.Mastery and Config.Mastery.Enabled and mastery >= threshold then
        state = 'mastered'
    elseif r.partialKnowledge == true then
        state = 'partial'
    elseif type(r.maskedIngredients) == 'table' and #r.maskedIngredients > 0 then
        state = 'partial'
    elseif bpId and not hasBp then
        state = 'unknown'
    elseif bpId and hasBp and (mastery or 0) <= 0 then
        state = 'blueprint'
    elseif lockReason == 'craft_blueprint_required' then
        state = 'unknown'
    else
        state = 'learned'
    end

    -- Book-masked ingredients → partial (only when Book resources enabled)
    if state == 'learned' or state == 'blueprint' then
        if SurvivalBook and SurvivalBook.HasDiscoveredResource and BookDB and BookDB.Mod
            and (BookDB.Mod('Resources') or BookDB.Mod('Discoveries')) then
            local ings = r.ingredients or {}
            local anyKnown, anyUnknown = false, false
            for i = 1, #ings do
                local it = ings[i] and ings[i].item
                if it then
                    if SurvivalBook.HasDiscoveredResource(src, it) then
                        anyKnown = true
                    else
                        anyUnknown = true
                    end
                end
            end
            -- Only treat as partial when discoveries exist for this player and some mats are veiled
            if anyKnown and anyUnknown and (r.partialKnowledge == true or r.knowledgePartial == true) then
                state = 'partial'
            end
        end
    end

    return state, source
end

local function findProducerRecipe(item)
    if not item or not Config.RecipeById then return nil end
    for id, rr in pairs(Config.RecipeById) do
        if rr.result and rr.result.item == item and not rr.dismantle then
            return rr
        end
    end
    return nil
end

local function findDismantleSources(src, item)
    if not item then return {} end
    if not Config.Dismantling or not Config.Dismantling.Enabled then return {} end
    local bookOn = SurvivalBook and SurvivalBook.HasDiscoveredResource
        and BookDB and BookDB.Mod and (BookDB.Mod('Resources') or BookDB.Mod('Discoveries'))
    local out = {}
    for _, rr in pairs(Config.RecipeById or {}) do
        if rr.dismantle == true then
            local yields = rr.dismantleYields or rr.yields or rr.result
            local list = {}
            if type(yields) == 'table' then
                if yields.item then
                    list[1] = yields
                else
                    for i = 1, #yields do list[#list + 1] = yields[i] end
                    if #list == 0 then
                        for _, v in pairs(yields) do
                            if type(v) == 'table' and v.item then list[#list + 1] = v end
                        end
                    end
                end
            end
            -- also: dismantle recipes often consume an item and yield ingredients;
            -- reverse map: recipes that list this item as a yield/byproduct
            local hit = false
            for i = 1, #list do
                if list[i].item == item then hit = true; break end
            end
            if not hit and rr.result and rr.result.item == item then hit = true end
            if hit then
                local sourceItem = (rr.ingredients and rr.ingredients[1] and rr.ingredients[1].item) or rr.id
                if bookOn then
                    if SurvivalBook.HasDiscoveredResource(src, sourceItem)
                        or SurvivalBook.HasDiscoveredResource(src, item) then
                        out[#out + 1] = { recipeId = rr.id, label = recipeFacingLabel(rr), item = sourceItem }
                    end
                end
            end
        end
    end
    -- Reverse: normal recipes whose ingredients include item and that have dismantleYields pointing back
    for _, rr in pairs(Config.RecipeById or {}) do
        local dy = rr.dismantleYields
        if type(dy) == 'table' then
            for i = 1, #dy do
                if dy[i] and dy[i].item == item then
                    local srcItem = rr.result and rr.result.item
                    if srcItem and bookOn and SurvivalBook.HasDiscoveredResource(src, srcItem) then
                        out[#out + 1] = { recipeId = rr.id, label = recipeFacingLabel(rr), item = srcItem }
                    end
                end
            end
        end
    end
    return out
end

local function buildPathHints(src, r, entry, artisans)
    local ux = (Config.UI and Config.UI.Ux) or {}
    if ux.PathHints == false then return {}, false end
    local hints = {}
    local more = false

    local function push(h)
        if #hints >= 3 then
            more = true
            return false
        end
        hints[#hints + 1] = h
        return true
    end

    -- missing materials
    local ings = entry.ingredients or {}
    for i = 1, #ings do
        local ing = ings[i]
        local need = ing.count or 1
        local owned = ing.owned or 0
        if owned < need then
            local deficit = need - owned
            if not push({
                kind = 'missing',
                title = 'MATÉRIAU MANQUANT',
                detail = string.format('%s · %d manquant(s) (%d/%d)', ing.label or ing.item, deficit, owned, need),
                priority = 10 + i,
            }) then break end
            -- craftable component
            local prod = findProducerRecipe(ing.item)
            if prod then
                -- only if player would "know" it: no missing bp, or has bp
                local prodBp = prod.requireBlueprint or prod.blueprintId
                local known = true
                if prodBp and Config.Blueprints and Config.Blueprints.Enabled and Blueprints then
                    known = Blueprints.Has(src, prodBp)
                end
                if known then
                    if not push({
                        kind = 'craft',
                        title = 'FABRIQUER LE COMPOSANT',
                        detail = recipeFacingLabel(prod) or prod.id,
                        recipeId = prod.id,
                        priority = 20,
                    }) then break end
                end
            end
            -- dismantle recovery (discovered only)
            local sources = findDismantleSources(src, ing.item)
            if sources[1] then
                if not push({
                    kind = 'dismantle',
                    title = 'RÉCUPÉRATION CONNUE',
                    detail = string.format('Via %s', sources[1].label or sources[1].item),
                    recipeId = sources[1].recipeId,
                    priority = 25,
                }) then break end
            end
        end
    end

    -- skill progression
    if entry.lockReason == 'craft_level_required' and entry.levelGap and entry.levelGap > 0 then
        push({
            kind = 'skill',
            title = 'PROGRESSION',
            detail = string.format('%d niveau(x) restant(s)', entry.levelGap),
            priority = 30,
        })
    end

    -- blueprint missing
    local bpId = entry.requireBlueprint or r.blueprintId
    if bpId and entry.lockReason == 'craft_blueprint_required' then
        local detail = 'Plan technique requis'
        -- discovered hint only if book knows the blueprint item/resource
        if SurvivalBook and SurvivalBook.HasDiscoveredResource and SurvivalBook.HasDiscoveredResource(src, bpId) then
            detail = string.format('Plan requis · indice connu : %s', itemLabelOf(bpId) or bpId)
        end
        push({
            kind = 'blueprint',
            title = 'PLAN REQUIS',
            detail = detail,
            priority = 5,
        })
    end

    -- artisan potential (specialty match) — do not claim they know the recipe
    if artisans and #artisans > 0 then
        local spec = (r.skillTree and r.skillTree.category) or r.requireSpec or r.category or r.station
        if spec then
            local specL = tostring(spec):lower()
            for i = 1, #artisans do
                local a = artisans[i]
                local as = a.specialty and tostring(a.specialty):lower() or ''
                if as ~= '' and (as == specL or specL:find(as, 1, true) or as:find(specL, 1, true)) then
                    push({
                        kind = 'artisan',
                        title = 'CONTACT POTENTIEL',
                        detail = a.displayName or a.name or a.contactId,
                        artisanId = a.contactId or a.id,
                        priority = 40,
                    })
                    break
                end
            end
        end
    end

    table.sort(hints, function(a, b) return (a.priority or 99) < (b.priority or 99) end)
    while #hints > 3 do
        more = true
        hints[#hints] = nil
    end
    return hints, more
end

local function buildArtisanHints(src, r, artisans, orders)
    local ux = (Config.UI and Config.UI.Ux) or {}
    if ux.ArtisanHints == false then
        return { potential = {}, confirmed = {} }
    end
    if not artisans then artisans = {} end
    local potential, confirmed = {}, {}
    local spec = (r.skillTree and r.skillTree.category) or r.requireSpec or r.category or r.station
    local specL = spec and tostring(spec):lower() or nil
    local recipeId = r.id

    -- confirmed: orders linking artisan contact to this recipe, or artisan meta.services
    orders = orders or {}
    local confirmedIds = {}
    for i = 1, #orders do
        local o = orders[i]
        if o.recipeId == recipeId and o.targetContact then
            confirmedIds[o.targetContact] = o.note or 'Commande liée'
        end
    end

    for i = 1, #artisans do
        local a = artisans[i]
        local id = a.contactId or a.id
        local name = a.displayName or a.name or id
        local specialty = a.specialty
        local meta = a.meta or {}
        -- explicit service/knowledge link only
        local serviceLabel = nil
        if confirmedIds[id] then
            serviceLabel = confirmedIds[id]
        elseif type(meta.services) == 'table' then
            for _, svc in ipairs(meta.services) do
                if type(svc) == 'table' and (svc.recipeId == recipeId or svc.recipe == recipeId) then
                    serviceLabel = svc.label or svc.serviceLabel or 'Service lié'
                    break
                elseif svc == recipeId then
                    serviceLabel = 'Service lié'
                    break
                end
            end
        elseif meta.recipeId == recipeId or meta.knownRecipe == recipeId then
            serviceLabel = meta.serviceLabel or 'Connaissance notée'
        end
        if serviceLabel then
            confirmed[#confirmed + 1] = {
                id = id, name = name, specialty = specialty, serviceLabel = serviceLabel,
            }
        elseif specL and specialty then
            local as = tostring(specialty):lower()
            if as == specL or specL:find(as, 1, true) or as:find(specL, 1, true) then
                potential[#potential + 1] = { id = id, name = name, specialty = specialty }
            end
        end
    end
    return { potential = potential, confirmed = confirmed }
end

local function buildRecipeEntry(src, r, ctx)

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
        local lab = itemLabelOf(ing.item, ing.labelOverride, ing.label)
        ingsOut[i] = { item = ing.item, count = ing.count or 1, owned = owned, label = lab }
    end

    local skillCategory = nil
    local playerSkillLevel = nil
    local hasSpecialization = nil
    local skillSnap = ctx and ctx.skillSnap
    local facing = nil
    if CraftingSkills and CraftingSkills.FacingSkill then
        facing = CraftingSkills.FacingSkill(src, r, skillSnap)
        skillCategory = facing.category
        playerSkillLevel = facing.playerSkillLevel
    elseif CraftingSkills and CraftingSkills.LevelCategoryForRecipe then
        skillCategory = CraftingSkills.LevelCategoryForRecipe(r)
        if skillSnap and skillSnap.categories and skillSnap.categories[skillCategory] then
            playerSkillLevel = skillSnap.categories[skillCategory].level
        end
    elseif r.xp and r.xp.category then
        skillCategory = r.xp.category
    end
    if playerSkillLevel == nil and lockReason == 'craft_level_required' and lockArgs and lockArgs[2] ~= nil then
        playerSkillLevel = lockArgs[2]
    end

    local requireSpec = nil
    local requireSpecLabel = nil
    if Specializations and Specializations.InferRequireSpec then
        requireSpec = Specializations.InferRequireSpec(r)
        if requireSpec then
            local c = Config.Specializations or {}
            if requireSpec == (c.SurvivalId or 'survie') then
                requireSpecLabel = c.SurvivalLabel or 'Survie'
            else
                local def = (c.Main or {})[requireSpec]
                requireSpecLabel = def and def.label or nil
            end
        end
        local okSpec = Specializations.CanCraftRecipe and select(1, Specializations.CanCraftRecipe(src, r))
        hasSpecialization = okSpec and true or false
        if not okSpec then
            canCraft, lockReason, lockArgs = false, 'craft_spec_required', { requireSpecLabel or requireSpec }
        end
    end

    local knownRecipe = true
    if Blueprints and Blueprints.KnowsRecipe then
        knownRecipe = Blueprints.KnowsRecipe(src, r) == true
        if not knownRecipe then
            local bpId = r.requireBlueprint or r.blueprintId
            canCraft = false
            lockReason = bpId and 'craft_blueprint_required' or 'craft_knowledge_required'
            lockArgs = { bpId or r.id }
        end
    end

    local teachable = false
    if Teaching and Teaching.IsTeachable then
        teachable = Teaching.IsTeachable(r) == true
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
                primaryMissing = { item = ing.item, owned = owned, count = need, label = ing.label or itemLabelOf(ing.item) }
            end
        end
    end

    local bench = ctx and ctx.bench
    if bench and Benches and Benches.MeetsStationLevel and not Benches.MeetsStationLevel(bench, r) then
        canCraft, lockReason, lockArgs = false, 'craft_station_level', { r.stationLevel, bench.stationLevel or 1 }
    end
    if StationRuntime and StationRuntime.CanRun and bench then
        local okRun, runReason = StationRuntime.CanRun(bench, r)
        if not okRun then
            canCraft, lockReason, lockArgs = false, runReason or 'craft_failed', nil
        end
    end
    if Tools and Tools.HasRecipe and not Tools.HasRecipe(src, r) then
        if canCraft then
            canCraft, lockReason, lockArgs = false, 'craft_tool_required', nil
        end
    end

    local toolDurability = nil
    local toolItem = nil
    if r.tools and type(r.tools) == 'table' and r.tools[1] then
        local t0 = r.tools[1]
        toolItem = type(t0) == 'string' and t0 or t0.item
    elseif r.requireTool then
        toolItem = type(r.requireTool) == 'string' and r.requireTool or r.requireTool.item
    end
    if Config.Tools and Config.Tools.Enabled and toolItem then
        if Tools and Tools.Durability then
            toolDurability = Tools.Durability(src, toolItem)
        end
    end

    local levelGap = nil
    if lockReason == 'craft_level_required' then
        local need = (lockArgs and lockArgs[1]) or (r.skillTree and r.skillTree.requiredLevel) or r.requireLevel
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

    local bpId = r.requireBlueprint or r.blueprintId
    local hasBp = true
    if bpId and Config.Blueprints and Config.Blueprints.Enabled and Blueprints then
        hasBp = Blueprints.Has(src, bpId) == true
    elseif not bpId then
        hasBp = true
    end

    local threshold = (Config.Mastery and (Config.Mastery.MasteredThreshold or Config.Mastery.MaxMastery)) or 100
    local mastered = (Config.Mastery and Config.Mastery.Enabled and mastery >= threshold) or false
    local knowledge, knowledgeSource = resolveKnowledge(src, r, mastery, hasBp, lockReason)
    local bpMeta = blueprintMetaOf(r)

    local resultOut = r.result
    if type(resultOut) == 'table' and resultOut.item then
        resultOut = {
            item = resultOut.item,
            count = resultOut.count or 1,
            label = itemLabelOf(resultOut.item, r.labelOverride or resultOut.labelOverride, resultOut.label),
            description = recipeFacingDesc(r),
        }
    end

    local entry = {
        id = r.id, label = recipeFacingLabel(r), category = r.category, tags = tags,
        description = recipeFacingDesc(r),
        ingredients = ingsOut,
        result = resultOut, duration = r.duration,
        xp = r.xp, requireLevel = r.requireLevel, requireSkill = r.requireSkill,
        skillTree = r.skillTree,
        skillCategoryLabel = facing and facing.categoryLabel or (SkillTree and SkillTree.CategoryLabel and SkillTree.CategoryLabel(skillCategory)) or nil,
        requiredSkillLabel = facing and facing.requiredSkillLabel or nil,
        hasRequiredSkill = facing and facing.hasRequiredSkill,
        requireSpecLabel = requireSpecLabel,
        playerSkillXp = facing and facing.playerSkillXp or nil,
        playerTotalXp = facing and facing.playerTotalXp or nil,
        requireBlueprint = bpId,
        requireTool = r.requireTool, tools = (function()
            local srcTools = r.tools
            if type(srcTools) ~= 'table' then
                if type(r.requireTool) == 'string' then
                    return { { item = r.requireTool, count = 1, label = itemLabelOf(r.requireTool) } }
                end
                return srcTools
            end
            local outT = {}
            for i = 1, #srcTools do
                local t = srcTools[i]
                if type(t) == 'string' then
                    outT[i] = { item = t, count = 1, label = itemLabelOf(t) }
                elseif type(t) == 'table' then
                    outT[i] = {
                        item = t.item, count = t.count or 1,
                        label = itemLabelOf(t.item, t.labelOverride, t.label),
                    }
                end
            end
            return outT
        end)(), station = r.station, rarity = r.rarity,
        hideIfSkillLocked = r.hideIfSkillLocked, quality = r.quality, byproducts = r.byproducts,
        queueable = r.queueable, batchMax = r.batchMax or r.maxQuantity, maxQuantity = r.maxQuantity or r.batchMax,
        dismantle = r.dismantle,
        stationLevel = r.stationLevel, powerCost = r.powerCost, noiseLevel = r.noiseLevel,
        heat = r.heat, needsVentilation = r.needsVentilation, smoke = r.smoke,
        signatureMode = (CraftSignature and CraftSignature.Mode and CraftSignature.Mode(r)) or r.signatureMode,
        trackCrafter = r.trackCrafter, trackLot = r.trackLot,
        steps = stepsOut, chain = r.chain,
        canCraft = canCraft and hasItems, locked = not canCraft,
        missingItems = not hasItems, lockReason = lockReason, lockArgs = lockArgs,
        mastery = mastery,
        mastered = mastered,
        knowledge = knowledge,
        knowledgeSource = knowledgeSource,
        blueprintId = bpId,
        blueprintMeta = bpMeta,
        skillCategory = skillCategory,
        playerSkillLevel = playerSkillLevel,
        hasSpecialization = hasSpecialization,
        requireSpec = requireSpec,
        teachable = teachable,
        known = knownRecipe,
        teacherKnows = knownRecipe,
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

    local artisans = ctx and ctx.artisans or nil
    local includeHeavy = not ctx or ctx.includeHints ~= false
    if includeHeavy then
        local pathHints, moreAvailable = buildPathHints(src, r, entry, artisans)
        entry.pathHints = pathHints
        entry.pathHintsMore = moreAvailable and true or false
        entry.artisanHints = buildArtisanHints(src, r, artisans, ctx and ctx.orders)
    end

    return entry
end

function CraftingPipeline.BuildRecipeEntry(src, r, ctx)
    return buildRecipeEntry(src, r, ctx)
end

--- Public helper for NUI pathHints callback
function CraftingPipeline.BuildPathHints(src, recipeId)
    local r = Config.RecipeById and Config.RecipeById[recipeId]
    if not r then return nil, 'craft_invalid' end
    local artisans = {}
    if SurvivalBook and SurvivalBook.ListArtisans and BookDB and BookDB.Mod and BookDB.Mod('Artisans') then
        artisans = SurvivalBook.ListArtisans(src) or {}
    end
    local orders = {}
    if SurvivalBook and SurvivalBook.ListOrders and BookDB and BookDB.Mod and BookDB.Mod('Orders') then
        orders = SurvivalBook.ListOrders(src) or {}
    end
    local entry = buildRecipeEntry(src, r, { artisans = artisans, orders = orders, includeHints = true })
    return {
        ok = true,
        recipeId = recipeId,
        pathHints = entry.pathHints or {},
        moreAvailable = entry.pathHintsMore == true,
        artisanHints = entry.artisanHints or { potential = {}, confirmed = {} },
        knowledge = entry.knowledge,
        knowledgeSource = entry.knowledgeSource,
        mastered = entry.mastered,
        mastery = entry.mastery,
        blueprintMeta = entry.blueprintMeta,
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
    local artisans = {}
    if SurvivalBook and SurvivalBook.ListArtisans and BookDB and BookDB.Mod and BookDB.Mod('Artisans') then
        artisans = SurvivalBook.ListArtisans(src) or {}
    end
    local orders = {}
    if SurvivalBook and SurvivalBook.ListOrders and BookDB and BookDB.Mod and BookDB.Mod('Orders') then
        orders = SurvivalBook.ListOrders(src) or {}
    end
    local skillSnap = (CraftingSkills and CraftingSkills.Snapshot and CraftingSkills.Snapshot(src)) or nil
    local ctx = { artisans = artisans, orders = orders, includeHints = true, bench = bench, skillSnap = skillSnap }
    local out = {}
    for i = 1, #recipes do
        out[#out + 1] = buildRecipeEntry(src, recipes[i], ctx)
    end

    local favorites = {}
    if Favorites then favorites = Favorites.Get(src) end

    local unreadSet = {}
    if NewlyLearned and NewlyLearned.List then
        for _, row in ipairs(NewlyLearned.List(src) or {}) do
            unreadSet[row.recipeId or row] = row.source or true
        end
    end
    for i = 1, #out do
        local e = out[i]
        if unreadSet[e.id] then
            e.unread = true
            e.unreadSource = unreadSet[e.id]
            e.isNew = true
            e.newlyUnlocked = true
        end
    end

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

    local session = CraftingPipeline.GetSession(src, benchKey)

    local snap = (StationRuntime and StationRuntime.Snapshot and StationRuntime.Snapshot(bench, src)) or {}
    local realEff = snap.efficiency
    local modsArr = snap.modules or bench.modules or {}
    if type(modsArr) ~= 'table' then modsArr = {} end

    return {
        ok = true, benchKey = benchKey, category = bench.category,
        label = bench.label or _(Config.BenchLabels[bench.category] or 'bench_scrap'),
        stationLevel = snap.level or benchLevel, modules = modsArr,
        powered = snap.powered,
        condition = snap.condition, temp = snap.temp, ventilation = snap.ventilation,
        efficiency = realEff, energy = snap.powered and 'OK' or 'Off',
        queue = snap.queue, queueSize = snap.queueSize,
        brokenParts = snap.brokenParts, moduleCatalog = snap.moduleCatalog,
        canUpgrade = snap.canUpgrade, canModule = snap.canModule,
        heatEnabled = snap.heatEnabled, conditionEnabled = snap.conditionEnabled,
        overheat = snap.overheat, stationKind = snap.kind,
        maxLevel = snap.maxLevel,
        recipes = out, favorites = favorites, pinned = pinned,
        playerSpec = (Specializations and Specializations.Resolve and Specializations.Resolve(src)) or nil,
        skillSnapshot = skillSnap and {
            available = skillSnap.available == true,
            categories = (function()
                local o = {}
                for k, c in pairs(skillSnap.categories or {}) do
                    o[k] = { key = k, label = c.label, level = c.level, xp = c.xp, totalXp = c.totalXp }
                end
                return o
            end)(),
            talents = (function()
                local talents = {}
                for i = 1, #(skillSnap.unlocked or {}) do
                    local u = skillSnap.unlocked[i]
                    if u and type(u.label) == 'string' and u.label ~= '' then
                        talents[#talents + 1] = { label = u.label, category = u.categoryKey }
                    end
                end
                return talents
            end)(),
        } or nil,
        recentlyCrafted = (RecentlyCrafted and RecentlyCrafted.List and RecentlyCrafted.List(src)) or {},
        newlyLearned = (NewlyLearned and NewlyLearned.Ids and NewlyLearned.Ids(src)) or {},
        shoppingPins = (ShoppingList and ShoppingList.BuildFromPins and select(1, ShoppingList.BuildFromPins(src))) or nil,
        teaching = Config.Teaching,
        itemLabels = (OxItemCatalog and OxItemCatalog.UsedLabels and OxItemCatalog.UsedLabels()) or {},
        session = session,
        ui = Config.UI, ux = ux,
        compare = {
            enabled = compareCfg.Enabled == true,
            map = compareCfg.Map or {},
        },
        queueMax = snap.queueSize or ((Config.Queue and Config.Queue.MaxQueuePerPlayer) or 5),
        batch = {
            enabled = Config.Batch and Config.Batch.Enabled,
            maxBatch = (CraftBatch and CraftBatch.ConfiguredMax and CraftBatch.ConfiguredMax()) or (Config.Batch and Config.Batch.MaxBatch) or 50,
            hardCap = (CraftBatch and CraftBatch.HardCap and CraftBatch.HardCap()) or 100,
            presets = (Config.Batch and Config.Batch.Presets) or { 1, 5, 10, 'max' },
        },
        flags = {
            quality = Config.Quality and Config.Quality.Enabled,
            blueprints = Config.Blueprints and Config.Blueprints.Enabled,
            queue = Config.Queue and Config.Queue.Enabled,
            batch = Config.Batch and Config.Batch.Enabled,
            mastery = Config.Mastery and Config.Mastery.Enabled,
            shopping = Config.ShoppingList and Config.ShoppingList.Enabled,
            craftTracker = Config.CraftTracker and Config.CraftTracker.Enabled ~= false,
            almostCraftable = ux.AlmostCraftable ~= false,
            badgeTooltips = ux.BadgeTooltips ~= false,
            nouveauIndicator = ux.NouveauIndicator ~= false,
            selectionTransition = ux.SelectionTransition ~= false,
            masteryDots = ux.MasteryDots ~= false,
            pinFollow = ux.PinFollow ~= false,
            fabReadyConsole = ux.FabReadyConsole ~= false,
            microToasts = ux.MicroToasts ~= false,
            smartSearch = ux.SmartSearch ~= false,
            masteredBadge = ux.MasteredBadge ~= false,
            knowledgeMarks = ux.KnowledgeMarks ~= false,
            pathHints = ux.PathHints ~= false,
            artisanHints = ux.ArtisanHints ~= false,
            knowledge = Config.Knowledge and Config.Knowledge.Enabled ~= false,
            compare = compareCfg.Enabled == true,
        },
        knowledge = Config.Knowledge,
        masteryCfg = Config.Mastery and {
            enabled = Config.Mastery.Enabled,
            max = Config.Mastery.MaxMastery,
            threshold = Config.Mastery.MasteredThreshold or Config.Mastery.MaxMastery,
        } or nil,
    }
end)

lib.callback.register('sanctuary_crafting:pathHints', function(src, recipeId)
    if type(recipeId) ~= 'string' then return { ok = false, reason = 'craft_invalid' } end
    local data, err = CraftingPipeline.BuildPathHints(src, recipeId)
    if not data then return { ok = false, reason = err or 'craft_invalid' } end
    return data
end)
