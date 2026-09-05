--[[
    integrations/crafting_skills.lua
    Sole skill / XP / level source for craft + Carnet.

    Prefer sanctuary_skilltree (Phase 4). Optional DevHub fallback when
    Config.SkillSystem = 'devhub' or 'auto' and sanctuary is down.

    Public API (keys = Config.SkillCategories, never invent % / UIDs to players):
      GetLevel GetXp GetTotalXp HasSkill HasRequiredLevel
      AddCraftXp(src, catKey, amount)  -- amount from recipe only (server)
      Snapshot CheckRecipeGates FacingSkill LevelCategoryForRecipe
      SkillLabel CategoryLabel Invalidate Load IsAvailable
]]

CraftingSkills = CraftingSkills or {}

local RES_SANCTUARY = 'sanctuary_skilltree'
local RES_DEVHUB = 'devhub_skillTree'
local CACHE_TTL_MS = 8000
local warnedDown = false
local bypassNotified = {}
local cache = {} -- [src] = snapshot
local labelIndex = nil -- skill labels
local providerName = nil -- 'sanctuary' | 'devhub' | nil

local function nowMs()
    return GetGameTimer()
end

local function cfgSystem()
    local s = Config.SkillSystem
    if s == 'sanctuary' or s == 'devhub' or s == 'auto' then return s end
    return 'auto'
end

local function sanctuaryName()
    return (Config.Skills and Config.Skills.resource) or RES_SANCTUARY
end

local function devhubName()
    return (Config.Skills and Config.Skills.fallbackResource) or RES_DEVHUB
end

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

--- Resolve active backend. Prefer sanctuary unless SkillSystem forces DevHub.
---@return string|nil resourceName
---@return string|nil provider 'sanctuary'|'devhub'
local function resolveProvider()
    local mode = cfgSystem()
    local san = sanctuaryName()
    local dh = devhubName()
    if mode == 'sanctuary' then
        if started(san) then return san, 'sanctuary' end
        return nil, nil
    end
    if mode == 'devhub' then
        if started(dh) then return dh, 'devhub' end
        return nil, nil
    end
    -- auto
    if started(san) then return san, 'sanctuary' end
    if started(dh) then return dh, 'devhub' end
    return nil, nil
end

local function pexport(resource, method, ...)
    local args = { ... }
    local ok, a, b, c = pcall(function()
        return exports[resource][method](exports[resource], table.unpack(args))
    end)
    if not ok then
        DebugPrint('CraftingSkills export failed', resource, method, a)
        return false, nil
    end
    return true, a, b, c
end

--------------------------------------------------------------------------------
-- Bypass
--------------------------------------------------------------------------------

function CraftingSkills.ShouldBypassRequirements(src)
    if not Config.Skills then return false end
    if Config.Skills.BypassRequirements == true then
        return true
    end
    if not src or src < 1 then return false end
    local ace = Config.Skills.BypassAce
    if type(ace) == 'string' and ace ~= '' then
        if IsPlayerAceAllowed(src, ace) then
            return true
        end
        if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then
            return true
        end
    end
    return false
end

function CraftingSkills.NotifyBypassIfNeeded(src)
    if not src or src < 1 then return end
    if bypassNotified[src] then return end
    if not CraftingSkills.ShouldBypassRequirements(src) then return end
    local notify = (Config.Debug == true) or (Config.Skills and Config.Skills.BypassNotify == true)
    if not notify then return end
    bypassNotified[src] = true
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'inform',
        description = _('craft_skills_bypass_active'),
    })
    DebugPrint('CraftingSkills bypass active for', src)
end

function CraftingSkills.Provider()
    local _, prov = resolveProvider()
    return prov
end

function CraftingSkills.IsAvailable()
    if not Config.Skills or Config.Skills.enabled == false then
        return false
    end
    local res = resolveProvider()
    return res ~= nil
end

local function warnIfDown()
    if CraftingSkills.IsAvailable() then
        warnedDown = false
        return false
    end
    if not warnedDown then
        print('[CRAFT] sanctuary_skilltree is not started (and no DevHub fallback).')
        warnedDown = true
    end
    return true
end

--------------------------------------------------------------------------------
-- Labels (French RP — never expose UIDs to players)
--------------------------------------------------------------------------------

local function indexSanctuaryLabels(resource)
    labelIndex = {}
    local ok, cats = pexport(resource, 'getCategories')
    if not ok or type(cats) ~= 'table' then return end
    for i = 1, #cats do
        local cat = cats[i]
        if type(cat) == 'table' then
            local cuid = cat.category_uid or cat.uid or cat.id
            local clabel = cat.label or cat.name
            if type(cuid) == 'string' and type(clabel) == 'string' then
                labelIndex['cat:' .. cuid] = clabel
            end
            if type(cuid) == 'string' then
                local okS, skills = pexport(resource, 'getSkills', cuid)
                if okS and type(skills) == 'table' then
                    for j = 1, #skills do
                        local sk = skills[j]
                        if type(sk) == 'table' then
                            local suid = sk.skill_uid or sk.uid or sk.id
                            local slabel = sk.label or sk.name
                            if type(suid) == 'string' and type(slabel) == 'string' and slabel ~= '' then
                                labelIndex[suid] = slabel
                                labelIndex[cuid .. ':' .. suid] = slabel
                            end
                        end
                    end
                end
            end
        end
    end
end

local function indexDevhubLabels(resource)
    labelIndex = {}
    local ok, cfg = pexport(resource, 'getConfig')
    if not ok or type(cfg) ~= 'table' then return end
    local function ingest(node, categoryUid)
        if type(node) ~= 'table' then return end
        local uid = node.uid or node.skillUid or node.id
        local label = node.label or node.name or node.title or node.Name
        local cat = node.categoryUid or node.category or categoryUid
        if type(uid) == 'string' and type(label) == 'string' and label ~= '' then
            labelIndex[uid] = label
            if type(cat) == 'string' then
                labelIndex[cat .. ':' .. uid] = label
            end
        end
        if type(uid) == 'string' and (node.categoryUid or node.SkillsList == nil) and label then
            -- category-ish
        end
        for k, v in pairs(node) do
            if type(v) == 'table' and k ~= 'parent' then
                ingest(v, cat)
            end
        end
    end
    ingest(cfg.SkillsList)
    ingest(cfg.SkillsCategory)
    if type(cfg.SkillsCategory) == 'table' then
        local function findCats(node)
            if type(node) ~= 'table' then return end
            local cuid = node.uid or node.categoryUid
            local clabel = node.label or node.name
            if type(cuid) == 'string' and type(clabel) == 'string' then
                labelIndex['cat:' .. cuid] = clabel
            end
            for _, v in pairs(node) do
                if type(v) == 'table' then findCats(v) end
            end
        end
        findCats(cfg.SkillsCategory)
    end
end

local function loadLabelIndex()
    local res, prov = resolveProvider()
    providerName = prov
    if not res then
        labelIndex = {}
        return
    end
    if prov == 'sanctuary' then
        indexSanctuaryLabels(res)
    else
        indexDevhubLabels(res)
    end
end

function CraftingSkills.SkillLabel(skillUid, catKey)
    if type(skillUid) ~= 'string' or skillUid == '' then return nil end
    if not labelIndex then loadLabelIndex() end
    if labelIndex then
        local uid = SkillTree and SkillTree.CategoryUid and SkillTree.CategoryUid(catKey)
        if uid and labelIndex[uid .. ':' .. skillUid] then
            return labelIndex[uid .. ':' .. skillUid]
        end
        if labelIndex[skillUid] then return labelIndex[skillUid] end
    end
    -- live lookup sanctuary
    local res, prov = resolveProvider()
    if prov == 'sanctuary' and res then
        local ok, skill = pexport(res, 'getSkill', skillUid)
        if ok and type(skill) == 'table' and type(skill.label) == 'string' and skill.label ~= '' then
            if not labelIndex then labelIndex = {} end
            labelIndex[skillUid] = skill.label
            return skill.label
        end
    end
    local extra = Config.SkillLabels
    if type(extra) == 'table' and extra[skillUid] then return extra[skillUid] end
    return nil
end

function CraftingSkills.CategoryLabel(catKey)
    local fromCfg
    if SkillTree and SkillTree.CategoryLabel then
        fromCfg = SkillTree.CategoryLabel(catKey)
    end
    if fromCfg and fromCfg ~= '' and fromCfg ~= catKey then return fromCfg end
    if not labelIndex then loadLabelIndex() end
    local uid = SkillTree and SkillTree.CategoryUid and SkillTree.CategoryUid(catKey)
    if uid and labelIndex and labelIndex['cat:' .. uid] then
        return labelIndex['cat:' .. uid]
    end
    local res, prov = resolveProvider()
    if prov == 'sanctuary' and res and uid then
        local ok, cat = pexport(res, 'getCategory', uid)
        if ok and type(cat) == 'table' and type(cat.label) == 'string' and cat.label ~= '' then
            return cat.label
        end
    end
    return fromCfg or catKey or ''
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

local function emptySnap(src)
    return {
        available = false,
        provider = nil,
        source = src,
        loadedAt = nowMs(),
        categories = {},
        unlocked = {},
        unlockedSet = {},
        global = { totalXp = 0, totalLevel = 0, usedPoints = 0, unlockedSkills = 0 },
    }
end

local function ingestUnlockedEntry(snap, uid, categoryUid, label)
    if type(uid) ~= 'string' or uid == '' then return end
    local catKey = SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(categoryUid) or nil
    local setKey = (type(categoryUid) == 'string' and (categoryUid .. ':' .. uid))
        or (catKey and (catKey .. ':' .. uid))
        or uid
    if snap.unlockedSet[setKey] or snap.unlockedSet[uid] then
        snap.unlockedSet[uid] = true
        if type(categoryUid) == 'string' then snap.unlockedSet[categoryUid .. ':' .. uid] = true end
        if catKey then snap.unlockedSet[catKey .. ':' .. uid] = true end
        return
    end
    local lab = label or CraftingSkills.SkillLabel(uid, catKey)
    snap.unlocked[#snap.unlocked + 1] = {
        uid = uid,
        categoryUid = categoryUid,
        categoryKey = catKey,
        label = lab,
    }
    snap.unlockedSet[uid] = true
    if type(categoryUid) == 'string' then
        snap.unlockedSet[categoryUid .. ':' .. uid] = true
    end
    if catKey then
        snap.unlockedSet[catKey .. ':' .. uid] = true
    end
end

local function ingestUnlockedRaw(snap, raw, categoryUid)
    if raw == false or raw == nil then return end
    if type(raw) ~= 'table' then return end
    if raw[1] ~= nil then
        for i = 1, #raw do
            local s = raw[i]
            if type(s) == 'table' then
                ingestUnlockedEntry(
                    snap,
                    s.skill_uid or s.uid or s.skillUid or s.id,
                    s.category_uid or s.categoryUid or s.category or categoryUid,
                    s.label or s.name
                )
            elseif type(s) == 'string' then
                ingestUnlockedEntry(snap, s, categoryUid, nil)
            end
        end
        return
    end
    for k, v in pairs(raw) do
        if type(v) == 'table' then
            ingestUnlockedEntry(
                snap,
                v.skill_uid or v.uid or v.skillUid or (type(k) == 'string' and k),
                v.category_uid or v.categoryUid or v.category or categoryUid,
                v.label or v.name
            )
        elseif v == true and type(k) == 'string' then
            ingestUnlockedEntry(snap, k, categoryUid, nil)
        elseif type(v) == 'number' and type(k) == 'string' and v > 0 then
            -- sanctuary unlock map style skillUid -> rank
            ingestUnlockedEntry(snap, k, categoryUid, nil)
        end
    end
end

local function fillCategorySanctuary(snap, src, catKey, resource)
    local uid = SkillTree.CategoryUid(catKey)
    if not uid then return end
    local cat = {
        key = catKey,
        uid = uid,
        label = CraftingSkills.CategoryLabel(catKey),
        level = 0,
        xp = 0,
        totalXp = 0,
        points = 0,
    }
    local ok, val
    ok, val = pexport(resource, 'getPlayerLevel', src, uid)
    if ok and type(val) == 'number' then cat.level = val end
    ok, val = pexport(resource, 'getPlayerXp', src, uid)
    if ok and type(val) == 'number' then cat.xp = val end
    ok, val = pexport(resource, 'getPlayerTotalXp', src, uid)
    if ok and type(val) == 'number' then cat.totalXp = val end
    ok, val = pexport(resource, 'getPlayerPoints', src, uid)
    if ok and type(val) == 'number' then cat.points = val end
    snap.categories[catKey] = cat
end

local function fillCategoryDevhub(snap, src, catKey, resource)
    local uid = SkillTree.CategoryUid(catKey)
    if not uid then return end
    local cat = {
        key = catKey,
        uid = uid,
        label = CraftingSkills.CategoryLabel(catKey),
        level = 0,
        xp = 0,
        totalXp = 0,
        points = 0,
    }
    local ok, val
    ok, val = pexport(resource, 'getPlayerLevel', uid, src)
    if ok and type(val) == 'number' then cat.level = val end
    ok, val = pexport(resource, 'getPlayerXp', uid, src)
    if ok and type(val) == 'number' then cat.xp = val end
    ok, val = pexport(resource, 'getPlayerTotalXp', uid, src)
    if ok and type(val) == 'number' then cat.totalXp = val end
    snap.categories[catKey] = cat
end

function CraftingSkills.Invalidate(src)
    if src then cache[src] = nil end
end

function CraftingSkills.Load(src)
    if not src or src < 1 then return emptySnap(src) end
    if warnIfDown() then
        local snap = emptySnap(src)
        cache[src] = snap
        return snap
    end
    local resource, prov = resolveProvider()
    providerName = prov
    if not labelIndex then loadLabelIndex() end

    local snap = emptySnap(src)
    snap.available = true
    snap.provider = prov

    for key, _ in pairs(Config.SkillCategories or {}) do
        if prov == 'sanctuary' then
            fillCategorySanctuary(snap, src, key, resource)
        else
            fillCategoryDevhub(snap, src, key, resource)
        end
    end

    if prov == 'sanctuary' then
        local totalXp, totalLevel, usedPoints = 0, 0, 0
        for key, _ in pairs(Config.SkillCategories or {}) do
            local uid = SkillTree.CategoryUid(key)
            if uid then
                local okU, unlocked = pexport(resource, 'getUnlockedSkills', src, uid)
                if okU then ingestUnlockedRaw(snap, unlocked, uid) end
                local cat = snap.categories[key]
                if cat then
                    totalXp = totalXp + (cat.totalXp or 0)
                    totalLevel = totalLevel + (cat.level or 0)
                    usedPoints = usedPoints + (cat.points or 0)
                end
            end
        end
        -- Optional global stats (totals only — unlocks already ingested per category)
        local okG, stats = pexport(resource, 'getPlayerGlobalStats', src)
        if okG and type(stats) == 'table' then
            totalXp, totalLevel, usedPoints = 0, 0, 0
            for _, row in pairs(stats) do
                if type(row) == 'table' then
                    totalXp = totalXp + (tonumber(row.totalXp) or 0)
                    totalLevel = totalLevel + (tonumber(row.level) or 0)
                    usedPoints = usedPoints + (tonumber(row.points) or 0)
                end
            end
        end
        snap.global = {
            totalXp = totalXp,
            totalLevel = totalLevel,
            usedPoints = usedPoints,
            unlockedSkills = #(snap.unlocked or {}),
        }
    else
        local ok, unlocked = pexport(resource, 'getUnlockedSkills', src)
        if ok then ingestUnlockedRaw(snap, unlocked, nil) end
        local okG, stats = pexport(resource, 'getPlayerGlobalStats', src)
        if okG and type(stats) == 'table' then
            snap.global = {
                totalXp = tonumber(stats.totalXp) or 0,
                totalLevel = tonumber(stats.totalLevel) or 0,
                usedPoints = tonumber(stats.usedPoints) or 0,
                unlockedSkills = tonumber(stats.unlockedSkills) or 0,
            }
        end
    end

    snap.loadedAt = nowMs()
    cache[src] = snap
    return snap
end

---@param src number
---@param force boolean|nil
function CraftingSkills.Snapshot(src, force)
    if not src or src < 1 then return emptySnap(src) end
    local snap = cache[src]
    if force or not snap then
        return CraftingSkills.Load(src)
    end
    if (nowMs() - (snap.loadedAt or 0)) > CACHE_TTL_MS then
        return CraftingSkills.Load(src)
    end
    return snap
end

function CraftingSkills.LevelCategoryForRecipe(recipe)
    local g = SkillTree.RecipeGate(recipe)
    return g.category or (Config.Skills and Config.Skills.defaultCategory) or 'survival'
end

function CraftingSkills.GetLevel(src, catKey)
    if warnIfDown() then return 0 end
    local snap = CraftingSkills.Snapshot(src)
    local key = SkillTree.ResolveKey(catKey) or catKey
    local cat = snap.categories[key]
    return (cat and cat.level) or 0
end

function CraftingSkills.GetXp(src, catKey)
    if warnIfDown() then return 0 end
    local snap = CraftingSkills.Snapshot(src)
    local key = SkillTree.ResolveKey(catKey) or catKey
    local cat = snap.categories[key]
    return (cat and cat.xp) or 0
end

function CraftingSkills.GetTotalXp(src, catKey)
    if warnIfDown() then return 0 end
    local snap = CraftingSkills.Snapshot(src)
    local key = SkillTree.ResolveKey(catKey) or catKey
    local cat = snap.categories[key]
    return (cat and cat.totalXp) or 0
end

function CraftingSkills.HasRequiredLevel(src, catKey, requiredLevel)
    if not requiredLevel then return true end
    if CraftingSkills.ShouldBypassRequirements(src) then return true end
    return CraftingSkills.GetLevel(src, catKey) >= requiredLevel
end

function CraftingSkills.HasSkill(src, catKey, skillUid)
    if not skillUid then return true end
    if CraftingSkills.ShouldBypassRequirements(src) then return true end
    if warnIfDown() then return false end
    local snap = CraftingSkills.Snapshot(src)
    local key = SkillTree.ResolveKey(catKey) or catKey
    local uid = SkillTree.CategoryUid(key)
    if snap.unlockedSet[skillUid] then return true end
    if key and snap.unlockedSet[key .. ':' .. skillUid] then return true end
    if uid and snap.unlockedSet[uid .. ':' .. skillUid] then return true end

    local resource, prov = resolveProvider()
    if not resource or not uid then return false end
    local ok, has
    if prov == 'sanctuary' then
        ok, has = pexport(resource, 'hasUnlockedSkill', src, uid, skillUid)
    else
        ok, has = pexport(resource, 'hasUnlockedSkill', uid, skillUid, src)
    end
    if ok and has then
        snap.unlockedSet[skillUid] = true
        snap.unlockedSet[uid .. ':' .. skillUid] = true
        return true
    end
    return false
end

--- No GetTotalCategoryBonus on either backend. Keep 0 so quality/reverse callers do not crash.
function CraftingSkills.GetCategoryBonus(_catKey, _src)
    return 0
end

function CraftingSkills.ApplyCraftTimeBonus(baseDuration, _src)
    return baseDuration
end

--- SERVER ONLY. amount from recipe.xp / Config — never from NUI / client.
function CraftingSkills.AddCraftXp(src, catKey, amount)
    if Config.Skills and Config.Skills.BypassAlsoSkipXP
        and CraftingSkills.ShouldBypassRequirements(src) then
        return false
    end
    amount = tonumber(amount)
    if not src or src < 1 or not amount or amount <= 0 then return false end
    if warnIfDown() then return false end
    local key = SkillTree.ResolveKey(catKey) or catKey
    local uid = SkillTree.CategoryUid(key)
    if not uid then return false end
    local resource, prov = resolveProvider()
    if not resource then return false end

    local ok
    if prov == 'sanctuary' then
        ok = pexport(resource, 'addXp', src, uid, amount)
    else
        ok = pexport(resource, 'addXp', uid, amount, src)
    end
    if not ok then return false end

    if Config.Skills and Config.Skills.AwardPoints == true then
        local pts = tonumber(Config.Skills.PointsPerCraft) or 0
        if pts > 0 then
            if prov == 'sanctuary' then
                pexport(resource, 'addPoints', src, uid, pts)
            else
                pexport(resource, 'addPoints', uid, pts, src)
            end
        end
    end

    local snap = cache[src]
    if snap and snap.categories[key] then
        local cat = snap.categories[key]
        if prov == 'sanctuary' then
            local okL, lvl = pexport(resource, 'getPlayerLevel', src, uid)
            if okL and type(lvl) == 'number' then cat.level = lvl end
            local okX, xp = pexport(resource, 'getPlayerXp', src, uid)
            if okX and type(xp) == 'number' then cat.xp = xp end
            local okT, txp = pexport(resource, 'getPlayerTotalXp', src, uid)
            if okT and type(txp) == 'number' then cat.totalXp = txp end
        else
            local okL, lvl = pexport(resource, 'getPlayerLevel', uid, src)
            if okL and type(lvl) == 'number' then cat.level = lvl end
            local okX, xp = pexport(resource, 'getPlayerXp', uid, src)
            if okX and type(xp) == 'number' then cat.xp = xp end
            local okT, txp = pexport(resource, 'getPlayerTotalXp', uid, src)
            if okT and type(txp) == 'number' then cat.totalXp = txp end
        end
        snap.loadedAt = nowMs()
    end
    return true
end

function CraftingSkills.CheckRecipeGates(src, recipe)
    if not SkillTree.NeedsGate(recipe) then
        return true
    end
    if CraftingSkills.ShouldBypassRequirements(src) then
        return true
    end
    if not Config.Skills or Config.Skills.enabled == false then
        return false, 'craft_skills_unavailable'
    end
    if not CraftingSkills.IsAvailable() then
        warnIfDown()
        return false, 'craft_skills_unavailable'
    end

    local g = SkillTree.RecipeGate(recipe)
    local catKey = g.category or CraftingSkills.LevelCategoryForRecipe(recipe)

    if g.requiredLevel then
        if not CraftingSkills.HasRequiredLevel(src, catKey, g.requiredLevel) then
            local level = CraftingSkills.GetLevel(src, catKey)
            return false, 'craft_level_required', { g.requiredLevel, level }
        end
    end
    if g.requiredSkill then
        if not CraftingSkills.HasSkill(src, catKey, g.requiredSkill) then
            local label = CraftingSkills.SkillLabel(g.requiredSkill, catKey)
            if label then
                return false, 'craft_skill_required', { label }
            end
            return false, 'craft_skill_required'
        end
    end
    return true
end

function CraftingSkills.FacingSkill(src, recipe, snap)
    local g = SkillTree.RecipeGate(recipe)
    local catKey = g.category or CraftingSkills.LevelCategoryForRecipe(recipe)
    snap = snap or CraftingSkills.Snapshot(src)
    local cat = (snap.categories and snap.categories[catKey]) or {}
    local talentLabel = g.requiredSkill and CraftingSkills.SkillLabel(g.requiredSkill, catKey) or nil
    local hasRequiredSkill = nil
    if g.requiredSkill then
        hasRequiredSkill = CraftingSkills.HasSkill(src, catKey, g.requiredSkill)
    end
    return {
        category = catKey,
        categoryLabel = CraftingSkills.CategoryLabel(catKey),
        requireLevel = g.requiredLevel,
        requireSkill = g.requiredSkill,
        requiredSkillLabel = talentLabel,
        hasRequiredSkill = hasRequiredSkill,
        playerSkillLevel = cat.level or 0,
        playerSkillXp = cat.xp or 0,
        playerTotalXp = cat.totalXp or 0,
    }
end

--------------------------------------------------------------------------------
-- Lifecycle / listeners
--------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    if src then
        bypassNotified[src] = nil
        cache[src] = nil
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = type(playerId) == 'number' and playerId or source
    if src then CraftingSkills.Load(src) end
end)

local function refreshOnResource(res)
    local san, dh = sanctuaryName(), devhubName()
    if res == san or res == dh or res == GetCurrentResourceName() then
        labelIndex = nil
        cache = {}
        warnedDown = false
        providerName = nil
        if res == san or res == dh then
            loadLabelIndex()
        end
    end
end

AddEventHandler('onResourceStart', function(res)
    refreshOnResource(res)
end)

AddEventHandler('onResourceStop', function(res)
    local san, dh = sanctuaryName(), devhubName()
    if res == san or res == dh then
        labelIndex = nil
        cache = {}
        warnedDown = false
        providerName = nil
    end
end)

-- Sanctuary events
AddEventHandler('sanctuary_skilltree:server:skillUnlocked', function(src, _identifier, payload)
    src = tonumber(src)
    if not src or src < 1 then return end
    local snap = cache[src]
    if not snap then return end
    payload = type(payload) == 'table' and payload or {}
    local skillUid = payload.skillUid or payload.skill_uid
    local categoryUid = payload.categoryUid or payload.category_uid
    if type(skillUid) ~= 'string' then return end
    local catKey = SkillTree.ResolveKey(categoryUid)
    local label = CraftingSkills.SkillLabel(skillUid, catKey)
    ingestUnlockedEntry(snap, skillUid, categoryUid, label)
    if catKey then
        local resource = sanctuaryName()
        if started(resource) then
            fillCategorySanctuary(snap, src, catKey, resource)
        end
    end
    snap.loadedAt = nowMs()
    if NewlyLearned and NewlyLearned.MarkFromTalent then
        NewlyLearned.MarkFromTalent(src, skillUid)
    end
end)

AddEventHandler('sanctuary_skilltree:server:skillReset', function(src)
    src = tonumber(src)
    if src and src > 0 then CraftingSkills.Load(src) end
end)

AddEventHandler('sanctuary_skilltree:server:categoryReset', function(src)
    src = tonumber(src)
    if src and src > 0 then CraftingSkills.Load(src) end
end)

AddEventHandler('sanctuary_skilltree:server:published', function()
    labelIndex = nil
    cache = {}
end)

AddEventHandler('sanctuary_skilltree:server:ready', function()
    labelIndex = nil
    cache = {}
    warnedDown = false
    loadLabelIndex()
end)

-- DevHub listeners (fallback / transitional)
RegisterNetEvent('devhub_skillTree:server:listener:skillUnlocked', function(src, categoryUid, skillUid)
    src = tonumber(src) or source
    if not src or src < 1 then return end
    local snap = cache[src]
    if not snap then return end
    local catKey = SkillTree.ResolveKey(categoryUid)
    local label = CraftingSkills.SkillLabel(skillUid, catKey)
    ingestUnlockedEntry(snap, skillUid, categoryUid, label)
    if catKey then
        local resource = devhubName()
        if started(resource) then
            fillCategoryDevhub(snap, src, catKey, resource)
        end
    end
    snap.loadedAt = nowMs()
    if NewlyLearned and NewlyLearned.MarkFromTalent then
        NewlyLearned.MarkFromTalent(src, skillUid)
    end
end)

RegisterNetEvent('devhub_skillTree:server:listener:skillReset', function(src, _categoryUid)
    src = tonumber(src) or source
    if not src or src < 1 then return end
    CraftingSkills.Load(src)
end)

lib.callback.register('sanctuary_crafting:skillSnapshot', function(src)
    local snap = CraftingSkills.Snapshot(src)
    local cats = {}
    for key, cat in pairs(snap.categories or {}) do
        cats[key] = {
            key = key,
            label = cat.label,
            level = cat.level,
            xp = cat.xp,
            totalXp = cat.totalXp,
        }
    end
    local talents = {}
    for i = 1, #(snap.unlocked or {}) do
        local u = snap.unlocked[i]
        if u.label then
            talents[#talents + 1] = { label = u.label, category = u.categoryKey }
        end
    end
    return {
        ok = true,
        available = snap.available == true,
        provider = snap.provider,
        categories = cats,
        talents = talents,
    }
end)
