--[[
    systems/station_output.lua — craft results stay at the station until collected
    v2.23.0: no ox_inventory:AddItem on timer end. Snapshot once at complete.
    Sparse: extends sanctuary_craft_queue (no fat new schema).
]]

StationOutput = StationOutput or {}

local busy = {} -- [craftId] = true  completing / collect mutex
local outputCache = {} -- [identifier] = { [craftId] = row }  completed only

local STATES = {
    queued = true, processing = true, paused = true,
    completed = true, collected = true, cancelled = true, failed = true,
}

local function cfg()
    return Config.StationOutput or {}
end

function StationOutput.Enabled()
    local c = cfg()
    if c.Enabled == false then return false end
    return true
end

function StationOutput.XpOnCollect()
    local on = cfg().XpOn
    return on == 'collect'
end

function StationOutput.SameStationOnly()
    local c = cfg()
    if c.SameStationOnly == false then return false end
    return true
end

function StationOutput.Uid(benchOrKey)
    if type(benchOrKey) == 'string' and benchOrKey ~= '' then
        return benchOrKey
    end
    if type(benchOrKey) == 'table' then
        if type(benchOrKey.key) == 'string' and benchOrKey.key ~= '' then
            return benchOrKey.key
        end
        if benchOrKey.kind and benchOrKey.id then
            return ('%s:%s'):format(tostring(benchOrKey.kind), tostring(benchOrKey.id))
        end
    end
    return nil
end

function StationOutput.StationLabel(uid)
    if type(uid) ~= 'string' or uid == '' then return 'station' end
    local bench = Benches and Benches.Resolve and Benches.Resolve(uid)
    if bench then
        if type(bench.label) == 'string' and bench.label ~= '' then
            return bench.label
        end
        local localeKey = Config.BenchLabels and Config.BenchLabels[bench.category or bench.station]
        if localeKey then
            local lab = _(localeKey)
            if type(lab) == 'string' and lab ~= '' and lab ~= localeKey then
                return lab
            end
        end
        return bench.station or bench.category or uid
    end
    local kind, id = uid:match('^(%w+):(.+)$')
    if kind == 'world' and id then
        for _, w in ipairs(Config.WorldBenches or {}) do
            if w.id == id and type(w.label) == 'string' and w.label ~= '' then
                return w.label
            end
        end
    end
    return uid
end

local function identOf(src)
    return GetPlayerIdentifierSafe(src)
end

local function esxJob(src)
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local job = xPlayer.job
    if type(job) == 'table' and type(job.name) == 'string' and job.name ~= '' then
        return job.name
    end
    if xPlayer.getJob then
        local j = xPlayer.getJob()
        if type(j) == 'table' and type(j.name) == 'string' then
            return j.name
        end
    end
    return nil
end

local function decodeJson(s, fallback)
    if type(s) == 'table' then return s end
    if type(s) ~= 'string' or s == '' then return fallback end
    local ok, data = pcall(json.decode, s)
    if ok and type(data) == 'table' then return data end
    return fallback
end

local function encodeJson(t)
    if t == nil then return nil end
    if type(t) == 'string' then return t end
    local ok, s = pcall(json.encode, t)
    if ok then return s end
    return nil
end

local function cachePut(row)
    if not row or not row.identifier or not row.craftId then return end
    outputCache[row.identifier] = outputCache[row.identifier] or {}
    outputCache[row.identifier][row.craftId] = row
end

local function cacheDrop(identifier, craftId)
    if identifier and outputCache[identifier] then
        outputCache[identifier][craftId] = nil
    end
end

local function facingLabel(recipe, fallback)
    if recipe and OxItemCatalog and OxItemCatalog.RecipeLabel then
        local lab = OxItemCatalog.RecipeLabel(recipe)
        if type(lab) == 'string' and lab ~= '' then return lab end
    end
    if recipe and type(recipe.label) == 'string' and recipe.label ~= '' then
        return recipe.label
    end
    if recipe and recipe.result and recipe.result.item and OxItemCatalog and OxItemCatalog.Label then
        return OxItemCatalog.Label(recipe.result.item, nil, recipe.result.item)
    end
    return fallback or (recipe and recipe.id) or 'objet'
end

local function itemFacingLabel(item, fallback)
    if OxItemCatalog and OxItemCatalog.Label then
        return OxItemCatalog.Label(item, nil, fallback or item)
    end
    return fallback or item
end

--- Read-time ox fields — never stored in SQL.
local function decorateRow(row)
    if not row then return row end
    local item = row.resultItem or row.result_item
    local ox = item and OxItemCatalog and OxItemCatalog.Get and OxItemCatalog.Get(item)
    row.label = row.label or (ox and ox.label) or itemFacingLabel(item, row.recipeId)
    row.image = (ox and ox.image) or (item and (item .. '.png')) or nil
    row.stationLabel = row.stationLabel or StationOutput.StationLabel(row.stationUid or row.station_uid)
    local meta = row.metadata or row.resultMetadata or {}
    row.quality = row.quality or meta.quality
    row.lot = row.lot or meta.lot
    row.craftedBy = row.craftedBy or meta.craftedBy
    row.finishedAt = row.finishedAt or row.finished_at
    return row
end

function StationOutput.RowFromSql(r)
    if not r then return nil end
    local meta = decodeJson(r.result_metadata, {})
    local snap = nil
    if r.recipe_snapshot and RecipeSnapshot and RecipeSnapshot.Decode then
        snap = RecipeSnapshot.Decode(r.recipe_snapshot)
    else
        snap = decodeJson(r.recipe_snapshot, nil)
    end
    local row = {
        id = r.id,
        craftId = r.craft_id,
        identifier = r.identifier,
        recipeId = r.recipe_id,
        recipeVersion = tonumber(r.recipe_version) or 0,
        snapshot = snap,
        benchKey = r.bench_key,
        stationUid = r.station_uid or r.bench_key,
        state = r.state or 'queued',
        batch = tonumber(r.batch) or 1,
        ingredients = decodeJson(r.ingredients, {}),
        resultItem = r.result_item,
        resultCount = tonumber(r.result_count) or 0,
        metadata = meta,
        quality = r.quality or (meta and meta.quality),
        finishAt = tonumber(r.finish_at),
        finishedAt = tonumber(r.finished_at),
        createdAt = tonumber(r.created_at),
        ownerJob = r.owner_job,
        xpGranted = tonumber(r.xp_granted) == 1,
        source = (meta and meta.source) or 'queue',
    }
    return decorateRow(row)
end

function StationOutput.EnsureColumns()
    if not MySQL or not MySQL.query or not MySQL.query.await then return end
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `station_uid` VARCHAR(64) NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `state` VARCHAR(16) NOT NULL DEFAULT 'queued'")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `result_item` VARCHAR(64) NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `result_count` INT NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `result_metadata` LONGTEXT NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `quality` VARCHAR(24) NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `finished_at` INT NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `owner_job` VARCHAR(32) NULL")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD COLUMN `xp_granted` TINYINT(1) NOT NULL DEFAULT 0")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD KEY `idx_station_state` (`station_uid`, `state`)")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE sanctuary_craft_queue ADD KEY `idx_ident_state` (`identifier`, `state`)")
    end)
    -- Backfill station_uid from bench_key for legacy rows
    pcall(function()
        MySQL.query.await("UPDATE sanctuary_craft_queue SET station_uid = bench_key WHERE station_uid IS NULL OR station_uid = ''")
    end)
    pcall(function()
        -- legacy rows with no state were always in-flight; do NOT promote real queued jobs
        MySQL.query.await("UPDATE sanctuary_craft_queue SET state = 'processing' WHERE (state IS NULL OR state = '') AND finish_at > 0")
    end)
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

local UPSERT = [[
    INSERT INTO sanctuary_craft_queue
        (identifier, craft_id, recipe_id, bench_key, batch, ingredients, finish_at, created_at,
         recipe_snapshot, recipe_version, station_uid, state, result_item, result_count,
         result_metadata, quality, finished_at, owner_job, xp_granted)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
        result_item = VALUES(result_item),
        result_count = VALUES(result_count),
        result_metadata = VALUES(result_metadata),
        quality = VALUES(quality),
        finished_at = VALUES(finished_at),
        owner_job = VALUES(owner_job),
        xp_granted = VALUES(xp_granted)
]]

function StationOutput.Persist(row)
    if not row or not row.craftId then return false end
    local id = row.identifier
    if not id then return false end
    local snapJson = nil
    if row.snapshot then
        if RecipeSnapshot and RecipeSnapshot.Encode then
            snapJson = RecipeSnapshot.Encode(row.snapshot)
        else
            snapJson = encodeJson(row.snapshot)
        end
    end
    local ok = pcall(function()
        MySQL.insert.await(UPSERT, {
            id,
            row.craftId,
            row.recipeId,
            row.benchKey or row.stationUid,
            row.batch or 1,
            encodeJson(row.ingredients) or '[]',
            tonumber(row.finishAt) or 0,
            tonumber(row.createdAt) or os.time(),
            snapJson,
            tonumber(row.recipeVersion) or 0,
            row.stationUid or row.benchKey,
            row.state or 'processing',
            row.resultItem,
            row.resultCount,
            encodeJson(row.metadata),
            row.quality,
            row.finishedAt,
            row.ownerJob,
            row.xpGranted and 1 or 0,
        })
    end)
    if not ok then
        print(('[sanctuary_crafting] station_output persist failed craftId=%s'):format(tostring(row.craftId)))
        return false
    end
    if row.state == 'completed' then
        cachePut(row)
    else
        cacheDrop(id, row.craftId)
    end
    return true
end

function StationOutput.Delete(craftId, identifier)
    if type(craftId) ~= 'string' then return end
    MySQL.query.await('DELETE FROM sanctuary_craft_queue WHERE craft_id = ?', { craftId })
    if identifier then cacheDrop(identifier, craftId) end
end

--- Access: Config.OutputAccess = owner | crew | job | public
--- crew is a stub of job (ESX job/group). No crew framework invented.
--- Shared stations still don't allow steal by default (owner).
function StationOutput.CanAccess(src, row)
    if not row then return false, 'craft_invalid' end
    local mode = Config.OutputAccess or 'owner'
    if mode ~= 'owner' and mode ~= 'crew' and mode ~= 'job' and mode ~= 'public' then
        mode = 'owner'
    end
    local id = identOf(src)
    if mode == 'public' then
        return true
    end
    if id and row.identifier == id then
        return true
    end
    if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then
        return true
    end
    if mode == 'job' or mode == 'crew' then
        local job = esxJob(src)
        if job and row.ownerJob and job == row.ownerJob then
            return true
        end
        -- stub: no crew system — fall through to owner-only
    end
    return false, 'craft_denied'
end

function StationOutput.AtStation(src, row, benchKey)
    if not StationOutput.SameStationOnly() then
        return true
    end
    local uid = StationOutput.Uid(benchKey) or benchKey
    local rowUid = row.stationUid or row.benchKey
    if uid and rowUid and uid ~= rowUid then
        return false, 'craft_wrong_station'
    end
    local bench = Benches and Benches.Resolve and Benches.Resolve(uid or rowUid)
    if bench and bench.coords and Validation and Validation.IsNearBench then
        if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance or 2.5) then
            return false, 'craft_too_far'
        end
    end
    return true
end

local function dropFromQueueRam(craftId)
    if not CraftQueue or not CraftQueue.Detach then return end
    CraftQueue.Detach(craftId)
end

local function grantXp(src, recipe, batch, meta)
    if not src or src == 0 then return false end
    if not recipe then return false end
    batch = batch or 1
    local xp = (meta and meta.xp) or recipe.xp
    if xp and xp.category and xp.amount and CraftingSkills and CraftingSkills.AddCraftXp then
        CraftingSkills.AddCraftXp(src, xp.category, (xp.amount or 0) * batch)
        if NewlyLearned and NewlyLearned.ScanLevelUnlocks then
            NewlyLearned.ScanLevelUnlocks(src)
        end
    end
    if Config.Mastery and Config.Mastery.Enabled and Mastery and recipe.id then
        Mastery.Add(src, recipe.id, (Config.Mastery.XpPerCraft or 1) * batch)
    end
    return true
end

local function notifyReady(src, row)
    if not src or src == 0 then return end
    local label = row.label or itemFacingLabel(row.resultItem, row.recipeId)
    local count = row.resultCount or 1
    local station = row.stationLabel or StationOutput.StationLabel(row.stationUid)
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        description = _('craft_output_ready', label, count, station),
    })
    TriggerClientEvent('sanctuary_crafting:client:outputReady', src, {
        craftId = row.craftId,
        label = label,
        result = { item = row.resultItem, count = count, quality = row.quality },
        batch = row.batch,
        benchKey = row.benchKey or row.stationUid,
        stationUid = row.stationUid,
        stationLabel = station,
        quality = row.quality,
        lot = row.lot,
        craftedBy = row.craftedBy,
        finishedAt = row.finishedAt,
    })
end

--- Build the definitive result snapshot at complete (quality / lot / signature once).
function StationOutput.BuildSnapshot(src, recipe, bench, craftId, batch)
    batch = batch or 1
    local resultItem = recipe and recipe.result and recipe.result.item
    local resultCount = recipe and recipe.result and ((recipe.result.count or 1) * batch) or batch
    local quality = nil
    if src and src ~= 0 and CraftingPipeline and CraftingPipeline.RollQuality then
        quality = CraftingPipeline.RollQuality(src, recipe, bench)
    elseif Config.Quality and Config.Quality.Enabled and recipe and recipe.quality then
        quality = Config.Quality.DefaultTier or 'normal'
    end
    local meta, mode = {}, 'none'
    if CraftSignature and CraftSignature.Build then
        if src and src ~= 0 then
            meta, mode = CraftSignature.Build(src, recipe, bench, quality, craftId)
        else
            meta = {}
            if quality then meta.quality = quality end
            meta.craftedDate = os.date('%Y-%m-%d')
            local stationLabel = bench and (bench.label or bench.station or bench.category)
            if stationLabel then meta.station = stationLabel end
        end
    else
        if src and src ~= 0 then
            meta.craftedBy = identOf(src)
        end
        if quality then meta.quality = quality end
    end
    meta = meta or {}
    if recipe and recipe.xp then
        meta.xp = { category = recipe.xp.category, amount = recipe.xp.amount }
    end
    -- Byproducts rolled once at complete, stored (given on collect)
    local extras = {}
    if Config.Byproducts and Config.Byproducts.Enabled then
        for _, bp in ipairs((recipe and recipe.byproducts) or {}) do
            local chance = bp.chance or 1.0
            if math.random() <= chance then
                extras[#extras + 1] = { item = bp.item, count = bp.count or 1 }
            end
        end
    end
    if recipe and recipe.dismantle and Config.Dismantling and Config.Dismantling.Enabled and recipe.dismantleYields then
        local bonus = 0
        if src and src ~= 0 and Config.Dismantling.SkillYieldBonus and CraftingSkills then
            bonus = (CraftingSkills.GetCategoryBonus(Config.Skills.defaultCategory or 'engineer', src) or 0) / 100
        end
        extras = extras or {}
        for _, y in ipairs(recipe.dismantleYields) do
            local chance = math.min(1.0, (y.chance or 1.0) + bonus * 0.2)
            if math.random() <= chance then
                extras[#extras + 1] = { item = y.item, count = y.count or 1 }
            end
        end
        -- dismantle has no primary result; first extra becomes the stored result if missing
        if (not resultItem or resultItem == '') and extras[1] then
            resultItem = extras[1].item
            resultCount = extras[1].count
            table.remove(extras, 1)
        end
    end
    if #extras > 0 then meta.extras = extras end
    meta.mode = mode
    meta.source = 'station_output'
    return resultItem, resultCount, meta, quality
end

--- Finalize a processing job to completed. Idempotent. Does NOT AddItem.
--- ctx: { craftId, identifier, src?, recipe, bench?, batch, snapshot, recipeVersion,
---        ingredients, finishAt, createdAt, benchKey, stationUid, source }
function StationOutput.Finalize(ctx)
    if not ctx or type(ctx.craftId) ~= 'string' then
        return false, 'craft_invalid'
    end
    local craftId = ctx.craftId
    if busy[craftId] then
        return true, 'already'
    end
    busy[craftId] = true
    local okRun, a, b = pcall(function()
        -- already completed?
        local existing = MySQL.query.await('SELECT state, result_item FROM sanctuary_craft_queue WHERE craft_id = ? LIMIT 1', { craftId })
        if existing and existing[1] and existing[1].state == 'completed' then
            return true, 'already'
        end
        if existing and existing[1] and existing[1].state == 'collected' then
            StationOutput.Delete(craftId, ctx.identifier)
            return false, 'craft_invalid'
        end

        local recipe = ctx.recipe or ctx.snapshot
        if type(recipe) ~= 'table' and RecipeSnapshot and RecipeSnapshot.Of then
            recipe = RecipeSnapshot.Of(ctx)
        end
        if type(recipe) ~= 'table' then
            recipe = Config.RecipeById and Config.RecipeById[ctx.recipeId]
        end
        if type(recipe) ~= 'table' then
            return false, 'craft_invalid'
        end
        local bench = ctx.bench
        if not bench and Benches and Benches.Resolve then
            bench = Benches.Resolve(ctx.stationUid or ctx.benchKey)
        end
        local batch = ctx.batch or 1
        local src = ctx.src
        local identifier = ctx.identifier
        if (not identifier or identifier == '') and src then
            identifier = identOf(src)
        end
        if (not src or src == 0) and identifier and ESX and ESX.GetPlayerFromIdentifier then
            local xP = ESX.GetPlayerFromIdentifier(identifier)
            if xP then src = xP.source or xP.playerId end
        end
        local resultItem, resultCount, meta, quality = StationOutput.BuildSnapshot(src, recipe, bench, craftId, batch)
        meta.source = ctx.source or meta.source or 'queue'
        if not identifier then
            return false, 'craft_invalid'
        end
        local ownerJob = ctx.ownerJob
        if not ownerJob and src then ownerJob = esxJob(src) end
        local now = os.time()
        local row = {
            craftId = craftId,
            identifier = identifier,
            recipeId = recipe.id or ctx.recipeId,
            recipeVersion = ctx.recipeVersion or (recipe._version) or 0,
            snapshot = ctx.snapshot or recipe,
            benchKey = ctx.benchKey or (bench and bench.key),
            stationUid = ctx.stationUid or StationOutput.Uid(bench) or ctx.benchKey,
            state = 'completed',
            batch = batch,
            ingredients = ctx.ingredients or {},
            resultItem = resultItem,
            resultCount = resultCount,
            metadata = meta,
            quality = quality,
            finishAt = ctx.finishAt or now,
            finishedAt = now,
            createdAt = ctx.createdAt or now,
            ownerJob = ownerJob,
            xpGranted = false,
            source = meta.source,
        }
        decorateRow(row)

        local xpNow = src and src ~= 0 and not StationOutput.XpOnCollect()
        if xpNow then
            grantXp(src, recipe, batch, meta)
            row.xpGranted = true
        end

        if src and src ~= 0 then
            if Tools and Tools.WearRecipe then
                Tools.WearRecipe(src, recipe, batch)
            end
        end
        if StationRuntime and StationRuntime.Degrade and bench then
            StationRuntime.Degrade(bench, recipe, batch)
        end

        StationOutput.Persist(row)
        dropFromQueueRam(craftId)

        if CraftingCore and CraftingCore.Emit then
            CraftingCore.Emit('craftCompleted', src or 0, {
                craftId = craftId,
                recipeId = row.recipeId,
                benchKey = row.benchKey,
                stationUid = row.stationUid,
                batch = batch,
                src = src,
                identifier = identifier,
                output = true,
            }, { { item = resultItem, count = resultCount, quality = quality } })
            CraftingCore.Emit('outputReady', src or 0, row)
        end

        if src and src ~= 0 then
            notifyReady(src, row)
        end
        return true, row
    end)
    busy[craftId] = nil
    if not okRun then
        print(('[sanctuary_crafting] station_output finalize error: %s'):format(tostring(a)))
        return false, 'craft_failed'
    end
    return a, b
end

--- Catch-up a SQL row (boot / tick). Player may be offline.
function StationOutput.FinalizeRow(sqlRow, src)
    local row = StationOutput.RowFromSql(sqlRow)
    if not row then return false, 'craft_invalid' end
    if row.state == 'completed' then return true, 'already' end
    if row.state == 'paused' then return false, 'paused' end
    if row.state == 'cancelled' or row.state == 'failed' or row.state == 'collected' then
        return false, row.state
    end
    local recipe = row.snapshot
    if type(recipe) ~= 'table' then
        recipe = Config.RecipeById and Config.RecipeById[row.recipeId]
    end
    return StationOutput.Finalize({
        craftId = row.craftId,
        identifier = row.identifier,
        src = src,
        recipe = recipe,
        snapshot = row.snapshot,
        recipeId = row.recipeId,
        recipeVersion = row.recipeVersion,
        benchKey = row.benchKey,
        stationUid = row.stationUid,
        batch = row.batch,
        ingredients = row.ingredients,
        finishAt = row.finishAt,
        createdAt = row.createdAt,
        ownerJob = row.ownerJob,
        source = row.source or 'queue',
    })
end

local function giveStored(src, item, count, meta)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if not item then return false, 0 end
    local units = meta and meta.units
    if type(units) == 'table' and #units > 0 then
        local given = 0
        for i = 1, math.min(count, #units) do
            if not Validation.CanCarry(src, item, 1) then
                break
            end
            local added = exports.ox_inventory:AddItem(src, item, 1, units[i])
            if not added then break end
            given = given + 1
        end
        return given == count, given
    end
    local payload = meta
    if type(payload) == 'table' then
        -- strip internal bookkeeping from ox metadata
        payload = {}
        for k, v in pairs(meta) do
            if k ~= 'xp' and k ~= 'extras' and k ~= 'source' and k ~= 'units' and k ~= 'mode' then
                payload[k] = v
            end
        end
        if not next(payload) then payload = nil end
    end
    if not Validation.CanCarry(src, item, count) then
        return false, 0
    end
    local added = exports.ox_inventory:AddItem(src, item, count, payload)
    if not added then return false, 0 end
    return true, count
end

--- Collect one completed craft into player inventory. Transactional + idempotent.
function StationOutput.Collect(src, craftId, benchKey)
    if type(craftId) ~= 'string' then return false, 'craft_invalid' end
    if not StationOutput.Enabled() then
        -- fallback: old queue collect path
        if CraftQueue and CraftQueue.TryCollectLegacy then
            return CraftQueue.TryCollectLegacy(src, craftId)
        end
        return false, 'craft_invalid'
    end
    if busy[craftId] then return false, 'craft_busy' end
    busy[craftId] = true
    local okRun, a, b = pcall(function()
        local rows = MySQL.query.await('SELECT * FROM sanctuary_craft_queue WHERE craft_id = ? LIMIT 1', { craftId })
        local sql = rows and rows[1]
        if not sql then return false, 'craft_invalid' end
        if sql.state ~= 'completed' then
            if (sql.state == 'processing' or sql.state == 'queued') and tonumber(sql.finish_at) and tonumber(sql.finish_at) <= os.time() then
                local okF = StationOutput.FinalizeRow(sql, src)
                if okF then
                    rows = MySQL.query.await('SELECT * FROM sanctuary_craft_queue WHERE craft_id = ? LIMIT 1', { craftId })
                    sql = rows and rows[1]
                end
            end
        end
        if not sql or sql.state ~= 'completed' then
            if sql and (sql.state == 'queued' or sql.state == 'processing' or sql.state == 'paused') then
                return false, 'queue_not_ready'
            end
            return false, 'craft_invalid'
        end
        local row = StationOutput.RowFromSql(sql)
        local okA, rA = StationOutput.CanAccess(src, row)
        if not okA then return false, rA or 'craft_denied' end
        local okS, rS = StationOutput.AtStation(src, row, benchKey)
        if not okS then return false, rS or 'craft_wrong_station' end

        local item = row.resultItem
        local count = row.resultCount or 1
        local meta = row.metadata or {}
        if not item or count < 1 then
            StationOutput.Delete(craftId, row.identifier)
            return false, 'craft_invalid'
        end
        if not Validation.CanCarry(src, item, count) then
            return false, 'craft_inventory_insufficient'
        end
        local extras = meta.extras or {}
        for i = 1, #extras do
            local ex = extras[i]
            if ex and ex.item then
                if not Validation.CanCarry(src, ex.item, ex.count or 1) then
                    return false, 'craft_inventory_insufficient'
                end
            end
        end

        local okGive = giveStored(src, item, count, meta)
        if not okGive then
            return false, 'craft_inventory_insufficient'
        end
        -- extras after primary; if extras fail, keep remaining extras by rewriting metadata
        local leftover = {}
        for i = 1, #extras do
            local ex = extras[i]
            if ex and ex.item then
                local okEx = giveStored(src, ex.item, ex.count or 1, ex.metadata)
                if not okEx then
                    leftover[#leftover + 1] = ex
                end
            end
        end
        if #leftover > 0 then
            -- primary already given — do NOT double-give. Drop primary from row, keep extras.
            meta.extras = leftover
            local first = leftover[1]
            row.resultItem = first.item
            row.resultCount = first.count or 1
            meta.extras = leftover
            if leftover[1] then table.remove(leftover, 1) end
            row.metadata = meta
            StationOutput.Persist(row)
            return false, 'craft_inventory_insufficient'
        end

        if StationOutput.XpOnCollect() and not row.xpGranted then
            local recipe = row.snapshot or (Config.RecipeById and Config.RecipeById[row.recipeId])
            grantXp(src, recipe, row.batch or 1, meta)
        end

        -- DELETE active row (collected does not linger)
        StationOutput.Delete(craftId, row.identifier)
        dropFromQueueRam(craftId)

        if CraftingCore and CraftingCore.Emit then
            CraftingCore.Emit('outputCollected', src, row)
        end
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            description = _('craft_output_collected', row.label or itemFacingLabel(item, item), count),
        })
        TriggerClientEvent('sanctuary_crafting:client:outputCollected', src, {
            craftId = craftId,
            benchKey = row.benchKey or row.stationUid,
        })
        return true, row
    end)
    busy[craftId] = nil
    if not okRun then
        print(('[sanctuary_crafting] station_output collect error: %s'):format(tostring(a)))
        return false, 'craft_failed'
    end
    return a, b
end

function StationOutput.CollectAll(src, benchKey)
    local list = StationOutput.ListForStation(src, benchKey)
    local collected, failed, lastReason = 0, 0, nil
    for i = 1, #list do
        local ok, reason = StationOutput.Collect(src, list[i].craftId, benchKey)
        if ok then
            collected = collected + 1
        else
            failed = failed + 1
            lastReason = reason
            if reason == 'craft_inventory_insufficient' or reason == 'craft_inventory_full' then
                break
            end
        end
    end
    return collected, failed, lastReason
end

function StationOutput.ListForStation(src, benchKey)
    local id = identOf(src)
    if not id then return {} end
    local uid = StationOutput.Uid(benchKey) or benchKey
    local sql
    if uid and StationOutput.SameStationOnly() then
        sql = MySQL.query.await(
            "SELECT * FROM sanctuary_craft_queue WHERE state = 'completed' AND station_uid = ? ORDER BY finished_at ASC, id ASC",
            { uid }
        ) or {}
    else
        sql = MySQL.query.await(
            "SELECT * FROM sanctuary_craft_queue WHERE state = 'completed' AND identifier = ? ORDER BY finished_at ASC, id ASC",
            { id }
        ) or {}
    end
    local out = {}
    for i = 1, #sql do
        local row = StationOutput.RowFromSql(sql[i])
        local okA = StationOutput.CanAccess(src, row)
        if okA then
            out[#out + 1] = row
        end
    end
    return out
end

function StationOutput.ListReadyForPlayer(src)
    local id = identOf(src)
    if not id then return {} end
    local sql = MySQL.query.await(
        "SELECT * FROM sanctuary_craft_queue WHERE state = 'completed' AND identifier = ? ORDER BY finished_at ASC, id ASC",
        { id }
    ) or {}
    local out, byStation = {}, {}
    for i = 1, #sql do
        local row = StationOutput.RowFromSql(sql[i])
        out[#out + 1] = row
        local uid = row.stationUid or row.benchKey or '?'
        local slot = byStation[uid]
        if not slot then
            slot = { stationUid = uid, stationLabel = row.stationLabel or StationOutput.StationLabel(uid), count = 0 }
            byStation[uid] = slot
        end
        slot.count = slot.count + 1
    end
    local stations = {}
    for _, s in pairs(byStation) do stations[#stations + 1] = s end
    table.sort(stations, function(a, b) return (a.stationLabel or '') < (b.stationLabel or '') end)
    return out, stations
end

function StationOutput.CountReady(src, benchKey)
    local list = StationOutput.ListForStation(src, benchKey)
    return #list
end

function StationOutput.CountReadyPlayer(src)
    local id = identOf(src)
    if not id then return 0 end
    local rows = MySQL.query.await(
        "SELECT COUNT(*) AS n FROM sanctuary_craft_queue WHERE state = 'completed' AND identifier = ?",
        { id }
    )
    return (rows and rows[1] and tonumber(rows[1].n)) or 0
end

function StationOutput.SerializeOutput(row)
    if not row then return nil end
    decorateRow(row)
    return {
        craftId = row.craftId,
        recipeId = row.recipeId,
        benchKey = row.benchKey or row.stationUid,
        stationUid = row.stationUid,
        stationLabel = row.stationLabel,
        state = 'completed',
        batch = row.batch or 1,
        quantity = row.resultCount or row.batch or 1,
        resultItem = row.resultItem,
        resultCount = row.resultCount,
        item = row.resultItem,
        count = row.resultCount,
        label = row.label,
        image = row.image,
        quality = row.quality,
        lot = row.lot or (row.metadata and row.metadata.lot),
        craftedBy = row.craftedBy or (row.metadata and row.metadata.craftedBy),
        finishedAt = row.finishedAt,
        finishAt = row.finishedAt,
        createdAt = row.createdAt,
    }
end

function StationOutput.GrantPendingXp(src)
    local id = identOf(src)
    if not id then return end
    local rows = MySQL.query.await(
        "SELECT * FROM sanctuary_craft_queue WHERE identifier = ? AND state = 'completed' AND xp_granted = 0",
        { id }
    ) or {}
    for i = 1, #rows do
        local row = StationOutput.RowFromSql(rows[i])
        if row and not StationOutput.XpOnCollect() then
            local recipe = row.snapshot or (Config.RecipeById and Config.RecipeById[row.recipeId])
            if grantXp(src, recipe, row.batch or 1, row.metadata) then
                MySQL.update.await(
                    'UPDATE sanctuary_craft_queue SET xp_granted = 1 WHERE craft_id = ?',
                    { row.craftId }
                )
                row.xpGranted = true
            end
        end
    end
end

function StationOutput.CatchUpOverdue()
    local now = os.time()
    -- queued jobs have finish_at = 0 and must NEVER be auto-completed
    local rows = MySQL.query.await(
        "SELECT * FROM sanctuary_craft_queue WHERE state IN ('processing','running') AND finish_at <= ? AND finish_at > 0",
        { now }
    ) or {}
    local n = 0
    local stations = {}
    for i = 1, #rows do
        local uid = rows[i].station_uid or rows[i].bench_key
        local cid = rows[i].craft_id
        -- Online interactive crafts: pipeline watchdog finalizes (GetGameTimer). Skip steal.
        if cid and CraftingPipeline and CraftingPipeline.Get and CraftingPipeline.Get(cid) then
            goto continue_catchup
        end
        local ok = StationOutput.FinalizeRow(rows[i], nil)
        if ok then
            n = n + 1
            if uid then stations[uid] = true end
            if CraftQueue and CraftQueue.Detach then CraftQueue.Detach(cid) end
        end
        ::continue_catchup::
    end
    for uid in pairs(stations) do
        if CraftQueue and CraftQueue.PromoteNext then
            CraftQueue.PromoteNext(uid)
        end
    end
    if n > 0 then
        print(('[sanctuary_crafting] station_output catch-up: %d → completed'):format(n))
    end
    return n
end

function StationOutput.PurgeExpired()
    local days = Config.CompletedRetentionDays
    if days == nil or days == false then return end
    days = tonumber(days)
    if not days or days <= 0 then return end
    local cutoff = os.time() - math.floor(days * 86400)
    local ok, n = pcall(function()
        return MySQL.update.await(
            "DELETE FROM sanctuary_craft_queue WHERE state = 'completed' AND finished_at > 0 AND finished_at < ?",
            { cutoff }
        )
    end)
    if ok and n and n > 0 then
        print(('[sanctuary_crafting] station_output purged %s completed older than %s days'):format(tostring(n), tostring(days)))
    end
end

function StationOutput.Boot()
    StationOutput.EnsureColumns()
    StationOutput.CatchUpOverdue()
    StationOutput.PurgeExpired()
    -- Warm completed cache
    local rows = MySQL.query.await("SELECT * FROM sanctuary_craft_queue WHERE state = 'completed'") or {}
    for i = 1, #rows do
        cachePut(StationOutput.RowFromSql(rows[i]))
    end
end

function StationOutput.IsCancelable(state)
    return state == 'queued' or state == 'processing' or state == 'paused' or state == nil or state == 'running'
end

CreateThread(function()
    MySQL.ready.await()
    if not StationOutput.Enabled() then return end
    StationOutput.Boot()
    while true do
        Wait(5000)
        StationOutput.CatchUpOverdue()
    end
end)

CreateThread(function()
    MySQL.ready.await()
    if not StationOutput.Enabled() then return end
    while true do
        Wait(3600000)
        StationOutput.PurgeExpired()
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = type(playerId) == 'number' and playerId or source
    if not src then return end
    if not StationOutput.Enabled() then return end
    -- finalize any overdue jobs for this player, then grant pending XP
    local id = identOf(src)
    if id then
        local rows = MySQL.query.await(
            "SELECT * FROM sanctuary_craft_queue WHERE identifier = ? AND state IN ('processing','running') AND finish_at > 0 AND finish_at <= ?",
            { id, os.time() }
        ) or {}
        for i = 1, #rows do
            StationOutput.FinalizeRow(rows[i], src)
        end
    end
    StationOutput.GrantPendingXp(src)
end)

lib.callback.register('sanctuary_crafting:collectCraft', function(src, craftId, benchKey)
    local ok, extra = StationOutput.Collect(src, craftId, benchKey)
    if not ok then return { ok = false, reason = extra } end
    return { ok = true, label = extra and extra.label, craftId = craftId }
end)

lib.callback.register('sanctuary_crafting:collectAll', function(src, benchKey)
    local n, failed, reason = StationOutput.CollectAll(src, benchKey)
    return { ok = true, collected = n, failed = failed, reason = reason }
end)

lib.callback.register('sanctuary_crafting:getStationOutput', function(src, benchKey)
    local list = StationOutput.ListForStation(src, benchKey)
    local serial = {}
    for i = 1, #list do
        serial[i] = StationOutput.SerializeOutput(list[i])
    end
    return { ok = true, output = serial, count = #serial }
end)
