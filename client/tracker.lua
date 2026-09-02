--[[
    client/tracker.lua — Craft Tracker flottant (visuel only)
    Server reste source de vérité pour complete / rewards.
]]

CraftTracker = CraftTracker or {}

local jobs = {} -- [craftId] = entry
local menuOpen = false
local lastBenchKey = nil
local lastSessionFetch = 0
local cfg

local function trackerCfg()
    cfg = Config.CraftTracker
    return cfg
end

local function enabled()
    local c = trackerCfg()
    return c and c.Enabled ~= false
end

local function nowMs()
    return GetGameTimer()
end

local function wallMs()
    return (os.time and os.time() or 0) * 1000
end

local function phaseFamilyFor(category)
    if not category then return 'default' end
    local cat = string.lower(tostring(category))
    if cat:find('medical', 1, true) or cat:find('medecin', 1, true) or cat:find('pharma', 1, true) or cat:find('soin', 1, true) then
        return 'medical'
    end
    if cat:find('mechanic', 1, true) or cat:find('mecano', 1, true) or cat:find('ingenieur', 1, true)
        or cat:find('armurier', 1, true) or cat:find('weapon', 1, true) or cat:find('scrap', 1, true)
        or cat:find('construction', 1, true) then
        return 'mechanical'
    end
    if cat:find('cook', 1, true) or cat:find('cuisine', 1, true) or cat:find('food', 1, true)
        or cat:find('boucher', 1, true) then
        return 'cooking'
    end
    return 'default'
end

local function kvpKey(suffix)
    return ('sanctuary_craft_tracker_%s'):format(suffix)
end

local function send(action, payload)
    if not enabled() then return end
    local msg = payload or {}
    msg.action = action
    SendNUIMessage(msg)
end

local function buildConfigPayload()
    local c = trackerCfg() or {}
    return {
        enabled = enabled(),
        defaultPosition = c.DefaultPosition or { top = 24, right = 24 },
        defaultMode = c.DefaultMode or 'normal',
        autoShowOnStart = c.AutoShowOnStart ~= false,
        hideWithMenuIfUnpinned = c.HideWithMenuIfUnpinned ~= false,
        persistPin = c.PersistPin ~= false,
        persistMode = c.PersistMode ~= false,
        persistPosition = c.PersistPosition ~= false,
        allowDrag = c.AllowDrag ~= false,
        completedLingerMs = c.CompletedLingerMs or 4500,
        autoRemoveCompleted = c.AutoRemoveCompleted ~= false,
        tickMs = c.TickMs or 250,
        phases = c.Phases or {},
        sounds = c.Sounds or {},
        uiSounds = (Config.UI and Config.UI.Sounds) or {},
    }
end

local function listJobs()
    local out = {}
    for _, e in pairs(jobs) do
        out[#out + 1] = e
    end
    table.sort(out, function(a, b)
        return (a.startedAt or 0) < (b.startedAt or 0)
    end)
    return out
end

function CraftTracker.SetLastBench(key)
    if type(key) == 'string' and key ~= '' then
        lastBenchKey = key
    end
end

function CraftTracker.FromSessionActive(entry)
    if not entry or not entry.craftId then return nil end
    local remaining = tonumber(entry.remainingMs)
    if remaining == nil then remaining = tonumber(entry.duration) or 0 end
    local duration = tonumber(entry.durationMs) or remaining
    local started = nowMs() - math.max(0, duration - remaining)
    local category = entry.category or entry.phaseFamily
    return {
        craftId = entry.craftId,
        recipeId = entry.recipeId,
        label = entry.label or entry.stepLabel or entry.recipeId,
        item = entry.resultItem or entry.item,
        count = entry.resultCount or entry.batch or 1,
        batch = entry.batch or 1,
        benchKey = entry.benchKey,
        benchLabel = entry.benchLabel,
        status = 'active',
        startedAt = started,
        endsAt = nowMs() + remaining,
        duration = duration,
        stepIndex = entry.stepIndex or 1,
        totalSteps = entry.totalSteps or 1,
        stepLabel = entry.stepLabel or entry.label,
        phaseFamily = entry.phaseFamily or phaseFamilyFor(category),
        category = category,
        clientTimer = nowMs(),
        wallNow = wallMs(),
        useWallClock = false,
    }
end

--- Replace RAM jobs for this bench with server session (station-scoped).
--- Other benches' jobs are kept; session.other is upserted without removal.
function CraftTracker.ApplySession(benchKey, session)
    if not enabled() or type(session) ~= 'table' then return end
    if type(benchKey) == 'string' and benchKey ~= '' then
        lastBenchKey = benchKey
    end
    local keep = {}
    for _, a in ipairs(session.active or {}) do
        local e = CraftTracker.FromSessionActive(a)
        if e then
            CraftTracker.Upsert(e)
            keep[e.craftId] = true
        end
    end
    for _, q in ipairs(session.queued or {}) do
        local e = CraftTracker.FromQueueEntry(q)
        if e then
            CraftTracker.Upsert(e)
            keep[e.craftId] = true
        end
    end
    for _, o in ipairs(session.other or {}) do
        local e = CraftTracker.FromSessionActive(o)
        if e then CraftTracker.Upsert(e) end
    end
    local key = benchKey or lastBenchKey
    if key then
        local drop = {}
        for id, job in pairs(jobs) do
            if job.benchKey == key and not keep[id] then
                local st = job.status
                if st == 'done' or st == 'completing' or st == 'completed' then
                    -- keep linger card
                elseif st == 'active' then
                    local remaining = (job.endsAt or 0) - nowMs()
                    if remaining <= 0 then
                        -- Session no longer has this job: server just finalized. Show TERMINÉ, don't yank.
                        CraftTracker.Upsert({
                            craftId = id,
                            status = 'done',
                            stepLabel = 'FABRICATION TERMINÉE',
                        })
                    else
                        drop[#drop + 1] = id
                    end
                elseif st == 'queued' or st == 'paused' then
                    drop[#drop + 1] = id
                end
            end
        end
        for i = 1, #drop do
            CraftTracker.Remove(drop[i])
        end
    end
end

function CraftTracker.RefreshSession(benchKey)
    if not enabled() then return end
    benchKey = benchKey or lastBenchKey
    if type(benchKey) ~= 'string' or benchKey == '' then return end
    local t = nowMs()
    if (t - lastSessionFetch) < 300 then return end
    lastSessionFetch = t
    local r = lib.callback.await('sanctuary_crafting:getCraftSession', false, benchKey)
    if r and r.ok and r.session then
        CraftTracker.ApplySession(benchKey, r.session)
    end
end

function CraftTracker.Sync()
    if not enabled() then return end
    if menuOpen and lastBenchKey then
        CraftTracker.RefreshSession(lastBenchKey)
    end
    send('tracker:sync', {
        jobs = listJobs(),
        menuOpen = menuOpen,
        config = buildConfigPayload(),
    })
end

function CraftTracker.Upsert(entry)
    if not enabled() or type(entry) ~= 'table' or not entry.craftId then return end
    local prev = jobs[entry.craftId] or {}
    local merged = {}
    for k, v in pairs(prev) do merged[k] = v end
    for k, v in pairs(entry) do merged[k] = v end

    merged.craftId = entry.craftId
    merged.status = merged.status or 'active'
    merged.startedAt = merged.startedAt or nowMs()
    merged.duration = tonumber(merged.duration) or 0
    if not merged.endsAt and merged.duration > 0 then
        merged.endsAt = merged.startedAt + merged.duration
    end
    if not merged.clientTimer then
        merged.clientTimer = nowMs()
    end
    if not merged.wallNow then
        merged.wallNow = wallMs()
    end
    if not merged.phaseFamily then
        merged.phaseFamily = phaseFamilyFor(merged.category or merged.phaseFamily)
    end

    jobs[merged.craftId] = merged
    send('tracker:upsert', { entry = merged, menuOpen = menuOpen, config = buildConfigPayload() })
end

function CraftTracker.Remove(id)
    if not id then return end
    jobs[id] = nil
    if not enabled() then return end
    send('tracker:remove', { craftId = id })
end

function CraftTracker.SetMenuOpen(isOpen)
    menuOpen = isOpen and true or false
    if not enabled() then return end
    if menuOpen and lastBenchKey then
        CraftTracker.RefreshSession(lastBenchKey)
    end
    send('tracker:menuState', {
        menuOpen = menuOpen,
        config = buildConfigPayload(),
        jobs = listJobs(),
    })
end

function CraftTracker.HasActive()
    for _, e in pairs(jobs) do
        local st = e.status
        if st == 'active' or st == 'queued' or st == 'paused' then
            return true
        end
    end
    return false
end

function CraftTracker.Get(id)
    return jobs[id]
end

--- Build entry from startCraft / completeCraft response + optional recipe meta
function CraftTracker.FromStart(data, meta)
    if not data or not data.ok or not data.craftId then return nil end
    meta = meta or {}
    local duration = tonumber(data.duration) or 0
    local started = nowMs()
    local label = data.stepLabel or data.label or meta.label or data.recipeId or meta.recipeId
    local item = data.resultItem or meta.item or meta.resultItem
    local count = data.resultCount or meta.count or meta.resultCount or data.batch or 1
    local category = data.category or meta.category
    return {
        craftId = data.craftId,
        recipeId = data.recipeId or meta.recipeId,
        label = label,
        item = item,
        count = count,
        batch = data.batch or meta.batch or 1,
        benchKey = data.benchKey or meta.benchKey,
        benchLabel = data.benchLabel or meta.benchLabel,
        status = 'active',
        startedAt = started,
        endsAt = started + duration,
        duration = duration,
        stepIndex = data.stepIndex or 1,
        totalSteps = data.totalSteps or 1,
        stepLabel = data.stepLabel or data.label,
        phaseFamily = data.phaseFamily or phaseFamilyFor(category),
        category = category,
        clientTimer = started,
        wallNow = wallMs(),
    }
end

function CraftTracker.FromQueueEntry(entry, meta)
    if not entry or not entry.craftId then return nil end
    meta = meta or {}
    local finishAt = tonumber(entry.finishAt) or 0
    local createdAt = tonumber(entry.createdAt) or (finishAt - math.ceil((entry.duration or 0) / 1000))
    local duration = tonumber(entry.duration) or math.max(0, (finishAt - createdAt) * 1000)
    local category = meta.category or entry.category
    return {
        craftId = entry.craftId,
        recipeId = entry.recipeId,
        label = entry.label or meta.label or entry.recipeId,
        item = meta.item or entry.resultItem or entry.recipeId,
        count = entry.batch or 1,
        batch = entry.batch or 1,
        benchKey = entry.benchKey or meta.benchKey,
        benchLabel = meta.benchLabel or entry.benchLabel,
        status = 'queued',
        startedAt = createdAt * 1000,
        endsAt = finishAt * 1000,
        duration = duration,
        useWallClock = true,
        stepIndex = 1,
        totalSteps = 1,
        stepLabel = 'En file',
        phaseFamily = phaseFamilyFor(category),
        category = category,
        queueWaiting = 0,
        wallNow = wallMs(),
        clientTimer = nowMs(),
    }
end

local function mirrorKvp(key, value)
    local c = trackerCfg()
    if not c then return end
    if key == 'pin' and c.PersistPin == false then return end
    if key == 'mode' and c.PersistMode == false then return end
    if key == 'pos' and c.PersistPosition == false then return end
    SetResourceKvp(kvpKey(key), tostring(value))
end

local function playTrackerSound(kind)
    local c = trackerCfg()
    if not c or not c.Sounds or c.Sounds.Enabled == false then return end
    if kind == 'start' and c.Sounds.OnStart == false then return end
    if kind == 'complete' and c.Sounds.OnComplete == false then return end
    if kind == 'error' and c.Sounds.OnError == false then return end
    -- NUI plays WebAudio / ogg; client just flags via message already sent
end

-- NUI callbacks -------------------------------------------------------------

RegisterNUICallback('trackerPin', function(data, cb)
    local pinned = data and data.pinned
    mirrorKvp('pin', pinned and '1' or '0')
    cb({ ok = true })
end)

RegisterNUICallback('trackerMode', function(data, cb)
    local mode = data and data.mode or 'normal'
    mirrorKvp('mode', mode)
    cb({ ok = true })
end)

RegisterNUICallback('trackerPosition', function(data, cb)
    if data and data.top ~= nil and data.right ~= nil then
        mirrorKvp('pos', json.encode({ top = data.top, right = data.right, left = data.left, bottom = data.bottom }))
    end
    cb({ ok = true })
end)

RegisterNUICallback('trackerResetPosition', function(_, cb)
    local c = trackerCfg()
    local pos = (c and c.DefaultPosition) or { top = 24, right = 24 }
    DeleteResourceKvp(kvpKey('pos'))
    send('tracker:setVisible', { resetPosition = pos })
    cb({ ok = true, position = pos })
end)

RegisterNUICallback('trackerClick', function(data, cb)
    local id = data and data.craftId
    local entry = id and jobs[id]
    local benchKey = (data and data.benchKey) or (entry and entry.benchKey)
    if benchKey and OpenCraftMenu then
        OpenCraftMenu(benchKey)
    end
    cb({ ok = true })
end)

RegisterNUICallback('trackerDismiss', function(data, cb)
    local id = data and data.craftId
    if id then CraftTracker.Remove(id) end
    cb({ ok = true })
end)

RegisterNUICallback('trackerCancel', function(data, cb)
    local id = data and data.craftId
    if id then
        TriggerServerEvent('sanctuary_crafting:server:cancelCraft', id)
        CraftTracker.Upsert({
            craftId = id,
            status = 'cancelled',
        })
        SetTimeout(800, function()
            CraftTracker.Remove(id)
        end)
    end
    cb({ ok = true })
end)

RegisterNUICallback('trackerComplete', function(data, cb)
    local id = data and data.craftId
    if not id then
        cb({ ok = false, reason = 'craft_invalid' })
        return
    end
    local entry = jobs[id]
    if entry and entry.status == 'queued' then
        -- Queue: collect via existing path when ready
        local r = lib.callback.await('sanctuary_crafting:queueCollect', false, id)
        if r and r.ok then
            CraftTracker.Upsert({
                craftId = id,
                status = 'done',
                label = r.label or (entry and entry.label),
                stepLabel = 'FABRICATION TERMINÉE',
            })
            playTrackerSound('complete')
            cb(r)
            return
        end
        -- Not ready or failed — keep queued / mark error
        if r and r.reason == 'queue_not_ready' then
            cb(r or { ok = false })
            return
        end
        CraftTracker.Upsert({ craftId = id, status = 'error', stepLabel = 'Erreur' })
        playTrackerSound('error')
        cb(r or { ok = false })
        return
    end

    local result = lib.callback.await('sanctuary_crafting:completeCraft', false, id)
    if result and result.ok and result.advanced then
        local duration = tonumber(result.duration) or 0
        local started = nowMs()
        CraftTracker.Upsert({
            craftId = id,
            status = 'active',
            startedAt = started,
            endsAt = started + duration,
            duration = duration,
            stepIndex = result.stepIndex,
            totalSteps = result.totalSteps,
            stepLabel = result.stepLabel or result.label,
            label = result.label or (entry and entry.label),
            clientTimer = started,
            wallNow = wallMs(),
            useWallClock = false,
        })
        cb(result)
        return
    end

    if result and (result.ok or result.already) then
        CraftTracker.Upsert({
            craftId = id,
            status = 'done',
            stepLabel = 'FABRICATION TERMINÉE',
            label = result.label or (entry and entry.label),
            item = (result.result and result.result.item) or (entry and entry.item),
            count = (result.result and result.result.count) or (entry and entry.count),
        })
        playTrackerSound('complete')
        cb(result)
        return
    end

    local reason = result and result.reason or 'craft_failed'
    -- craft_too_far must not happen at 100%; treat as done (watchdog grants)
    if reason == 'craft_invalid' or reason == 'craft_too_far' or (result and result.already) then
        CraftTracker.Upsert({
            craftId = id,
            status = 'done',
            stepLabel = 'FABRICATION TERMINÉE',
            label = entry and entry.label,
        })
        cb({ ok = true, already = true })
        return
    end
    CraftTracker.Upsert({
        craftId = id,
        status = 'error',
        stepLabel = 'Erreur',
    })
    playTrackerSound('error')
    cb(result or { ok = false })
end)

local function refreshQueueIntoTracker()
    if not enabled() then return end
    if not (Config.Queue and Config.Queue.Enabled) then return end
    local r = lib.callback.await('sanctuary_crafting:queueList', false)
    if not r or not r.queue then return end
    for i = 1, #r.queue do
        local qe = CraftTracker.FromQueueEntry(r.queue[i])
        if qe then CraftTracker.Upsert(qe) end
    end
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if not enabled() then return end
    SetTimeout(1500, function()
        CraftTracker.Sync()
        refreshQueueIntoTracker()
    end)
end)

RegisterNetEvent('esx:playerLoaded', function()
    if not enabled() then return end
    SetTimeout(2000, function()
        CraftTracker.Sync()
        refreshQueueIntoTracker()
    end)
end)

RegisterNetEvent('sanctuary_crafting:client:craftFinished', function(payload)
    if not enabled() then return end
    payload = type(payload) == 'table' and payload or {}
    local craftId = payload.craftId
    if not craftId then return end
    CraftTracker.Upsert({
        craftId = craftId,
        status = 'done',
        stepLabel = 'FABRICATION TERMINÉE',
        label = payload.label,
        item = payload.result and payload.result.item,
        count = payload.result and payload.result.count,
        batch = payload.batch,
        benchKey = payload.benchKey,
    })
end)

RegisterNetEvent('sanctuary_crafting:client:craftAdvanced', function(payload)
    if not enabled() then return end
    payload = type(payload) == 'table' and payload or {}
    local craftId = payload.craftId
    if not craftId then return end
    local duration = tonumber(payload.duration) or 0
    local started = nowMs()
    CraftTracker.Upsert({
        craftId = craftId,
        status = 'active',
        startedAt = started,
        endsAt = started + duration,
        duration = duration,
        stepIndex = payload.stepIndex,
        totalSteps = payload.totalSteps,
        stepLabel = payload.stepLabel or payload.label,
        label = payload.label,
        clientTimer = started,
        wallNow = wallMs(),
        useWallClock = false,
    })
end)

-- Expose for nui.lua
exports('CraftTrackerUpsert', CraftTracker.Upsert)
exports('CraftTrackerRemove', CraftTracker.Remove)
exports('CraftTrackerSync', CraftTracker.Sync)
