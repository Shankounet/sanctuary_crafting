--[[
    integrations/devhub_skillTree.lua
    Seule source skill / XP / niveau — wrappers CraftingSkills autour des
    exports officiels devhub_skillTree (docs.devhub.gg 2026).
    unlockSkill n'est jamais utilisé.

    API consommateur (clés Config.SkillCategories, jamais d'UID hors Config) :
      GetLevel(src, catKey) GetXp GetTotalXp HasSkill HasRequiredLevel
      AddCraftXp(src, catKey, amount)  -- amount recette serveur uniquement
      Snapshot(src) CheckRecipeGates LevelCategoryForRecipe
]]

CraftingSkills = CraftingSkills or {}

local RESOURCE = 'devhub_skillTree'
local CACHE_TTL_MS = 8000
local warnedDown = false
local bypassNotified = {}
local cache = {} -- [src] = snapshot
local dhConfig = nil
local skillLabelIndex = nil -- [uid] = label, [categoryUid:uid] = label

local function resourceName()
    return (Config.Skills and Config.Skills.resource) or RESOURCE
end

local function nowMs()
    return GetGameTimer()
end

local function pexport(method, ...)
    local name = resourceName()
    local args = { ... }
    local ok, a, b, c = pcall(function()
        return exports[name][method](exports[name], table.unpack(args))
    end)
    if not ok then
        DebugPrint('CraftingSkills export failed', method, a)
        return false, nil
    end
    return true, a, b, c
end

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

function CraftingSkills.IsAvailable()
    if not Config.Skills or Config.Skills.enabled == false then
        return false
    end
    return GetResourceState(resourceName()) == 'started'
end

local function warnIfDown()
    if CraftingSkills.IsAvailable() then
        warnedDown = false
        return false
    end
    if not warnedDown then
        print('[CRAFT] devhub_skillTree is not started.')
        warnedDown = true
    end
    return true
end

local function indexDhConfig(cfg)
    dhConfig = cfg
    skillLabelIndex = {}
    if type(cfg) ~= 'table' then return end
    local function ingest(node, categoryUid)
        if type(node) ~= 'table' then return end
        local uid = node.uid or node.skillUid or node.id
        local label = node.label or node.name or node.title or node.Name
        local cat = node.categoryUid or node.category or categoryUid
        if type(uid) == 'string' and type(label) == 'string' and label ~= '' then
            skillLabelIndex[uid] = label
            if type(cat) == 'string' then
                skillLabelIndex[cat .. ':' .. uid] = label
            end
        end
        for k, v in pairs(node) do
            if type(v) == 'table' and k ~= 'parent' then
                ingest(v, cat)
            end
        end
    end
    ingest(cfg.SkillsList)
    ingest(cfg.SkillsCategory)
end

local function loadDhConfig()
    if not CraftingSkills.IsAvailable() then return nil end
    local ok, cfg = pexport('getConfig')
    if ok and type(cfg) == 'table' then
        indexDhConfig(cfg)
        return cfg
    end
    return nil
end

function CraftingSkills.SkillLabel(skillUid, catKey)
    if type(skillUid) ~= 'string' or skillUid == '' then return nil end
    if not skillLabelIndex then loadDhConfig() end
    if skillLabelIndex then
        local uid = SkillTree and SkillTree.CategoryUid and SkillTree.CategoryUid(catKey)
        if uid and skillLabelIndex[uid .. ':' .. skillUid] then
            return skillLabelIndex[uid .. ':' .. skillUid]
        end
        if skillLabelIndex[skillUid] then return skillLabelIndex[skillUid] end
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
    if not skillLabelIndex then loadDhConfig() end
    local uid = SkillTree and SkillTree.CategoryUid and SkillTree.CategoryUid(catKey)
    if uid and dhConfig and type(dhConfig.SkillsCategory) == 'table' then
        local list = dhConfig.SkillsCategory
        local function find(node)
            if type(node) ~= 'table' then return nil end
            if (node.uid == uid or node.categoryUid == uid) and (node.label or node.name) then
                return node.label or node.name
            end
            for _, v in pairs(node) do
                if type(v) == 'table' then
                    local hit = find(v)
                    if hit then return hit end
                end
            end
            return nil
        end
        local hit = find(list)
        if hit then return hit end
    end
    return fromCfg or catKey or ''
end

local function emptySnap(src)
    return {
        available = false,
        source = src,
        loadedAt = nowMs(),
        categories = {},
        unlocked = {},
        unlockedSet = {},
        global = { totalXp = 0, totalLevel = 0, usedPoints = 0, unlockedSkills = 0 },
    }
end

local function ingestUnlocked(snap, raw)
    snap.unlocked = {}
    snap.unlockedSet = {}
    if raw == false or raw == nil then return end
    local function add(uid, categoryUid, label)
        if type(uid) ~= 'string' or uid == '' then return end
        local catKey = SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(categoryUid) or nil
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
    if type(raw) ~= 'table' then return end
    -- array of objects
    if raw[1] ~= nil then
        for i = 1, #raw do
            local s = raw[i]
            if type(s) == 'table' then
                add(s.uid or s.skillUid or s.id, s.categoryUid or s.category, s.label or s.name)
            elseif type(s) == 'string' then
                add(s, nil, nil)
            end
        end
        return
    end
    for k, v in pairs(raw) do
        if type(k) == 'table' then
            add(k.uid or k.skillUid, k.categoryUid, k.label or k.name)
        elseif type(v) == 'table' then
            add(v.uid or v.skillUid or (type(k) == 'string' and k), v.categoryUid or v.category, v.label or v.name)
        elseif v == true and type(k) == 'string' then
            add(k, nil, nil)
        end
    end
end

local function fillCategory(snap, src, catKey)
    local uid = SkillTree.CategoryUid(catKey)
    if not uid then return end
    local cat = {
        key = catKey,
        uid = uid,
        label = CraftingSkills.CategoryLabel(catKey),
        level = 0,
        xp = 0,
        totalXp = 0,
    }
    local ok, val
    ok, val = pexport('getPlayerLevel', uid, src)
    if ok and type(val) == 'number' then cat.level = val end
    ok, val = pexport('getPlayerXp', uid, src)
    if ok and type(val) == 'number' then cat.xp = val end
    ok, val = pexport('getPlayerTotalXp', uid, src)
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
    if not skillLabelIndex then loadDhConfig() end
    local snap = emptySnap(src)
    snap.available = true
    for key, _ in pairs(Config.SkillCategories or {}) do
        fillCategory(snap, src, key)
    end
    local ok, unlocked = pexport('getUnlockedSkills', src)
    if ok then ingestUnlocked(snap, unlocked) end
    local okG, stats = pexport('getPlayerGlobalStats', src)
    if okG and type(stats) == 'table' then
        snap.global = {
            totalXp = tonumber(stats.totalXp) or 0,
            totalLevel = tonumber(stats.totalLevel) or 0,
            usedPoints = tonumber(stats.usedPoints) or 0,
            unlockedSkills = tonumber(stats.unlockedSkills) or 0,
        }
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
    -- cache miss on unlocked set: one export, then remember
    if uid then
        local ok, has = pexport('hasUnlockedSkill', uid, skillUid, src)
        if ok and has then
            snap.unlockedSet[skillUid] = true
            snap.unlockedSet[uid .. ':' .. skillUid] = true
            return true
        end
    end
    return false
end

--- DevHub has no GetTotalCategoryBonus. Kept as 0 so quality/reverse/dismantle
--- callers do not crash. Do not invent a bonus from level.
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
    local ok, _ = pexport('addXp', uid, amount, src)
    if not ok then return false end
    if Config.Skills and Config.Skills.AwardPoints == true then
        local pts = tonumber(Config.Skills.PointsPerCraft) or 0
        if pts > 0 then
            pexport('addPoints', uid, pts, src)
        end
    end
    local snap = cache[src]
    if snap and snap.categories[key] then
        local cat = snap.categories[key]
        cat.xp = (cat.xp or 0) + amount
        cat.totalXp = (cat.totalXp or 0) + amount
        -- refresh level for this category only (not a per-card spam)
        local okL, lvl = pexport('getPlayerLevel', uid, src)
        if okL and type(lvl) == 'number' then cat.level = lvl end
        local okX, xp = pexport('getPlayerXp', uid, src)
        if okX and type(xp) == 'number' then cat.xp = xp end
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

AddEventHandler('onResourceStart', function(res)
    if res == resourceName() or res == GetCurrentResourceName() then
        dhConfig = nil
        skillLabelIndex = nil
        cache = {}
        warnedDown = false
        if res == resourceName() then
            loadDhConfig()
        end
    end
end)

RegisterNetEvent('devhub_skillTree:server:listener:skillUnlocked', function(src, categoryUid, skillUid)
    src = tonumber(src) or source
    if not src or src < 1 then return end
    local snap = cache[src]
    if not snap then return end
    local catKey = SkillTree.ResolveKey(categoryUid)
    local label = CraftingSkills.SkillLabel(skillUid, catKey)
    snap.unlockedSet[skillUid] = true
    if categoryUid then snap.unlockedSet[categoryUid .. ':' .. skillUid] = true end
    if catKey then snap.unlockedSet[catKey .. ':' .. skillUid] = true end
    snap.unlocked[#snap.unlocked + 1] = {
        uid = skillUid, categoryUid = categoryUid, categoryKey = catKey, label = label,
    }
    if catKey then fillCategory(snap, src, catKey) end
    snap.loadedAt = nowMs()
    if NewlyLearned and NewlyLearned.MarkFromTalent then
        NewlyLearned.MarkFromTalent(src, skillUid)
    end
end)

RegisterNetEvent('devhub_skillTree:server:listener:skillReset', function(src, categoryUid)
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
    return { ok = true, available = snap.available == true, categories = cats, talents = talents }
end)
