--[[
    stations/runtime.lua — modules, levels, condition, heat, snapshot
    World benches: skip modules / skip-or-light condition. Placed must work.
]]

StationRuntime = StationRuntime or {}

local worldHeat = {} -- [bench.key] = { temp, updated }
local worldCond = {} -- [bench.key] = pct  (light mode only)

local function cfg()
    return Config.Stations or {}
end

local function moduleDefs()
    return (cfg().ModuleDefs) or {}
end

function StationRuntime.ModuleList(bench)
    if not bench then return {} end
    local mods = bench.modules or {}
    if type(mods) ~= 'table' then return {} end
    -- normalize to array of ids
    local out = {}
    if #mods > 0 then
        for i = 1, #mods do
            if type(mods[i]) == 'string' then out[#out + 1] = mods[i] end
            if type(mods[i]) == 'table' and mods[i].id then out[#out + 1] = mods[i].id end
        end
        return out
    end
    for k, v in pairs(mods) do
        if type(k) == 'string' and v then out[#out + 1] = k end
    end
    return out
end

function StationRuntime.HasModule(bench, id)
    local list = StationRuntime.ModuleList(bench)
    for i = 1, #list do
        if list[i] == id then return true end
    end
    return false
end

function StationRuntime.WorldSkipsModules(bench)
    if not bench or bench.kind ~= 'world' then return false end
    if cfg().WorldSkipModules == false then return false end
    return true
end

function StationRuntime.ConditionEnabled(bench)
    local c = cfg().Condition
    if not c or c.Enabled ~= true then return false end
    if bench and bench.kind == 'world' then
        return (c.WorldMode or 'skip') == 'light'
    end
    return true
end

function StationRuntime.HeatEnabled(bench)
    local h = cfg().Heat
    if not h or h.Enabled ~= true then return false end
    if not bench then return true end
    local industrial = h.Industrial or {}
    local cat = bench.station or bench.category
    if next(industrial) ~= nil and not industrial[cat] then
        return false
    end
    return true
end

function StationRuntime.Modifiers(bench)
    local m = {
        speed = 0, efficiency = 0, quality = 0, energy = 0,
        queueSize = 0, noise = 0, temperature = 0, durability = 0,
    }
    if not bench then return m end
    if StationRuntime.WorldSkipsModules(bench) then
        -- still apply if world already has modules in config
    end
    local defs = moduleDefs()
    local list = StationRuntime.ModuleList(bench)
    for i = 1, #list do
        local def = defs[list[i]]
        local mods = def and def.modifiers
        if type(mods) == 'table' then
            for k, v in pairs(mods) do
                if type(m[k]) == 'number' and type(v) == 'number' then
                    m[k] = m[k] + v
                end
            end
        end
    end
    -- condition penalties
    if StationRuntime.ConditionEnabled(bench) then
        local pct = StationRuntime.GetCondition(bench)
        if pct < 50 then
            local t = (50 - pct) / 50
            m.speed = m.speed - (0.18 * t)
            m.efficiency = m.efficiency - (0.20 * t)
            m.quality = m.quality - math.floor(t * 1.5)
            m.energy = m.energy + (0.15 * t)
        end
        if pct < 20 then
            m.speed = m.speed - 0.10
        end
    end
    -- heat
    if StationRuntime.HeatEnabled(bench) then
        local temp = StationRuntime.GetTemp(bench)
        local over = (cfg().Heat and cfg().Heat.OverheatAt) or 85
        if temp >= over then
            m.speed = m.speed - 0.12
            m.efficiency = m.efficiency - 0.08
        end
        m.temperature = m.temperature + (temp or 0)
    end
    return m
end

function StationRuntime.EfficiencyPct(bench)
    local mods = StationRuntime.Modifiers(bench)
    local base = 100
    local pct = math.floor(base + (mods.efficiency or 0) * 100)
    if StationRuntime.ConditionEnabled(bench) then
        local cond = StationRuntime.GetCondition(bench)
        pct = math.floor((pct * 0.55) + (cond * 0.45))
    end
    if pct < 5 then pct = 5 end
    if pct > 160 then pct = 160 end
    return pct
end

function StationRuntime.ApplyDuration(duration, bench)
    duration = tonumber(duration) or 5000
    local mods = StationRuntime.Modifiers(bench)
    local factor = 1 - (mods.speed or 0)
    if factor < 0.45 then factor = 0.45 end
    if factor > 1.8 then factor = 1.8 end
    return math.max(500, math.floor(duration * factor))
end

function StationRuntime.QualityNudge(bench)
    return math.floor(tonumber(StationRuntime.Modifiers(bench).quality) or 0)
end

function StationRuntime.FailChance(bench)
    if not StationRuntime.ConditionEnabled(bench) then return 0 end
    local pct = StationRuntime.GetCondition(bench)
    local c = cfg().Condition or {}
    local failBelow = c.FailBelow or 8
    if pct > 35 then return 0 end
    if pct <= failBelow then
        return math.min(0.22, 0.06 + (failBelow - pct) * 0.015)
    end
    return (35 - pct) * 0.004
end

function StationRuntime.GetCondition(bench)
    if not bench then return 100 end
    if bench.kind == 'placed' then
        return tonumber(bench.condition) or 100
    end
    if (cfg().Condition and cfg().Condition.WorldMode) == 'light' then
        return tonumber(worldCond[bench.key]) or 100
    end
    return 100
end

function StationRuntime.GetTemp(bench)
    if not bench then return 20 end
    if bench.kind == 'placed' then
        return tonumber(bench.heat) or 20
    end
    local w = worldHeat[bench.key]
    return (w and w.temp) or 20
end

function StationRuntime.GetVentilation(bench)
    local v = 0
    if StationRuntime.HasModule(bench, 'ventilation') then v = v + 1 end
    if StationRuntime.HasModule(bench, 'cooling') then v = v + 1 end
    if StationRuntime.HasModule(bench, 'filter') then v = v + 1 end
    return v
end

--- Persist only fields that must survive restart (level/modules/condition/broken_parts).
--- Heat is RAM-only (C): cools to ambient on restart. CoolTick must NEVER SQL.
local function persistPlaced(bench)
    if not bench or bench.kind ~= 'placed' or not bench.id then return end
    local mods = bench.modules
    local modsJson = nil
    if type(mods) == 'table' and next(mods) ~= nil then
        modsJson = json.encode(mods)
    end
    pcall(function()
        MySQL.update.await(
            'UPDATE sanctuary_placed_benches SET station_level = ?, modules = ?, condition_pct = ?, broken_parts = ? WHERE id = ?',
            {
                bench.stationLevel or 1,
                modsJson,
                tonumber(bench.condition) or 100,
                json.encode(bench.brokenParts or {}),
                bench.id,
            }
        )
    end)
end

function StationRuntime.Degrade(bench, recipe, batch)
    batch = math.max(1, math.floor(tonumber(batch) or 1))
    if StationRuntime.ConditionEnabled(bench) then
        local c = cfg().Condition or {}
        local d = (c.DegradePerCraft or 1.2) * batch
        if StationRuntime.HasModule(bench, 'reinforced_bench') then d = d * 0.7 end
        local durabilityMod = StationRuntime.Modifiers(bench).durability or 0
        d = d * math.max(0.4, 1 - durabilityMod)
        local prevPct = StationRuntime.GetCondition(bench)
        local pct = prevPct - d
        if pct < 0 then pct = 0 end
        local brokenStop = (c.BrokenStop) or 3
        if prevPct > brokenStop and pct <= brokenStop and CraftingCore and CraftingCore.Emit then
            CraftingCore.Emit('stationBroken', nil, bench, pct)
        end
        if bench.kind == 'placed' then
            bench.condition = pct
            -- optional broken parts
            local bp = c.BrokenParts
            if bp and bp.Enabled ~= false and pct <= (bp.Threshold or 20) then
                local chance = bp.Chance or 0.10
                if math.random() < chance then
                    local pool = bp.Pool or {}
                    local keys = {}
                    for k, _ in pairs(pool) do keys[#keys + 1] = k end
                    if #keys > 0 then
                        local pick = keys[math.random(1, #keys)]
                        bench.brokenParts = bench.brokenParts or {}
                        local exists = false
                        for i = 1, #bench.brokenParts do
                            if bench.brokenParts[i] == pick then exists = true break end
                        end
                        if not exists then bench.brokenParts[#bench.brokenParts + 1] = pick end
                    end
                end
            end
            persistPlaced(bench)
        elseif bench.kind == 'world' then
            worldCond[bench.key] = pct
        end
    end
    if StationRuntime.HeatEnabled(bench) then
        local h = cfg().Heat or {}
        local rise = (recipe and recipe.heat) or h.RisePerCraft or 8
        rise = rise * batch
        if recipe and recipe.needsVentilation and StationRuntime.GetVentilation(bench) == 0 then
            rise = rise * 1.35
        end
        local cool = 0
        if StationRuntime.HasModule(bench, 'cooling') then cool = cool + (h.CoolingModule or 12) end
        if StationRuntime.HasModule(bench, 'ventilation') then cool = cool + (h.VentilationModule or 8) end
        local temp = StationRuntime.GetTemp(bench) + rise - cool
        local ambient = h.Ambient or 20
        if temp < ambient then temp = ambient end
        if temp > 120 then temp = 120 end
        if bench.kind == 'placed' then
            bench.heat = temp
            -- heat is RAM; do not SQL on craft heat rise
        else
            worldHeat[bench.key] = { temp = temp, updated = os.time() }
        end
        if h.Particles and bench.coords then
            TriggerClientEvent('sanctuary_crafting:client:heatFx', -1, {
                x = bench.coords.x, y = bench.coords.y, z = bench.coords.z,
            }, temp)
        end
    end
end

function StationRuntime.CoolTick()
    local h = cfg().Heat
    if not h or h.Enabled ~= true then return end
    local rate = h.IdleCoolPerTick or 4
    local ambient = h.Ambient or 20
    if Benches and Benches.ForEach then
        Benches.ForEach(function(bench)
            if not StationRuntime.HeatEnabled(bench) then return end
            local t = StationRuntime.GetTemp(bench)
            if t > ambient then
                t = t - rate
                if t < ambient then t = ambient end
                if bench.kind == 'placed' then
                    bench.heat = t
                    -- CoolTick: RAM only. Heat does not survive restart (resets to ambient).
                else
                    worldHeat[bench.key] = { temp = t, updated = os.time() }
                end
            end
        end)
    end
end

function StationRuntime.CanRun(bench, recipe)
    if StationRuntime.HeatEnabled(bench) then
        local h = cfg().Heat or {}
        local pauseAt = h.PauseAt or 95
        if StationRuntime.GetTemp(bench) >= pauseAt then
            return false, 'craft_overheat'
        end
    end
    if StationRuntime.ConditionEnabled(bench) then
        local pct = StationRuntime.GetCondition(bench)
        local brokenStop = (cfg().Condition and cfg().Condition.BrokenStop) or 3
        if pct <= brokenStop then
            return false, 'craft_station_broken'
        end
    end
    return true
end

function StationRuntime.RepairCost(kind)
    local c = cfg().Condition or {}
    if kind == 'maintain' then
        return c.Maintain or { parts = { { item = 'cloth', count = 2 } }, restore = 12 }
    end
    return c.Repair or {
        parts = { { item = 'scrapmetal', count = 6 }, { item = 'metal_plate', count = 1 } },
        tools = { { item = 'WEAPON_WRENCHKNIFE', durabilityCost = 2 } },
        restore = 45,
        requireLevel = 1,
    }
end

function StationRuntime.MaintainOrRepair(src, key, kind)
    local bench = Benches.Resolve(key)
    if not bench then return false, 'craft_invalid' end
    if not StationRuntime.ConditionEnabled(bench) and kind ~= 'repair' then
        -- still allow repair of placed even if condition disabled? skip
        if not cfg().Condition or cfg().Condition.Enabled ~= true then
            return false, 'upgrade_disabled'
        end
    end
    if bench.kind == 'world' and (cfg().Condition and (cfg().Condition.WorldMode or 'skip') == 'skip') then
        return false, 'station_world_skip'
    end
    if not Validation.IsNearBench(src, bench.coords, Config.InteractDistance) then
        return false, 'craft_too_far'
    end
    if CraftingPermissions and CraftingPermissions.CanUpgradeStation then
        if bench.kind == 'placed' and not CraftingPermissions.CanUpgradeStation(src, bench) then
            return false, 'craft_denied'
        end
    end
    local spec = cfg().Condition and cfg().Condition.Repair
    if kind == 'repair' and spec then
        if spec.requireSpec and Specializations and Specializations.CanUseStation then
            local okS, reasonS, argsS = Specializations.CanUseStation(src, bench.category)
            if not okS then return false, reasonS, argsS end
        end
        if spec.requireLevel and CraftingSkills and CraftingSkills.HasRequiredLevel then
            local cat = spec.skillCategory or (SkillTree and SkillTree.StationCategory and SkillTree.StationCategory(bench.category)) or (Config.Skills and Config.Skills.defaultCategory) or 'engineer'
            -- skill check BEFORE consume
            if not CraftingSkills.HasRequiredLevel(src, cat, spec.requireLevel) then
                return false, 'craft_level_required', { spec.requireLevel }
            end
        end
    end
    local cost = StationRuntime.RepairCost(kind)
    local parts = cost.parts or {}
    if not Validation.HasIngredients(src, parts) then
        return false, 'craft_no_ingredients'
    end
    if cost.tools then
        for i = 1, #cost.tools do
            local t = cost.tools[i]
            if t.item and Tools and Tools.Has and not Tools.Has(src, t.item) then
                return false, 'craft_tool_required'
            end
        end
    end
    local okTake = CraftingMaterials.Take(src, parts)
    if not okTake then return false, 'craft_no_ingredients' end
    if cost.tools and Tools and Tools.Consume then
        for i = 1, #cost.tools do
            Tools.Consume(src, cost.tools[i])
        end
    end
    -- extra cost for broken parts
    local pool = (cfg().Condition and cfg().Condition.BrokenParts and cfg().Condition.BrokenParts.Pool) or {}
    if kind == 'repair' and bench.brokenParts then
        for i = 1, #bench.brokenParts do
            local def = pool[bench.brokenParts[i]]
            if def and def.item then
                local extra = { { item = def.item, count = def.count or 1 } }
                if Validation.HasIngredients(src, extra) then
                    CraftingMaterials.Take(src, extra)
                end
            end
        end
        bench.brokenParts = {}
    end
    local restore = cost.restore or (kind == 'repair' and 45 or 12)
    local pct = math.min(100, StationRuntime.GetCondition(bench) + restore)
    if bench.kind == 'placed' then
        bench.condition = pct
        persistPlaced(bench)
    else
        worldCond[bench.key] = pct
    end
    Benches.BroadcastSync()
    return true, pct
end

function StationRuntime.CatalogForNui(bench)
    local defs = moduleDefs()
    local installed = StationRuntime.ModuleList(bench)
    local instSet = {}
    for i = 1, #installed do instSet[installed[i]] = true end
    local out = {}
    for id, def in pairs(defs) do
        out[#out + 1] = {
            id = id,
            label = def.label or id,
            installed = instSet[id] == true,
            item = def.item,
            modifiers = def.modifiers or {},
            allow = def.allow,
        }
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

function StationRuntime.Snapshot(bench, src)
    if not bench then return {} end
    local mods = StationRuntime.ModuleList(bench)
    local queueUsed = 0
    local queueCap = bench.queueSize or ((Config.Queue and Config.Queue.MaxQueuePerPlayer) or 5)
    queueCap = queueCap + (StationRuntime.Modifiers(bench).queueSize or 0)
    if src and CraftQueue and CraftQueue.CountForBench then
        queueUsed = CraftQueue.CountForBench(src, bench.key)
    end
    local heatOn = StationRuntime.HeatEnabled(bench)
    local condOn = StationRuntime.ConditionEnabled(bench) or (cfg().Condition and cfg().Condition.Enabled == true and bench.kind == 'placed')
    return {
        level = bench.stationLevel or 1,
        maxLevel = cfg().MaxLevel or 3,
        modules = mods,
        moduleCatalog = StationRuntime.CatalogForNui(bench),
        condition = condOn and StationRuntime.GetCondition(bench) or nil,
        temp = heatOn and StationRuntime.GetTemp(bench) or nil,
        ventilation = StationRuntime.GetVentilation(bench),
        powered = (CraftingPower and CraftingPower.HasPower and CraftingPower.HasPower(bench)) or false,
        queue = queueUsed,
        queueSize = queueCap,
        efficiency = StationRuntime.EfficiencyPct(bench),
        brokenParts = bench.brokenParts or {},
        heatEnabled = heatOn,
        conditionEnabled = condOn ~= false and (cfg().Condition and cfg().Condition.Enabled == true) or false,
        canUpgrade = bench.kind == 'placed',
        canModule = bench.kind == 'placed' and not StationRuntime.WorldSkipsModules(bench),
        kind = bench.kind,
        category = bench.category,
        overheat = heatOn and StationRuntime.GetTemp(bench) >= ((cfg().Heat and cfg().Heat.OverheatAt) or 85),
    }
end

CreateThread(function()
    while true do
        Wait(15000)
        StationRuntime.CoolTick()
    end
end)
