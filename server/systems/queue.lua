--[[
    queue/queue.lua — file d'attente + craft offline (timestamps)
]]

CraftQueue = CraftQueue or {}

local queues = {} -- [src] = { {craftId, recipeId, benchKey, finishAt, batch, ingredients, removed} }

function CraftQueue.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_craft_queue` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(60) NOT NULL,
            `craft_id` VARCHAR(64) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `bench_key` VARCHAR(64) NOT NULL,
            `batch` INT NOT NULL DEFAULT 1,
            `ingredients` LONGTEXT NOT NULL,
            `finish_at` INT NOT NULL,
            `created_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_ident` (`identifier`),
            UNIQUE KEY `uniq_craft` (`craft_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

function CraftQueue.List(src)
    return queues[src] or {}
end

function CraftQueue.Enqueue(src, recipeId, benchKey, batch)
    if not Config.Queue or not Config.Queue.Enabled then
        return nil, 'queue_disabled'
    end
    queues[src] = queues[src] or {}
    local maxQ = Config.Queue.MaxQueuePerPlayer or 5
    if #queues[src] >= maxQ then return nil, 'queue_full' end

    -- reuse start validation via callback internals: call startCraft path manually
    local start = lib.callback.await and nil -- server-side: invoke logic
    -- Direct: trigger same as start but mark queued
    local result = { ok = false }

    -- Inline minimal enqueue using pipeline start callback pattern
    local cbResult = nil
    -- We register a server function instead:
    return CraftQueue._startQueued(src, recipeId, benchKey, batch)
end

function CraftQueue._startQueued(src, recipeId, benchKey, batch)
    -- Use startCraft callback body by triggering export-style
    -- Simpler: duplicate light validation via event from client using startCraft then move to queue
    -- Actually client should call sanctuary_crafting:queueCraft
    batch = math.floor(tonumber(batch) or 1)
    local recipe = Config.RecipeById[recipeId]
    local bench = Benches.Resolve(benchKey)
    if not recipe or not bench then return nil, 'craft_invalid' end
    if not recipe.queueable and not (Config.Queue.AllowAll) then
        -- allow if queueable flag or AllowAll
        if recipe.queueable ~= true then
            -- still allow queue for long crafts
            if (recipe.duration or 0) < 30000 then
                return nil, 'queue_not_allowed'
            end
        end
    end

    local okSkill, reason, args = CraftingSkills.CheckRecipeGates(src, recipe)
    if not okSkill then return nil, reason, args end
    if CraftingSkills.NotifyBypassIfNeeded then
        CraftingSkills.NotifyBypassIfNeeded(src)
    end
    if Specializations and Specializations.CanUseStation then
        local okSt, stReason, stArgs = Specializations.CanUseStation(src, bench.category)
        if not okSt then return nil, stReason, stArgs end
    end
    if Specializations and Specializations.CanCraftRecipe then
        local okSp, spReason, spArgs = Specializations.CanCraftRecipe(src, recipe)
        if not okSp then return nil, spReason, spArgs end
    end
    if Blueprints and Blueprints.KnowsRecipe and not Blueprints.KnowsRecipe(src, recipe) then
        local bpId = recipe.requireBlueprint or recipe.blueprintId
        if bpId then return nil, 'craft_blueprint_required', { bpId } end
        return nil, 'craft_knowledge_required', { recipe.id }
    end
    if recipe.requireBlueprint or recipe.blueprintId then
        local bpId = recipe.requireBlueprint or recipe.blueprintId
        if Config.Blueprints and Config.Blueprints.Enabled and Blueprints and not Blueprints.Has(src, bpId) then
            return nil, 'craft_blueprint_required', { bpId }
        end
    end
    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return nil, 'craft_too_far'
    end

    batch = math.max(1, batch)
    local ingredients = {}
    for i = 1, #recipe.ingredients do
        ingredients[i] = { item = recipe.ingredients[i].item, count = (recipe.ingredients[i].count or 1) * batch }
    end
    if not Validation.HasIngredients(src, ingredients) then return nil, 'craft_no_ingredients' end

    for i = 1, #ingredients do
        if not exports.ox_inventory:RemoveItem(src, ingredients[i].item, ingredients[i].count) then
            for j = 1, i - 1 do
                exports.ox_inventory:AddItem(src, ingredients[j].item, ingredients[j].count)
            end
            return nil, 'craft_no_ingredients'
        end
    end

    local duration = CraftingSkills.ApplyCraftTimeBonus(recipe.duration or 5000, src)
    if batch > 1 then duration = math.floor(duration * batch * 0.85) end
    local craftId = GenerateCraftId()
    local finishAt = os.time() + math.ceil(duration / 1000)
    local entry = {
        craftId = craftId, recipeId = recipeId, benchKey = benchKey,
        batch = batch, ingredients = ingredients, finishAt = finishAt,
        createdAt = os.time(), duration = duration, label = (OxItemCatalog and OxItemCatalog.RecipeLabel and OxItemCatalog.RecipeLabel(recipe)) or recipe.label,
    }
    queues[src] = queues[src] or {}
    queues[src][#queues[src] + 1] = entry

    local id = ident(src)
    if id and Config.Queue.OfflineProgress then
        MySQL.insert.await(
            'INSERT INTO sanctuary_craft_queue (identifier, craft_id, recipe_id, bench_key, batch, ingredients, finish_at, created_at) VALUES (?,?,?,?,?,?,?,?)',
            { id, craftId, recipeId, benchKey, batch, json.encode(ingredients), finishAt, os.time() }
        )
    end

    CraftingCore.Emit('craftQueued', src, entry)
    return entry
end

function CraftQueue.TryCollect(src, craftId)
    local list = queues[src] or {}
    for i = 1, #list do
        local e = list[i]
        if e.craftId == craftId then
            if os.time() < e.finishAt then
                return false, 'queue_not_ready', e.finishAt - os.time()
            end
            local recipe = Config.RecipeById[e.recipeId]
            if not recipe then
                table.remove(list, i)
                return false, 'craft_invalid'
            end
            local count = (recipe.result.count or 1) * (e.batch or 1)
            local meta = { craftUID = e.craftId, craftedBy = ident(src), queued = true }
            if not Validation.CanCarry(src, recipe.result.item, count) then
                return false, 'craft_inventory_full'
            end
            exports.ox_inventory:AddItem(src, recipe.result.item, count, meta)
            if recipe.xp and recipe.xp.category then
                CraftingSkills.AddXP(recipe.xp.category, (recipe.xp.amount or 0) * (e.batch or 1), src)
                if NewlyLearned and NewlyLearned.ScanLevelUnlocks then
                    NewlyLearned.ScanLevelUnlocks(src)
                end
            end
            table.remove(list, i)
            local id = ident(src)
            if id then
                MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
            end
            CraftingCore.Emit('queueCollected', src, e)
            return true, recipe
        end
    end
    return false, 'craft_invalid'
end

function CraftQueue.Cancel(src, craftId)
    local list = queues[src] or {}
    for i = 1, #list do
        if list[i].craftId == craftId then
            local e = list[i]
            if Config.Crafting and Config.Crafting.RefundOnCancel then
                for _, ing in ipairs(e.ingredients or {}) do
                    exports.ox_inventory:AddItem(src, ing.item, ing.count)
                end
            end
            table.remove(list, i)
            MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
            return true
        end
    end
    return false
end

function CraftQueue.LoadOffline(src)
    if not Config.Queue or not Config.Queue.Enabled or not Config.Queue.OfflineProgress then return end
    local id = ident(src)
    if not id then return end
    local rows = MySQL.query.await('SELECT * FROM sanctuary_craft_queue WHERE identifier = ?', { id }) or {}
    queues[src] = queues[src] or {}
    for i = 1, #rows do
        local r = rows[i]
        queues[src][#queues[src] + 1] = {
            craftId = r.craft_id, recipeId = r.recipe_id, benchKey = r.bench_key,
            batch = r.batch, ingredients = json.decode(r.ingredients) or {},
            finishAt = r.finish_at, createdAt = r.created_at,
        }
    end
end

CreateThread(function()
    MySQL.ready.await()
    CraftQueue.EnsureTable()
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    CraftQueue.LoadOffline(playerId)
end)

lib.callback.register('sanctuary_crafting:queueCraft', function(src, recipeId, benchKey, batch)
    local entry, reason, args = CraftQueue._startQueued(src, recipeId, benchKey, batch)
    if not entry then return { ok = false, reason = reason, args = args } end
    return { ok = true, entry = entry }
end)

lib.callback.register('sanctuary_crafting:queueList', function(src)
    return { ok = true, queue = CraftQueue.List(src) }
end)

lib.callback.register('sanctuary_crafting:queueCollect', function(src, craftId)
    local ok, extra = CraftQueue.TryCollect(src, craftId)
    if not ok then return { ok = false, reason = extra } end
    return { ok = true, label = extra.label }
end)

lib.callback.register('sanctuary_crafting:queueCancel', function(src, craftId)
    return { ok = CraftQueue.Cancel(src, craftId) }
end)
