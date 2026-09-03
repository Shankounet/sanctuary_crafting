--[[
    queue/queue.lua — file de production FIFO par station (v2.24)
    Per stationUid: 1 processing + N queued (capacity). Completed → SORTIE (no slot).
    Materials consumed/reserved on enqueue. Auto-promote on finish / cancel processing.
    Reorder up/down: SKIP — FIFO only (created_at / queue_position).
]]

CraftQueue = CraftQueue or {}

local byStation = {} -- [stationUid] = { [craftId] = entry }
local byCraft = {}   -- [craftId] = entry
local byIdent = {}   -- [identifier] = { [craftId] = entry }
local srcIdent = {}  -- [src] = identifier
local busy = {}      -- [craftId] = true  collect/cancel mutex
local promoteLock = {} -- [stationUid] = true
local lastRequest = {} -- [src] = { id, at, result }

local REQ_TTL_MS = 4000

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
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `started_at` INT NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `queue_position` INT NOT NULL DEFAULT 0")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `duration_ms` INT NULL")
    end)
end

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

local function sourceFromIdent(identifier)
    if not identifier or identifier == '' then return nil end
    if ESX and ESX.GetPlayerFromIdentifier then
        local xP = ESX.GetPlayerFromIdentifier(identifier)
        if xP then return xP.source or xP.playerId end
    end
    return nil
end

local function ownerLabel(identifier, src)
    local cfg = Config.Queue or {}
    if cfg.ShowOwnerNames ~= true then return nil end
    local s = src or sourceFromIdent(identifier)
    if s and ESX and ESX.GetPlayerFromId then
        local xP = ESX.GetPlayerFromId(s)
        if xP then
            if xP.getName then return xP.getName() end
            if xP.name then return xP.name end
        end
    end
    return nil
end

local function qcfg()
    return Config.Queue or {}
end

function CraftQueue.DefaultCapacity()
    return tonumber(qcfg().MaxQueuePerStation) or 6
end

function CraftQueue.Capacity(bench)
    if Benches and Benches.CountQueueCap then
        return Benches.CountQueueCap(bench)
    end
    return CraftQueue.DefaultCapacity()
end
local function encodeJson(t)
    if t == nil then return '[]' end
    if type(t) == 'string' then return t end
    local ok, s = pcall(json.encode, t)
    if ok then return s end
    return '[]'
end

local function facingLabel(recipe, fallback)
    if recipe and OxItemCatalog and OxItemCatalog.RecipeLabel then
        local lab = OxItemCatalog.RecipeLabel(recipe)
        if type(lab) == 'string' and lab ~= '' then return lab end
    end
    if recipe and type(recipe.label) == 'string' and recipe.label ~= '' then
        return recipe.label
    end
    return fallback or (recipe and recipe.id) or 'objet'
end

local function put(entry)
    if not entry or not entry.craftId then return end
    local uid = entry.stationUid or entry.benchKey
    if not uid then return end
    entry.stationUid = uid
    byCraft[entry.craftId] = entry
    byStation[uid] = byStation[uid] or {}
    byStation[uid][entry.craftId] = entry
    if entry.identifier then
        byIdent[entry.identifier] = byIdent[entry.identifier] or {}
        byIdent[entry.identifier][entry.craftId] = entry
    end
end

local function drop(craftId)
    local e = byCraft[craftId]
    if not e then return end
    byCraft[craftId] = nil
    local uid = e.stationUid or e.benchKey
    if uid and byStation[uid] then
        byStation[uid][craftId] = nil
    end
    if e.identifier and byIdent[e.identifier] then
        byIdent[e.identifier][craftId] = nil
    end
end

function CraftQueue.Detach(craftId)
    if type(craftId) ~= 'string' then return end
    drop(craftId)
end

function CraftQueue.Get(craftId)
    return byCraft[craftId]
end

local SLOT_STATES = { queued = true, processing = true, paused = true, running = true }

local function isSlotState(st)
    return SLOT_STATES[st or ''] == true
end

function CraftQueue.CountActiveSlots(stationUid)
    if not stationUid then return 0 end
    local n = 0
    local map = byStation[stationUid]
    if map then
        for _, e in pairs(map) do
            if isSlotState(e.state) then n = n + 1 end
        end
    end
    if CraftingPipeline and CraftingPipeline.GetProcessingAt then
        local ram = CraftingPipeline.GetProcessingAt(stationUid)
        if ram and ram.craftId and not (map and map[ram.craftId]) then
            n = n + 1
        end
    end
    return n
end

function CraftQueue.CountForBench(src, benchKey)
    if benchKey then return CraftQueue.CountActiveSlots(benchKey) end
    local id = srcIdent[src] or ident(src)
    if not id or not byIdent[id] then return 0 end
    local n = 0
    for _, e in pairs(byIdent[id]) do
        if isSlotState(e.state) then n = n + 1 end
    end
    return n
end

function CraftQueue.GetProcessing(stationUid)
    if not stationUid then return nil end
    local map = byStation[stationUid]
    local best = nil
    if map then
        for _, e in pairs(map) do
            if e.state == 'processing' or e.state == 'paused' or e.state == 'running' then
                if not best then
                    best = e
                else
                    local a = tonumber(e.startedAt or e.createdAt) or 0
                    local b = tonumber(best.startedAt or best.createdAt) or 0
                    if a < b then best = e end
                end
            end
        end
    end
    if best then return best end
    if CraftingPipeline and CraftingPipeline.GetProcessingAt then
        return CraftingPipeline.GetProcessingAt(stationUid)
    end
    return nil
end

local function stationJobs(stationUid)
    local list = {}
    local map = byStation[stationUid]
    if not map then return list end
    for _, e in pairs(map) do
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        local pa = tonumber(a.queuePosition) or 0
        local pb = tonumber(b.queuePosition) or 0
        if pa ~= pb then return pa < pb end
        local ca = tonumber(a.createdAt) or 0
        local cb = tonumber(b.createdAt) or 0
        if ca ~= cb then return ca < cb end
        return tostring(a.craftId) < tostring(b.craftId)
    end)
    return list
end

function CraftQueue.Reorder(stationUid)
    local list = stationJobs(stationUid)
    local pos = 0
    for i = 1, #list do
        local e = list[i]
        if e.state == 'queued' then
            pos = pos + 1
            e.queuePosition = pos
            MySQL.update('UPDATE sanctuary_craft_queue SET queue_position = ? WHERE craft_id = ?', { pos, e.craftId })
        end
    end
end

function CraftQueue.NextQueuePosition(stationUid)
    local n = 0
    local map = byStation[stationUid]
    if not map then return 1 end
    for _, e in pairs(map) do
        if e.state == 'queued' then
            local p = tonumber(e.queuePosition) or 0
            if p > n then n = p end
        end
    end
    return n + 1
end
local function persistRow(entry)
    if not entry or not entry.craftId or not entry.identifier then return false end
    local snapJson = nil
    if entry.snapshot then
        if RecipeSnapshot and RecipeSnapshot.Encode then
            snapJson = RecipeSnapshot.Encode(entry.snapshot)
        else
            snapJson = encodeJson(entry.snapshot)
        end
    end
    local ok = pcall(function()
        MySQL.insert.await([[
            INSERT INTO sanctuary_craft_queue
                (identifier, craft_id, recipe_id, bench_key, batch, ingredients, finish_at, created_at,
                 recipe_snapshot, recipe_version, station_uid, state, started_at, queue_position, duration_ms)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE
                identifier = VALUES(identifier),
                recipe_id = VALUES(recipe_id),
                bench_key = VALUES(bench_key),
                batch = VALUES(batch),
                ingredients = VALUES(ingredients),
                finish_at = VALUES(finish_at),
                recipe_snapshot = VALUES(recipe_snapshot),
                recipe_version = VALUES(recipe_version),
                station_uid = VALUES(station_uid),
                state = VALUES(state),
                started_at = VALUES(started_at),
                queue_position = VALUES(queue_position),
                duration_ms = VALUES(duration_ms)
        ]], {
            entry.identifier,
            entry.craftId,
            entry.recipeId,
            entry.benchKey or entry.stationUid,
            entry.batch or 1,
            encodeJson(entry.ingredients) or '[]',
            tonumber(entry.finishAt) or 0,
            tonumber(entry.createdAt) or os.time(),
            snapJson,
            tonumber(entry.recipeVersion) or 0,
            entry.stationUid or entry.benchKey,
            entry.state or 'queued',
            tonumber(entry.startedAt),
            tonumber(entry.queuePosition) or 0,
            tonumber(entry.duration) or tonumber(entry.durationMs),
        })
    end)
    if not ok then
        pcall(function()
            MySQL.insert.await(
                'INSERT INTO sanctuary_craft_queue (identifier, craft_id, recipe_id, bench_key, batch, ingredients, finish_at, created_at) VALUES (?,?,?,?,?,?,?,?)',
                { entry.identifier, entry.craftId, entry.recipeId, entry.benchKey, entry.batch or 1, encodeJson(entry.ingredients) or '[]', tonumber(entry.finishAt) or 0, tonumber(entry.createdAt) or os.time() }
            )
        end)
    end
    return ok
end

function CraftQueue.Persist(entry)
    put(entry)
    return persistRow(entry)
end

local function computeDuration(src, recipe, bench, batch)
    local raw = (recipe and recipe.duration) or 5000
    local duration = raw
    if CraftingSkills and CraftingSkills.ApplyCraftTimeBonus then
        duration = CraftingSkills.ApplyCraftTimeBonus(raw, src)
    end
    if StationRuntime and StationRuntime.ApplyDuration then
        duration = StationRuntime.ApplyDuration(duration, bench)
    end
    batch = tonumber(batch) or 1
    if batch > 1 then
        duration = math.floor(duration * batch * 0.85)
    end
    return math.max(500, math.floor(tonumber(duration) or raw))
end

function CraftQueue.BuildEntry(src, ctx, stationUid, state)
    local recipe, bench = ctx.recipe, ctx.bench
    local id = ident(src)
    if not id then return nil, 'craft_invalid' end
    local snap, ver = nil, 0
    if RecipeSnapshot and RecipeSnapshot.Capture then
        snap, ver = RecipeSnapshot.Capture(recipe)
    else
        snap, ver = recipe, tonumber(recipe._version) or 0
    end
    local duration = computeDuration(src, recipe, bench, ctx.batch)
    local now = os.time()
    local processing = state == 'processing' or state == 'running'
    local finishAt = 0
    local startedAt = nil
    if processing then
        startedAt = now
        finishAt = now + math.ceil(duration / 1000)
    end
    local craftId = GenerateCraftId()
    local qpos = processing and 0 or CraftQueue.NextQueuePosition(stationUid)
    local entry = {
        craftId = craftId,
        identifier = id,
        recipeId = recipe.id,
        benchKey = bench.key,
        stationUid = stationUid,
        batch = ctx.batch,
        ingredients = ctx.ingredients,
        finishAt = finishAt,
        createdAt = now,
        startedAt = startedAt,
        duration = duration,
        durationMs = duration,
        label = facingLabel(recipe, recipe.id),
        reserved = CraftingMaterials and CraftingMaterials.ReserveOnQueue and CraftingMaterials.ReserveOnQueue() == true,
        snapshot = snap,
        recipeVersion = ver or 0,
        state = processing and 'processing' or 'queued',
        source = processing and 'interactive' or 'queue',
        queuePosition = qpos,
        ownerName = ownerLabel(id, src),
    }
    return entry
end

function CraftQueue.InsertQueued(src, ctx, stationUid)
    if not ctx or not ctx.recipe then return { ok = false, reason = 'craft_invalid' } end
    local taken = CraftingMaterials.Take(src, ctx.ingredients)
    if not taken then return { ok = false, reason = 'craft_no_ingredients' } end
    local entry, err = CraftQueue.BuildEntry(src, ctx, stationUid, 'queued')
    if not entry then
        CraftingMaterials.Give(src, ctx.ingredients)
        return { ok = false, reason = err or 'craft_failed' }
    end
    entry.removed = true
    CraftQueue.Persist(entry)
    srcIdent[src] = entry.identifier
    if CraftingCore and CraftingCore.Emit then
        CraftingCore.Emit('craftQueued', src, entry)
    end
    return {
        ok = true,
        queued = true,
        craftId = entry.craftId,
        queuePosition = entry.queuePosition,
        entry = entry,
        label = entry.label,
        batch = entry.batch,
        recipeId = entry.recipeId,
        benchKey = entry.benchKey,
        stationUid = entry.stationUid,
        duration = 0,
        resultItem = ctx.recipe.result and ctx.recipe.result.item,
        resultCount = ctx.recipe.result and ((ctx.recipe.result.count or 1) * (entry.batch or 1)),
        benchLabel = ctx.bench and ctx.bench.label,
        category = ctx.recipe.category or (ctx.bench and ctx.bench.category),
        state = 'queued',
    }
end

function CraftQueue.InsertProcessing(entry)
    if not entry then return end
    entry.state = entry.state or 'processing'
    if not entry.startedAt then entry.startedAt = os.time() end
    if not entry.finishAt or entry.finishAt <= 0 then
        local dur = tonumber(entry.duration) or 0
        entry.finishAt = os.time() + math.ceil(dur / 1000)
    end
    entry.queuePosition = 0
    CraftQueue.Persist(entry)
end

function CraftQueue.RememberRequest(src, requestId, result)
    if type(requestId) ~= 'string' or requestId == '' then return end
    lastRequest[src] = { id = requestId, at = GetGameTimer(), result = result }
end

function CraftQueue.ReplayRequest(src, requestId)
    if type(requestId) ~= 'string' or requestId == '' then return nil end
    local hit = lastRequest[src]
    if not hit then return nil end
    if hit.id ~= requestId then return nil end
    if (GetGameTimer() - (hit.at or 0)) > REQ_TTL_MS then return nil end
    return hit.result
end
local function notifyStation(stationUid, action, payload)
    payload = payload or {}
    payload.stationUid = stationUid
    payload.action = action
    local seen = {}
    local map = byStation[stationUid]
    if map then
        for _, e in pairs(map) do
            local s = sourceFromIdent(e.identifier)
            if s and not seen[s] then
                seen[s] = true
                TriggerClientEvent('sanctuary_crafting:client:queueUpdated', s, payload)
            end
        end
    end
    if Benches and Benches.Resolve then
        local bench = Benches.Resolve(stationUid)
        if bench and bench.coords and Validation and Validation.IsNearBench then
            for _, playerId in ipairs(GetPlayers()) do
                local s = tonumber(playerId)
                if s and not seen[s] and Validation.IsNearBench(s, bench.coords, (Config.InteractDistance or 2.5) + 2.0) then
                    seen[s] = true
                    TriggerClientEvent('sanctuary_crafting:client:queueUpdated', s, payload)
                end
            end
        end
    end
end

function CraftQueue.Serialize(entry, viewerSrc)
    if not entry then return nil end
    local st = entry.state or 'queued'
    if st == 'running' then st = 'processing' end
    local finishAt = tonumber(entry.finishAt) or 0
    local createdAt = tonumber(entry.createdAt) or finishAt
    local startedAt = tonumber(entry.startedAt) or (st == 'processing' and createdAt or nil)
    local durationMs = tonumber(entry.duration) or tonumber(entry.durationMs) or 0
    local remainingMs = 0
    if st == 'processing' or st == 'paused' then
        if entry.paused and entry.pausedRemaining then
            remainingMs = math.max(0, tonumber(entry.pausedRemaining) or 0) * 1000
        elseif finishAt > 0 then
            remainingMs = math.max(0, (finishAt - os.time()) * 1000)
        end
    end
    local mine = false
    if viewerSrc then
        local vid = srcIdent[viewerSrc] or ident(viewerSrc)
        mine = vid and entry.identifier == vid
    end
    local ownerName = nil
    if qcfg().ShowOwnerNames == true then
        ownerName = entry.ownerName or ownerLabel(entry.identifier, sourceFromIdent(entry.identifier))
    end
    return {
        craftId = entry.craftId,
        recipeId = entry.recipeId,
        benchKey = entry.benchKey,
        stationUid = entry.stationUid or entry.benchKey,
        batch = entry.batch or 1,
        quantity = entry.batch or 1,
        ingredients = entry.ingredients,
        finishAt = finishAt,
        finishesAt = finishAt,
        createdAt = createdAt,
        startedAt = startedAt,
        duration = durationMs,
        durationMs = durationMs,
        remainingMs = remainingMs,
        label = entry.label,
        state = st,
        paused = entry.paused == true or st == 'paused',
        queuePosition = tonumber(entry.queuePosition) or 0,
        mine = mine,
        ownerName = ownerName,
    }
end

function CraftQueue.ListForStation(stationUid, viewerSrc)
    local out = {}
    if not stationUid then return out end
    local showOthers = qcfg().ShowOtherJobs ~= false
    local vid = viewerSrc and (srcIdent[viewerSrc] or ident(viewerSrc)) or nil
    local list = stationJobs(stationUid)
    for i = 1, #list do
        local e = list[i]
        if isSlotState(e.state) then
            if showOthers or not vid or e.identifier == vid then
                out[#out + 1] = CraftQueue.Serialize(e, viewerSrc)
            end
        end
    end
    return out
end

function CraftQueue.List(src)
    local id = srcIdent[src] or ident(src)
    if id then srcIdent[src] = id end
    local out = {}
    if not id or not byIdent[id] then return out end
    for _, e in pairs(byIdent[id]) do
        if isSlotState(e.state) then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        local ca = tonumber(a.createdAt) or 0
        local cb = tonumber(b.createdAt) or 0
        return ca < cb
    end)
    return out
end

local function refundEntry(src, entry)
    if not entry then return end
    local target = src
    if (not target or target == 0) and entry.identifier then
        target = sourceFromIdent(entry.identifier)
    end
    if not target or target == 0 then return end
    if CraftingMaterials and CraftingMaterials.ShouldRefundQueue then
        if CraftingMaterials.ShouldRefundQueue(entry) then
            CraftingMaterials.Give(target, entry.ingredients or {})
        end
    elseif not Config.Crafting or Config.Crafting.RefundOnCancel ~= false then
        if CraftingMaterials and CraftingMaterials.Give then
            CraftingMaterials.Give(target, entry.ingredients or {})
        end
    end
end

function CraftQueue.PromoteNext(stationUid)
    if not stationUid or stationUid == '' then return nil end
    if promoteLock[stationUid] then return nil end
    promoteLock[stationUid] = true
    local okRun, result = pcall(function()
        if CraftQueue.GetProcessing(stationUid) then
            return nil
        end
        local nextJob = nil
        local list = stationJobs(stationUid)
        for i = 1, #list do
            if list[i].state == 'queued' then
                nextJob = list[i]
                break
            end
        end
        if not nextJob then return nil end
        local recipe = nextJob.snapshot
        if type(recipe) ~= 'table' and RecipeSnapshot and RecipeSnapshot.Of then
            recipe = RecipeSnapshot.Of(nextJob)
        end
        if type(recipe) ~= 'table' then
            recipe = Config.RecipeById and Config.RecipeById[nextJob.recipeId]
        end
        local bench = Benches and Benches.Resolve and Benches.Resolve(nextJob.benchKey or stationUid)
        local src = sourceFromIdent(nextJob.identifier)
        local duration = tonumber(nextJob.duration) or tonumber(nextJob.durationMs)
        if not duration or duration < 500 then
            duration = computeDuration(src, recipe, bench, nextJob.batch or 1)
        end
        local now = os.time()
        nextJob.state = 'processing'
        nextJob.startedAt = now
        nextJob.finishAt = now + math.ceil(duration / 1000)
        nextJob.duration = duration
        nextJob.durationMs = duration
        nextJob.queuePosition = 0
        nextJob.paused = false
        persistRow(nextJob)
        CraftQueue.Reorder(stationUid)
        if src and CraftingPipeline and CraftingPipeline.AdoptQueued then
            CraftingPipeline.AdoptQueued(src, nextJob, recipe, bench)
        end
        notifyStation(stationUid, 'queuePromoted', {
            craftId = nextJob.craftId,
            identifier = nextJob.identifier,
            label = nextJob.label,
            batch = nextJob.batch,
            finishAt = nextJob.finishAt,
            duration = duration,
        })
        return nextJob
    end)
    promoteLock[stationUid] = nil
    if not okRun then
        print(('[sanctuary_crafting] PromoteNext error station=%s: %s'):format(tostring(stationUid), tostring(result)))
        return nil
    end
    return result
end

function CraftQueue.OnProcessingGone(stationUid, craftId)
    if craftId then drop(craftId) end
    if stationUid then
        CraftQueue.PromoteNext(stationUid)
    end
end
function CraftQueue.TickPower()
    if not Config.Power or Config.Power.Enabled ~= true then return end
    if Config.Power.PauseOnLoss == false then return end
    if not CraftingPower or not CraftingPower.HasPower then return end
    for uid, map in pairs(byStation) do
        for _, e in pairs(map) do
            if e.state == 'processing' or e.state == 'paused' then
                local bench = Benches and Benches.Resolve and Benches.Resolve(e.benchKey or uid)
                local powered = CraftingPower.HasPower(bench) == true
                if not powered then
                    if not e.paused then
                        e.paused = true
                        e.pausedAt = os.time()
                        e.pausedRemaining = math.max(0, (tonumber(e.finishAt) or os.time()) - os.time())
                        e.state = 'paused'
                        MySQL.update('UPDATE sanctuary_craft_queue SET state = ?, finish_at = ? WHERE craft_id = ?', { 'paused', e.finishAt, e.craftId })
                    end
                elseif e.paused or e.state == 'paused' then
                    local rem = tonumber(e.pausedRemaining) or 0
                    e.finishAt = os.time() + rem
                    e.paused = false
                    e.pausedAt = nil
                    e.pausedRemaining = nil
                    e.state = 'processing'
                    MySQL.update('UPDATE sanctuary_craft_queue SET finish_at = ?, state = ? WHERE craft_id = ?', { e.finishAt, 'processing', e.craftId })
                end
            end
        end
    end
end

function CraftQueue.TryCollect(src, craftId, benchKey)
    if type(craftId) ~= 'string' then return false, 'craft_invalid' end
    if StationOutput and StationOutput.Enabled and StationOutput.Enabled() then
        return StationOutput.Collect(src, craftId, benchKey)
    end
    return CraftQueue.TryCollectLegacy(src, craftId)
end

function CraftQueue.TryCollectLegacy(src, craftId)
    if type(craftId) ~= 'string' then return false, 'craft_invalid' end
    if busy[craftId] then return false, 'craft_busy' end
    busy[craftId] = true
    local okRun, a, b, c = pcall(function()
        local e = byCraft[craftId]
        if not e then return false, 'craft_invalid' end
        local id = ident(src)
        if id and e.identifier ~= id then return false, 'craft_denied' end
        if e.paused then
            return false, 'queue_not_ready', e.pausedRemaining or 0
        end
        if os.time() < (tonumber(e.finishAt) or 0) then
            return false, 'queue_not_ready', (tonumber(e.finishAt) or 0) - os.time()
        end
        local recipe = e.snapshot
        if type(recipe) ~= 'table' and RecipeSnapshot and RecipeSnapshot.Of then
            recipe = RecipeSnapshot.Of(e)
        end
        if type(recipe) ~= 'table' then
            recipe = Config.RecipeById and Config.RecipeById[e.recipeId]
        end
        if not recipe then
            drop(craftId)
            MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
            return false, 'craft_invalid'
        end
        local bench = Benches and Benches.Resolve and Benches.Resolve(e.benchKey)
        local count = CraftBatch.SafeMul(recipe.result.count or 1, e.batch or 1)
        if not Validation.CanCarry(src, recipe.result.item, count) then
            return false, 'craft_inventory_full'
        end
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
        local uid = e.stationUid or e.benchKey
        drop(craftId)
        MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
        CraftQueue.PromoteNext(uid)
        return true, recipe
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
        local e = byCraft[craftId]
        if not e then
            if CraftingPipeline and CraftingPipeline.Cancel then
                return CraftingPipeline.Cancel(src, craftId, 'cancel')
            end
            return false, 'craft_invalid'
        end
        local id = ident(src)
        if id and e.identifier ~= id then
            if not (Validation and Validation.IsAdmin and Validation.IsAdmin(src)) then
                return false, 'craft_denied'
            end
        end
        local st = e.state
        if st == 'completed' or st == 'collected' then
            return false, 'craft_must_collect'
        end
        if StationOutput and StationOutput.IsCancelable and not StationOutput.IsCancelable(st) then
            return false, 'craft_must_collect'
        end
        if st == 'processing' or st == 'running' or st == 'paused' then
            if e.finishAt and tonumber(e.finishAt) > 0 and os.time() >= e.finishAt and StationOutput and StationOutput.Enabled and StationOutput.Enabled() then
                return false, 'craft_must_collect'
            end
            if CraftingPipeline and CraftingPipeline.Get and CraftingPipeline.Get(craftId) then
                busy[craftId] = nil
                local okP, rP = CraftingPipeline.Cancel(src, craftId, 'cancel')
                return okP, rP
            end
        end
        if st == 'queued' then
            if CraftingMaterials and CraftingMaterials.Give then
                CraftingMaterials.Give(src, e.ingredients or {})
            end
        else
            refundEntry(src, e)
        end
        local uid = e.stationUid or e.benchKey
        drop(craftId)
        MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
        if st == 'queued' then
            CraftQueue.Reorder(uid)
        else
            CraftQueue.PromoteNext(uid)
        end
        if CraftingCore and CraftingCore.Emit then
            CraftingCore.Emit('queueCancelled', src, e)
        end
        notifyStation(uid, 'queueUpdated', { craftId = craftId, cancelled = true })
        return true
    end)
    busy[craftId] = nil
    if not okRun then
        print(('[sanctuary_crafting] queue cancel error: %s'):format(tostring(a)))
        return false
    end
    return a, b
end
local function entryFromSql(r)
    if not r then return nil end
    local snap = nil
    if r.recipe_snapshot and RecipeSnapshot and RecipeSnapshot.Decode then
        snap = RecipeSnapshot.Decode(r.recipe_snapshot)
    elseif r.recipe_snapshot then
        local okd, dec = pcall(json.decode, r.recipe_snapshot)
        if okd and type(dec) == 'table' then snap = dec end
    end
    local live = Config.RecipeById and Config.RecipeById[r.recipe_id]
    local lab = (RecipeSnapshot and RecipeSnapshot.FacingLabel and RecipeSnapshot.FacingLabel(snap))
        or (live and live.label) or r.recipe_id
    local st = r.state or 'queued'
    local ings = {}
    if r.ingredients then
        local okd, dec = pcall(json.decode, r.ingredients)
        if okd and type(dec) == 'table' then ings = dec end
    end
    return {
        craftId = r.craft_id,
        identifier = r.identifier,
        recipeId = r.recipe_id,
        benchKey = r.bench_key,
        stationUid = r.station_uid or r.bench_key,
        batch = tonumber(r.batch) or 1,
        ingredients = ings,
        finishAt = tonumber(r.finish_at) or 0,
        createdAt = tonumber(r.created_at) or os.time(),
        startedAt = tonumber(r.started_at),
        duration = tonumber(r.duration_ms),
        durationMs = tonumber(r.duration_ms),
        snapshot = snap,
        recipeVersion = tonumber(r.recipe_version) or 0,
        label = lab,
        state = st,
        paused = st == 'paused',
        queuePosition = tonumber(r.queue_position) or 0,
        source = 'queue',
    }
end

function CraftQueue.RebuildAll()
    local rows = MySQL.query.await(
        "SELECT * FROM sanctuary_craft_queue WHERE state IN ('queued','processing','paused','running')"
    ) or {}
    byStation, byCraft, byIdent = {}, {}, {}
    local stations = {}
    for i = 1, #rows do
        local e = entryFromSql(rows[i])
        if e and e.craftId then
            put(e)
            stations[e.stationUid or e.benchKey] = true
        end
    end
    for uid in pairs(stations) do
        local procs = {}
        local map = byStation[uid] or {}
        for _, e in pairs(map) do
            if e.state == 'processing' or e.state == 'running' then
                procs[#procs + 1] = e
            end
        end
        table.sort(procs, function(a, b)
            return (tonumber(a.startedAt or a.createdAt) or 0) < (tonumber(b.startedAt or b.createdAt) or 0)
        end)
        for i = 2, #procs do
            procs[i].state = 'queued'
            procs[i].finishAt = 0
            procs[i].startedAt = nil
            persistRow(procs[i])
        end
        CraftQueue.Reorder(uid)
        local proc = CraftQueue.GetProcessing(uid)
        if proc and tonumber(proc.finishAt) and tonumber(proc.finishAt) > 0 and tonumber(proc.finishAt) <= os.time() then
            if StationOutput and StationOutput.Finalize then
                local recipe = proc.snapshot or (Config.RecipeById and Config.RecipeById[proc.recipeId])
                StationOutput.Finalize({
                    craftId = proc.craftId,
                    identifier = proc.identifier,
                    recipe = recipe,
                    snapshot = proc.snapshot or recipe,
                    recipeId = proc.recipeId,
                    recipeVersion = proc.recipeVersion,
                    benchKey = proc.benchKey,
                    stationUid = proc.stationUid or uid,
                    batch = proc.batch,
                    ingredients = proc.ingredients,
                    finishAt = proc.finishAt,
                    createdAt = proc.createdAt,
                    source = proc.source or 'queue',
                })
            end
            drop(proc.craftId)
        end
        if not CraftQueue.GetProcessing(uid) then
            CraftQueue.PromoteNext(uid)
        end
    end
    local nSt = 0
    for _ in pairs(stations) do nSt = nSt + 1 end
    print(('[sanctuary_crafting] queue rebuilt: %d live jobs, %d stations'):format(#rows, nSt))
end

function CraftQueue.LoadOffline(src)
    local id = ident(src)
    if not id then return end
    srcIdent[src] = id
    local rows = MySQL.query.await(
        "SELECT * FROM sanctuary_craft_queue WHERE identifier = ? AND state IN ('queued','processing','paused','running')",
        { id }
    ) or {}
    local seenUid = {}
    for i = 1, #rows do
        local e = entryFromSql(rows[i])
        if e and e.craftId then
            put(e)
            seenUid[e.stationUid or e.benchKey] = true
            if (e.state == 'processing' or e.state == 'running') and CraftingPipeline and CraftingPipeline.AdoptQueued then
                local finishAt = tonumber(e.finishAt) or 0
                if finishAt <= 0 or finishAt > os.time() then
                    local recipe = e.snapshot or (Config.RecipeById and Config.RecipeById[e.recipeId])
                    local bench = Benches and Benches.Resolve and Benches.Resolve(e.benchKey)
                    CraftingPipeline.AdoptQueued(src, e, recipe, bench)
                end
            end
        end
    end
    for uid in pairs(seenUid) do
        local proc = CraftQueue.GetProcessing(uid)
        if proc and tonumber(proc.finishAt) and tonumber(proc.finishAt) > 0 and tonumber(proc.finishAt) <= os.time() then
            if StationOutput and StationOutput.Finalize then
                local recipe = proc.snapshot or (Config.RecipeById and Config.RecipeById[proc.recipeId])
                StationOutput.Finalize({
                    craftId = proc.craftId,
                    identifier = proc.identifier,
                    src = (proc.identifier == id) and src or nil,
                    recipe = recipe,
                    snapshot = proc.snapshot or recipe,
                    recipeId = proc.recipeId,
                    benchKey = proc.benchKey,
                    stationUid = uid,
                    batch = proc.batch,
                    ingredients = proc.ingredients,
                    finishAt = proc.finishAt,
                    createdAt = proc.createdAt,
                    source = proc.source or 'queue',
                })
            end
            drop(proc.craftId)
            CraftQueue.PromoteNext(uid)
        elseif not proc then
            CraftQueue.PromoteNext(uid)
        end
    end
end

function CraftQueue.Enqueue(src, recipeId, benchKey, batch)
    if not Config.Queue or not Config.Queue.Enabled then
        return nil, 'queue_disabled'
    end
    if not CraftingPipeline or not CraftingPipeline.Start then
        return nil, 'craft_invalid'
    end
    local result = CraftingPipeline.Start(src, recipeId, benchKey, batch)
    if not result or not result.ok then
        return nil, result and result.reason or 'craft_failed', result and result.args
    end
    return result.entry or result, nil
end

function CraftQueue._startQueued(src, recipeId, benchKey, batch)
    return CraftQueue.Enqueue(src, recipeId, benchKey, batch)
end

CreateThread(function()
    MySQL.ready.await()
    CraftQueue.EnsureTable()
    Wait(700)
    CraftQueue.RebuildAll()
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = type(playerId) == 'number' and playerId or source
    if src then CraftQueue.LoadOffline(src) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    srcIdent[src] = nil
    lastRequest[src] = nil
end)

lib.callback.register('sanctuary_crafting:queueCraft', function(src, recipeId, benchKey, batch)
    local result = CraftingPipeline and CraftingPipeline.Start and CraftingPipeline.Start(src, recipeId, benchKey, batch)
    if not result or not result.ok then
        return { ok = false, reason = result and result.reason, args = result and result.args }
    end
    return result
end)

lib.callback.register('sanctuary_crafting:queueList', function(src, benchKey)
    if type(benchKey) == 'string' and benchKey ~= '' then
        return { ok = true, queue = CraftQueue.ListForStation(benchKey, src) }
    end
    return { ok = true, queue = CraftQueue.List(src) }
end)

lib.callback.register('sanctuary_crafting:queueCollect', function(src, craftId, benchKey)
    local ok, extra, extra2 = CraftQueue.TryCollect(src, craftId, benchKey)
    if not ok then return { ok = false, reason = extra, wait = extra2 } end
    return { ok = true, label = extra and extra.label }
end)

lib.callback.register('sanctuary_crafting:queueCancel', function(src, craftId)
    local ok, reason = CraftQueue.Cancel(src, craftId)
    return { ok = ok and true or false, reason = reason }
end)
