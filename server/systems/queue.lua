--[[
    queue/queue.lua — file d'attente + craft offline (timestamps)
    v2.15: validateStart, clamp batch, LoadOffline dedup, no refund after finishAt,
    collect+cancel mutex, bench.queueSize cap, quality+signature on collect, tools Has+wear.
]]

CraftQueue = CraftQueue or {}

local queues = {} -- [src] = { entries }
local busy = {} -- [craftId] = true  collect/cancel mutex

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

function CraftQueue.CountForBench(src, benchKey)
    local list = queues[src] or {}
    if not benchKey then return #list end
    local n = 0
    for i = 1, #list do
        if list[i].benchKey == benchKey then n = n + 1 end
    end
    return n
end

function CraftQueue.Enqueue(src, recipeId, benchKey, batch)
    if not Config.Queue or not Config.Queue.Enabled then
        return nil, 'queue_disabled'
    end
    return CraftQueue._startQueued(src, recipeId, benchKey, batch)
end

function CraftQueue._startQueued(src, recipeId, benchKey, batch)
    if not Config.Queue or not Config.Queue.Enabled then
        return nil, 'queue_disabled'
    end
    queues[src] = queues[src] or {}

    -- Same clamp helper as interactive
    local recipePre = Config.RecipeById and Config.RecipeById[recipeId]
    local benchPre = Benches and Benches.Resolve and Benches.Resolve(benchKey)
    if CraftBatch and CraftBatch.Clamp then
        local clamped, lim = CraftBatch.Clamp(src, recipePre, benchPre, batch, { queued = true })
        if clamped < 1 then
            if lim and lim.queue == 0 then return nil, 'queue_full' end
            return nil, 'craft_no_ingredients'
        end
        batch = clamped
    else
        batch = math.max(1, math.floor(tonumber(batch) or 1))
    end

    -- Through validateStart (queued: skip concurrent interactive, Has tools only)
    if not CraftingPipeline or not CraftingPipeline.ValidateStart then
        return nil, 'craft_invalid'
    end
    local ctx, reason, args = CraftingPipeline.ValidateStart(src, recipeId, benchKey, batch, { queued = true })
    if not ctx then return nil, reason, args end

    local recipe, bench = ctx.recipe, ctx.bench
    if not recipe.queueable and not (Config.Queue.AllowAll) then
        if recipe.queueable ~= true then
            if (recipe.duration or 0) < 30000 then
                return nil, 'queue_not_allowed'
            end
        end
    end

    -- bench.queueSize cap (+ module bonus)
    local cap = (Benches.CountQueueCap and Benches.CountQueueCap(bench)) or (Config.Queue.MaxQueuePerPlayer or 5)
    local playerMax = Config.Queue.MaxQueuePerPlayer or 5
    if CraftQueue.CountForBench(src, bench.key) >= cap then return nil, 'queue_full' end
    if #queues[src] >= playerMax then return nil, 'queue_full' end

    if CraftingSkills.NotifyBypassIfNeeded then
        CraftingSkills.NotifyBypassIfNeeded(src)
    end

    local taken = CraftingMaterials.Take(src, ctx.ingredients)
    if not taken then return nil, 'craft_no_ingredients' end

    local duration = CraftingSkills.ApplyCraftTimeBonus(recipe.duration or 5000, src)
    if StationRuntime and StationRuntime.ApplyDuration then
        duration = StationRuntime.ApplyDuration(duration, bench)
    end
    if ctx.batch > 1 then duration = math.floor(duration * ctx.batch * 0.85) end
    local craftId = GenerateCraftId()
    local finishAt = os.time() + math.ceil(duration / 1000)
    local entry = {
        craftId = craftId, recipeId = recipe.id, benchKey = bench.key,
        batch = ctx.batch, ingredients = ctx.ingredients, finishAt = finishAt,
        createdAt = os.time(), duration = duration,
        label = (OxItemCatalog and OxItemCatalog.RecipeLabel and OxItemCatalog.RecipeLabel(recipe)) or recipe.label,
        reserved = CraftingMaterials.ReserveOnQueue() == true,
    }
    queues[src][#queues[src] + 1] = entry

    local id = ident(src)
    if id and Config.Queue.OfflineProgress then
        MySQL.insert.await(
            'INSERT INTO sanctuary_craft_queue (identifier, craft_id, recipe_id, bench_key, batch, ingredients, finish_at, created_at) VALUES (?,?,?,?,?,?,?,?)',
            { id, craftId, recipe.id, bench.key, ctx.batch, json.encode(ctx.ingredients), finishAt, os.time() }
        )
    end

    CraftingCore.Emit('craftQueued', src, entry)
    return entry
end

function CraftQueue.TryCollect(src, craftId)
    if type(craftId) ~= 'string' then return false, 'craft_invalid' end
    if busy[craftId] then return false, 'craft_busy' end
    busy[craftId] = true
    local okRun, a, b, c = pcall(function()
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
                    MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
                    return false, 'craft_invalid'
                end
                local bench = Benches and Benches.Resolve and Benches.Resolve(e.benchKey)
                local count = CraftBatch.SafeMul(recipe.result.count or 1, e.batch or 1)
                if not Validation.CanCarry(src, recipe.result.item, count) then
                    return false, 'craft_inventory_full'
                end
                -- identity still required at collect (v2.14)
                if CraftingPipeline and CraftingPipeline.CheckIdentityGates then
                    local okI, rI, aI = CraftingPipeline.CheckIdentityGates(src, recipe, bench)
                    if not okI then return false, rI, aI end
                end
                local quality = nil
                if CraftingPipeline and CraftingPipeline.RollQuality then
                    quality = CraftingPipeline.RollQuality(src, recipe, bench)
                end
                local okGive
                if CraftSignature and CraftSignature.GiveResult then
                    okGive = CraftSignature.GiveResult(src, recipe, bench, quality, e.craftId, count)
                else
                    local meta = { craftedBy = ident(src), queued = true }
                    if quality then meta.quality = quality end
                    okGive = exports.ox_inventory:AddItem(src, recipe.result.item, count, meta)
                end
                if not okGive then
                    return false, 'craft_inventory_full'
                end
                if Tools and Tools.WearRecipe then
                    Tools.WearRecipe(src, recipe, e.batch or 1)
                end
                if recipe.xp and recipe.xp.category then
                    CraftingSkills.AddXP(recipe.xp.category, (recipe.xp.amount or 0) * (e.batch or 1), src)
                    if NewlyLearned and NewlyLearned.ScanLevelUnlocks then
                        NewlyLearned.ScanLevelUnlocks(src)
                    end
                end
                if Config.Mastery and Config.Mastery.Enabled and Mastery then
                    Mastery.Add(src, recipe.id, (Config.Mastery.XpPerCraft or 1) * (e.batch or 1))
                end
                if StationRuntime and StationRuntime.Degrade then
                    StationRuntime.Degrade(bench, recipe, e.batch or 1)
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
    end)
    busy[craftId] = nil
    if not okRun then
        print(('[sanctuary_crafting] queue collect error: %s'):format(tostring(a)))
        return false, 'craft_failed'
    end
    return a, b, c
end

function CraftQueue.Cancel(src, craftId)
    if type(craftId) ~= 'string' then return false, 'craft_invalid' end
    if busy[craftId] then return false, 'craft_busy' end
    busy[craftId] = true
    local okRun, a, b = pcall(function()
        local list = queues[src] or {}
        for i = 1, #list do
            if list[i].craftId == craftId then
                local e = list[i]
                -- no refund after finishAt (race with collect)
                if CraftingMaterials.ShouldRefundQueue(e) then
                    CraftingMaterials.Give(src, e.ingredients or {})
                end
                table.remove(list, i)
                MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
                CraftingCore.Emit('queueCancelled', src, e)
                return true
            end
        end
        return false, 'craft_invalid'
    end)
    busy[craftId] = nil
    if not okRun then
        print(('[sanctuary_crafting] queue cancel error: %s'):format(tostring(a)))
        return false
    end
    return a, b
end

function CraftQueue.LoadOffline(src)
    if not Config.Queue or not Config.Queue.Enabled or not Config.Queue.OfflineProgress then return end
    local id = ident(src)
    if not id then return end
    local rows = MySQL.query.await('SELECT * FROM sanctuary_craft_queue WHERE identifier = ?', { id }) or {}
    -- clear + dedup by craft_id
    queues[src] = {}
    local seen = {}
    for i = 1, #rows do
        local r = rows[i]
        local cid = r.craft_id
        if cid and not seen[cid] then
            seen[cid] = true
            queues[src][#queues[src] + 1] = {
                craftId = cid, recipeId = r.recipe_id, benchKey = r.bench_key,
                batch = r.batch, ingredients = json.decode(r.ingredients) or {},
                finishAt = r.finish_at, createdAt = r.created_at,
            }
        else
            -- drop duplicate row
            if cid then
                MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE id = ?', { r.id })
            end
        end
    end
end

CreateThread(function()
    MySQL.ready.await()
    CraftQueue.EnsureTable()
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    CraftQueue.LoadOffline(playerId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    queues[src] = nil
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
    local ok, extra, extra2 = CraftQueue.TryCollect(src, craftId)
    if not ok then return { ok = false, reason = extra, wait = extra2 } end
    return { ok = true, label = extra.label }
end)

lib.callback.register('sanctuary_crafting:queueCancel', function(src, craftId)
    local ok, reason = CraftQueue.Cancel(src, craftId)
    return { ok = ok and true or false, reason = reason }
end)
