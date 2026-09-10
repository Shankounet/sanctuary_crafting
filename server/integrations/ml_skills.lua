--[[
    server/integrations/ml_skills.lua
    Central bridge: ml_skills = SOLE unlock / XP / level provider for craft.

    Official signatures (DO NOT invert):
      exports.ml_skills:HasUnlockedSkill(categoryUid, skillUid, source)
      exports.ml_skills:AddXp(categoryUid, amount, source)
      exports.ml_skills:OpenSkillTree(categoryUid)  -- client only
      Client HasUnlockedSkill(categoryUid, skillUid) — feedback; nil GetPlayerData → loading

    ALL craft unlock checks go through Skills.* with pcall. Never scatter raw exports.
]]

Skills = Skills or {}

local RES = 'ml_skills'
local UnlockedCache = {} -- [src] = { unlocked = { ['cat:uid']=true }, levels = { [catKey]=n }, loadedAt, available, loading }
local labelIndex = nil
-- Published ml_skills tree is the recipe-gate SoT: recipeId -> real skill/category UID.
-- publishedSkillByUid: skillUid -> list of { categoryUid, skillUid, label } from published nodes.
local recipeSkillIndex = nil
local publishedSkillByUid = nil
local publishedByNormLabel = nil -- norm(label) -> { categoryUid, skillUid, label } (unique only)
local recipeIndexLoaded = false
local publishedCategoryUids = {} -- exact ml_skills category UIDs; beat legacy aliases
local warnedDown = false
local bypassNotified = {}

local function nowMs()
    return GetGameTimer()
end

local function integ()
    return Config.SkillIntegration or {}
end

local function skillsCfg()
    return Config.Skills or {}
end

local function resourceName()
    return skillsCfg().resource or integ().provider or RES
end

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function failClosed()
    local v = integ().failClosed
    if v == nil then return true end
    return v == true
end

local function cacheEnabled()
    local v = integ().cache
    if v == nil then return true end
    return v == true
end

local function integrationEnabled()
    if integ().enabled == false then return false end
    if skillsCfg().enabled == false then return false end
    return true
end

--- Soft pcall around ml_skills export. Never throws into craft path.
local function pexport(method, ...)
    local res = resourceName()
    if not started(res) then return false, nil end
    local args = { ... }
    local ok, a, b, c = pcall(function()
        return exports[res][method](exports[res], table.unpack(args))
    end)
    if not ok then
        DebugPrint('Skills export failed', res, method, a)
        return false, nil
    end
    return true, a, b, c
end

local function resolveCategoryUid(catKeyOrUid)
    if type(catKeyOrUid) ~= 'string' or catKeyOrUid == '' then return nil end
    -- Published UID is authoritative. Never rewrite `agriculture` to legacy `survival`.
    if publishedCategoryUids[catKeyOrUid] then return catKeyOrUid end
    if SkillTree and SkillTree.CategoryUid then
        local uid = SkillTree.CategoryUid(catKeyOrUid)
        if uid then return uid end
    end
    local map = integ().CategoryMapping
    if type(map) == 'table' and map[catKeyOrUid] then
        return map[catKeyOrUid]
    end
    -- already a published UID
    return catKeyOrUid
end

local function cacheKey(categoryUid, skillUid)
    return tostring(categoryUid or '') .. ':' .. tostring(skillUid or '')
end

--------------------------------------------------------------------------------
-- Availability
--------------------------------------------------------------------------------

function Skills.IsAvailable()
    if not integrationEnabled() then return false end
    return started(resourceName())
end

function Skills.Provider()
    if Skills.IsAvailable() then return 'ml_skills' end
    return nil
end

local function warnIfDown()
    if Skills.IsAvailable() then
        warnedDown = false
        return false
    end
    if not warnedDown then
        print('[CRAFT] ml_skills is not started — skill-gated recipes stay locked (failClosed).')
        warnedDown = true
    end
    return true
end

--------------------------------------------------------------------------------
-- Bypass (labs / ACE) — unchanged semantics from Config.Skills
--------------------------------------------------------------------------------

function Skills.ShouldBypassRequirements(src)
    local cfg = skillsCfg()
    if cfg.BypassRequirements == true then return true end
    if not src or src < 1 then return false end
    local ace = cfg.BypassAce
    if type(ace) == 'string' and ace ~= '' then
        if IsPlayerAceAllowed(src, ace) then return true end
        if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then return true end
    end
    return false
end

function Skills.NotifyBypassIfNeeded(src)
    if not src or src < 1 then return end
    if bypassNotified[src] then return end
    if not Skills.ShouldBypassRequirements(src) then return end
    local notify = (DebugEnabled and DebugEnabled() or false) or (skillsCfg().BypassNotify == true)
    if not notify then return end
    bypassNotified[src] = true
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'inform',
        description = _('craft_skills_bypass_active'),
    })
end

--------------------------------------------------------------------------------
-- Labels (human — never expose UIDs to players)
--------------------------------------------------------------------------------

local function decodeMeta(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or {}
end


--- Normalize labels for fuzzy recipe↔node matching (FR/EN, accents, spaces).
---@param s string|nil
---@return string
local function normLabel(s)
    if type(s) ~= 'string' or s == '' then return '' end
    local out = s:lower()
    local accents = {
        ['à']='a',['á']='a',['â']='a',['ä']='a',['ã']='a',
        ['è']='e',['é']='e',['ê']='e',['ë']='e',
        ['ì']='i',['í']='i',['î']='i',['ï']='i',
        ['ò']='o',['ó']='o',['ô']='o',['ö']='o',
        ['ù']='u',['ú']='u',['û']='u',['ü']='u',
        ['ç']='c',['ñ']='n',['ÿ']='y',
    }
    out = out:gsub('[àáâäãèéêëìíîïòóôöùúûüçñÿ]', function(c) return accents[c] or c end)
    out = out:gsub('[^%w]+', '')
    return out
end
Skills._NormLabel = normLabel

local function itemLabelOf(item)
    if type(item) ~= 'string' or item == '' then return nil end
    if GetResourceState and GetResourceState('ox_inventory') == 'started' then
        local ok, def = pcall(function()
            return exports.ox_inventory:Items(item)
        end)
        if ok and type(def) == 'table' and type(def.label) == 'string' and def.label ~= '' then
            return def.label
        end
    end
    return nil
end

--- After trees (+ optionally recipes) are known, link recipes by label / result item.
---@return number linked
local function linkRecipesByPublishedLabels()
    if not recipeIndexLoaded or type(publishedByNormLabel) ~= 'table' then return 0 end
    local recipes = Config.RecipeById or Config.Recipes
    if type(recipes) ~= 'table' then return 0 end
    local list
    if recipes[1] ~= nil then
        list = recipes
    else
        list = {}
        for _, r in pairs(recipes) do list[#list + 1] = r end
    end
    local linked = 0
    for i = 1, #list do
        local r = list[i]
        if type(r) == 'table' and type(r.id) == 'string' and r.id ~= '' and not (recipeSkillIndex and recipeSkillIndex[r.id]) then
            local candidates = {}
            local function pushCand(s)
                if type(s) == 'string' and s ~= '' then candidates[#candidates + 1] = s end
            end
            pushCand(r.label)
            pushCand(r.name)
            local item = r.result and (r.result.item or r.result.name) or r.item
            if type(item) == 'string' then
                pushCand(item)
                pushCand(item:gsub('_', ' '))
                pushCand(itemLabelOf(item))
                -- craft_<item> already handled via id if equal
            end
            local matched = nil
            for ci = 1, #candidates do
                local nk = normLabel(candidates[ci])
                local pub = nk ~= '' and publishedByNormLabel[nk] or nil
                if type(pub) == 'table' then
                    matched = pub
                    break
                end
            end
            -- Also: result item craft id / item id equals a published skill uid
            if not matched and type(item) == 'string' and publishedSkillByUid then
                local bucket = publishedSkillByUid[item] or publishedSkillByUid['craft_' .. item]
                if type(bucket) == 'table' and #bucket == 1 then
                    matched = bucket[1]
                end
            end
            if matched then
                recipeSkillIndex[r.id] = {
                    recipeId = r.id,
                    categoryUid = matched.categoryUid,
                    skillUid = matched.skillUid,
                    label = matched.label,
                }
                linked = linked + 1
            end
        end
    end
    return linked
end

local function loadLabelIndex()
    labelIndex = {}
    recipeSkillIndex = {}
    publishedSkillByUid = {}
    publishedByNormLabel = {}
    recipeIndexLoaded = false
    publishedCategoryUids = {}
    local res = resourceName()
    if not started(res) then return end
    -- Prefer GetSkillTrees / GetConfig (official admin/tree surface)
    local ok, trees = pexport('GetSkillTrees')
    if not ok or type(trees) ~= 'table' then
        ok, trees = pexport('GetConfig')
    end
    if not ok or type(trees) ~= 'table' then return end

    local function ingestSkill(catUid, sk)
        if type(sk) ~= 'table' then return end
        local suid = sk.skillUid or sk.skill_uid or sk.uid or sk.id
        local slabel = sk.label or sk.name or sk.title
        if type(suid) == 'string' and type(slabel) == 'string' and slabel ~= '' then
            labelIndex[suid] = slabel
            if type(catUid) == 'string' then
                labelIndex[catUid .. ':' .. suid] = slabel
            end
        end
        if type(suid) ~= 'string' or suid == '' or type(catUid) ~= 'string' or catUid == '' then
            return
        end

        -- Track every published skill uid so legacy recipe.requireSkill can resolve
        -- only when that uid actually exists in the live tree (never invent orphan skill_N).
        local bucket = publishedSkillByUid[suid]
        if not bucket then
            bucket = {}
            publishedSkillByUid[suid] = bucket
        end
        bucket[#bucket + 1] = {
            categoryUid = catUid,
            skillUid = suid,
            label = slabel,
        }

        -- Same published node convention as the tree editor: recipeId / recipeIds in meta.
        local meta = decodeMeta(sk.meta or sk.metadata or sk.meta_json)
        local seen = {}
        local function link(recipeId)
            if type(recipeId) ~= 'string' or recipeId == '' or seen[recipeId] then return end
            seen[recipeId] = true
            -- First published node wins deterministically if an admin linked a recipe twice.
            if not recipeSkillIndex[recipeId] then
                recipeSkillIndex[recipeId] = {
                    recipeId = recipeId,
                    categoryUid = catUid,
                    skillUid = suid,
                    label = slabel,
                }
            end
        end
        link(meta.recipeId or meta.recipe_id or sk.recipeId or sk.recipe_id)
        local data = type(sk.data) == 'table' and sk.data or meta
        if type(data) == 'table' then
            link(data.recipeId or data.recipe_id or data.craftId or data.craft_id)
            link(data.unlockRecipe or data.unlock_recipe)
        end
        local effect = sk.effect or meta.effect
        if type(effect) == 'table' then
            link(effect.recipeId or effect.recipe_id or effect.craftId)
        end
        local ids = meta.recipeIds or meta.recipe_ids or sk.recipeIds or sk.recipe_ids
        if type(ids) == 'table' then
            for i = 1, #ids do link(ids[i]) end
        end
        -- Secondary safe links when the node uid itself is a recipe id / result item name.
        if suid:find('^craft_', 1, false) or suid:find('^recipe_', 1, false) then
            link(suid)
        end
        local resultItem = meta.resultItem or meta.result_item or meta.item or sk.resultItem or sk.item
        if type(resultItem) == 'string' and resultItem ~= '' then
            local byId = Config.RecipeById
            if type(byId) == 'table' then
                if byId[resultItem] then link(resultItem) end
                local craftId = 'craft_' .. resultItem
                if byId[craftId] then link(craftId) end
            end
        end
        -- Unique normalized label → skill (for later recipe matching).
        if type(slabel) == 'string' and slabel ~= '' then
            local nk = Skills._NormLabel and Skills._NormLabel(slabel) or nil
            if nk and nk ~= '' then
                local prev = publishedByNormLabel[nk]
                if prev == nil then
                    publishedByNormLabel[nk] = {
                        categoryUid = catUid,
                        skillUid = suid,
                        label = slabel,
                    }
                elseif prev ~= false and (prev.skillUid ~= suid or prev.categoryUid ~= catUid) then
                    publishedByNormLabel[nk] = false -- ambiguous
                end
            end
        end
    end

    local function ingestCategory(cat)
        if type(cat) ~= 'table' then return end
        local cuid = cat.categoryUid or cat.category_uid or cat.uid or cat.id
        local clabel = cat.label or cat.name
        if type(cuid) == 'string' and cuid ~= '' then
            publishedCategoryUids[cuid] = true
            if type(clabel) == 'string' then labelIndex['cat:' .. cuid] = clabel end
        end
        local skillBags = { cat.skills, cat.Skills, cat.nodes, cat.talents, cat.children, cat.Children }
        for bi = 1, #skillBags do
            local skills = skillBags[bi]
            if type(skills) == 'table' then
                if skills[1] ~= nil then
                    for i = 1, #skills do
                        local sk = skills[i]
                        if type(sk) == 'table' then
                            if sk.skills or sk.Skills or sk.nodes or sk.children then
                                ingestCategory(sk)
                            end
                            ingestSkill(cuid, sk)
                        end
                    end
                else
                    for _, sk in pairs(skills) do
                        if type(sk) == 'table' then
                            if sk.skills or sk.Skills or sk.nodes or sk.children then
                                ingestCategory(sk)
                            end
                            ingestSkill(cuid, sk)
                        end
                    end
                end
            end
        end
        -- nested trees / loose node tables
        for k, v in pairs(cat) do
            if type(v) == 'table' and k ~= 'skills' and k ~= 'Skills' and k ~= 'nodes' and k ~= 'talents'
                and k ~= 'children' and k ~= 'Children' and k ~= 'parent' and k ~= 'meta' then
                if v.uid or v.skillUid or v.skill_uid or v.id then
                    ingestSkill(cuid, v)
                end
                if v.categoryUid or v.skills or v.Skills or v.nodes or v.children then
                    ingestCategory(v)
                end
            end
        end
    end

    if trees[1] ~= nil then
        for i = 1, #trees do ingestCategory(trees[i]) end
    elseif trees.categories or trees.Categories then
        local cats = trees.categories or trees.Categories
        if cats[1] ~= nil then
            for i = 1, #cats do ingestCategory(cats[i]) end
        else
            for _, cat in pairs(cats) do ingestCategory(cat) end
        end
    else
        for _, cat in pairs(trees) do
            if type(cat) == 'table' then ingestCategory(cat) end
        end
    end

    -- also index Config.SkillCategories labels
    for key, def in pairs(Config.SkillCategories or {}) do
        if def and def.categoryUid and def.label then
            labelIndex['cat:' .. def.categoryUid] = def.label
            labelIndex['catkey:' .. key] = def.label
        end
    end
    recipeIndexLoaded = true
    local nLabelLinks = linkRecipesByPublishedLabels()
    if nLabelLinks > 0 then
        print(('[CRAFT] ML SKILLS: linked %d recipe(s) via published node label/item'):format(nLabelLinks))
    end
    if skillsCfg().BypassRequirements == true then
        print('[CRAFT] WARNING: Config.Skills.BypassRequirements=true — ALL skill gates skipped for every player (labs only)')
    end
end

--- Public: re-run label/item linking once RecipeById is warm (boot / overlay).
function Skills.RebuildRecipeGateLinks()
    if recipeSkillIndex == nil or publishedSkillByUid == nil then
        loadLabelIndex()
        return
    end
    if not recipeIndexLoaded then return end
    local n = linkRecipesByPublishedLabels()
    if n > 0 then
        print(('[CRAFT] ML SKILLS: rebuilt %d recipe gate(s) via label/item'):format(n))
    end
end

function Skills.SkillLabel(skillUid, catKey)
    if type(skillUid) ~= 'string' or skillUid == '' then return nil end
    if not labelIndex then loadLabelIndex() end
    if type(catKey) == 'string' and labelIndex and labelIndex[catKey .. ':' .. skillUid] then
        return labelIndex[catKey .. ':' .. skillUid]
    end
    local cuid = resolveCategoryUid(catKey)
    if cuid and labelIndex and labelIndex[cuid .. ':' .. skillUid] then
        return labelIndex[cuid .. ':' .. skillUid]
    end
    if labelIndex and labelIndex[skillUid] then return labelIndex[skillUid] end
    local extra = Config.SkillLabels
    if type(extra) == 'table' and extra[skillUid] then return extra[skillUid] end
    return nil
end

function Skills.CategoryLabel(catKey)
    if not labelIndex then loadLabelIndex() end
    -- Exact published ml_skills category label beats legacy SkillLegacyMap aliases.
    if type(catKey) == 'string' and labelIndex and labelIndex['cat:' .. catKey] then
        return labelIndex['cat:' .. catKey]
    end
    local cuid = resolveCategoryUid(catKey)
    if cuid and labelIndex and labelIndex['cat:' .. cuid] then
        return labelIndex['cat:' .. cuid]
    end
    if SkillTree and SkillTree.CategoryLabel then
        local fromCfg = SkillTree.CategoryLabel(catKey)
        if fromCfg and fromCfg ~= '' and fromCfg ~= catKey then return fromCfg end
    end
    return catKey or ''
end

--- Admin: trees for pickers (editor open / refresh only — not every frame)
function Skills.GetSkillTrees()
    if not Skills.IsAvailable() then return nil end
    local ok, trees = pexport('GetSkillTrees')
    if ok and type(trees) == 'table' then return trees end
    ok, trees = pexport('GetConfig')
    if ok and type(trees) == 'table' then return trees end
    return nil
end

function Skills.RefreshLabels()
    labelIndex = nil
    recipeSkillIndex = nil
    publishedSkillByUid = nil
    publishedByNormLabel = nil
    recipeIndexLoaded = false
    loadLabelIndex()
    return labelIndex ~= nil and recipeIndexLoaded == true
end

--------------------------------------------------------------------------------
-- Cache (per-player unlocked + levels)
--------------------------------------------------------------------------------

local function emptyCache(src)
    return {
        available = false,
        loading = true,
        source = src,
        loadedAt = nowMs(),
        unlocked = {}, -- set keyed categoryUid:skillUid
        levels = {},   -- keyed by SkillCategories KEY and categoryUid
        list = {},     -- array of { uid, categoryUid, label }
    }
end

local function ingestUnlocked(entry, categoryUid, skillUid, label)
    if type(skillUid) ~= 'string' or skillUid == '' then return end
    local catUid = categoryUid
    if type(catUid) ~= 'string' or catUid == '' then
        catUid = resolveCategoryUid(categoryUid) or ''
    else
        -- always store under published categoryUid, never bare skillUid / category KEY
        catUid = resolveCategoryUid(catUid) or catUid
    end
    if catUid == '' then return end -- refuse category-less positives (fail closed)
    local key = cacheKey(catUid, skillUid)
    if entry.unlocked[key] then
        return -- already recorded
    end
    entry.unlocked[key] = true
    local catKey = SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(catUid) or nil
    local lab = label or Skills.SkillLabel(skillUid, catKey or catUid)
    entry.list[#entry.list + 1] = {
        uid = skillUid,
        categoryUid = catUid,
        categoryKey = catKey,
        label = lab,
    }
end

local function isExplicitlyLocked(obj)
    if type(obj) ~= 'table' then return false end
    if obj.unlocked == false or obj.isUnlocked == false or obj.hasUnlocked == false then return true end
    if obj.locked == true or obj.isLocked == true or obj.verrouille == true then return true end
    if obj.learned == false or obj.isLearned == false then return true end
    return false
end

local function ingestUnlockedRaw(entry, raw, categoryUid)
    if raw == false or raw == nil then return end
    if type(raw) ~= 'table' then return end
    -- GetUnlockedSkills contract: returns unlocked skills only. If an object carries an
    -- explicit locked/unlocked=false flag, never treat it as unlocked (no category-wide true).
    if raw[1] ~= nil then
        for i = 1, #raw do
            local s = raw[i]
            if type(s) == 'table' then
                if not isExplicitlyLocked(s) then
                    local flag = s.unlocked
                    if flag == nil or flag == true then
                        ingestUnlocked(
                            entry,
                            s.categoryUid or s.category_uid or s.category or categoryUid,
                            s.skillUid or s.skill_uid or s.uid or s.id,
                            s.label or s.name
                        )
                    end
                end
            elseif type(s) == 'string' then
                ingestUnlocked(entry, categoryUid, s, nil)
            end
        end
        return
    end
    for k, v in pairs(raw) do
        if type(v) == 'table' then
            if not isExplicitlyLocked(v) then
                local flag = v.unlocked
                if flag == nil or flag == true then
                    ingestUnlocked(
                        entry,
                        v.categoryUid or v.category_uid or v.category or categoryUid,
                        v.skillUid or v.skill_uid or v.uid or (type(k) == 'string' and k) or nil,
                        v.label or v.name
                    )
                end
            end
        elseif v == true and type(k) == 'string' then
            ingestUnlocked(entry, categoryUid, k, nil)
        elseif type(v) == 'number' and type(k) == 'string' and v > 0 then
            ingestUnlocked(entry, categoryUid, k, nil)
        end
    end
end

function Skills.GetUnlockedSkills(src, categoryUid)
    if not Skills.IsAvailable() then return nil end
    local ok, raw
    if categoryUid then
        ok, raw = pexport('GetUnlockedSkills', categoryUid, src)
        if not ok or raw == nil then
            ok, raw = pexport('GetUnlockedSkills', src, categoryUid)
        end
    else
        ok, raw = pexport('GetUnlockedSkills', src)
    end
    if not ok then return nil end
    return raw
end

local function fetchLevel(src, catKey)
    local cuid = resolveCategoryUid(catKey)
    if not cuid then return 0 end
    local ok, level = pexport('GetPlayerLevel', cuid, src)
    if ok and type(level) == 'number' then return level end
    -- some builds expose GetLevel
    ok, level = pexport('GetLevel', cuid, src)
    if ok and type(level) == 'number' then return level end
    return 0
end

function Skills.RebuildCache(src)
    if not src or src < 1 then return emptyCache(src) end
    local entry = emptyCache(src)
    if warnIfDown() then
        entry.available = false
        entry.loading = false
        if cacheEnabled() then UnlockedCache[src] = entry end
        return entry
    end
    if not labelIndex then loadLabelIndex() end
    entry.available = true
    entry.loading = false

    -- Per configured category
    for key, def in pairs(Config.SkillCategories or {}) do
        local cuid = def and def.categoryUid or key
        local lvl = fetchLevel(src, key)
        entry.levels[key] = lvl
        if type(cuid) == 'string' then entry.levels[cuid] = lvl end
        local raw = Skills.GetUnlockedSkills(src, cuid)
        if raw then ingestUnlockedRaw(entry, raw, cuid) end
    end

    -- Published categories not represented in legacy Config.SkillCategories (e.g. agriculture).
    for cuid in pairs(publishedCategoryUids) do
        if entry.levels[cuid] == nil then
            entry.levels[cuid] = fetchLevel(src, cuid)
            local raw = Skills.GetUnlockedSkills(src, cuid)
            if raw then ingestUnlockedRaw(entry, raw, cuid) end
        end
    end

    -- Global unlocked dump if available
    local all = Skills.GetUnlockedSkills(src, nil)
    if all then ingestUnlockedRaw(entry, all, nil) end

    entry.loadedAt = nowMs()
    if cacheEnabled() then UnlockedCache[src] = entry end
    return entry
end

function Skills.GetCache(src)
    if not src or src < 1 then return emptyCache(src) end
    if not cacheEnabled() then return Skills.RebuildCache(src) end
    local entry = UnlockedCache[src]
    if not entry then return Skills.RebuildCache(src) end
    return entry
end

function Skills.Invalidate(src)
    if src then UnlockedCache[src] = nil end
end

function Skills.ClearCache(src)
    if src then
        UnlockedCache[src] = nil
        bypassNotified[src] = nil
    else
        UnlockedCache = {}
        bypassNotified = {}
    end
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

function Skills.GetLevel(src, catKey)
    if warnIfDown() then return 0 end
    local key = publishedCategoryUids[catKey] and catKey
        or ((SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(catKey)) or catKey)
    local entry = Skills.GetCache(src)
    if entry.levels[key] ~= nil then return entry.levels[key] end
    local cuid = resolveCategoryUid(catKey)
    if cuid and entry.levels[cuid] ~= nil then return entry.levels[cuid] end
    local lvl = fetchLevel(src, key or catKey)
    if key then entry.levels[key] = lvl end
    if cuid then entry.levels[cuid] = lvl end
    return lvl
end

function Skills.HasUnlockedSkill(src, categoryUidOrKey, skillUid)
    -- Fail closed: missing skillUid is NOT a free pass for gated display (callers must omit check).
    if type(skillUid) ~= 'string' or skillUid == '' then return false end
    if Skills.ShouldBypassRequirements(src) then return true end
    if warnIfDown() then return false end
    local cuid = resolveCategoryUid(categoryUidOrKey)
    if type(cuid) ~= 'string' or cuid == '' then
        return false
    end
    local entry = Skills.GetCache(src)
    local key = cacheKey(cuid, skillUid)
    -- Cache keys are ONLY categoryUid:skillUid (never bare skillUid / category-wide).
    if entry.unlocked[key] == true then
        return true
    end

    -- Official export ONLY: HasUnlockedSkill(categoryUid, skillUid, source). Strict boolean.
    local ok, has = pexport('HasUnlockedSkill', cuid, skillUid, src)
    if not ok then
        return false -- pcall error → fail closed
    end
    if has == true then
        ingestUnlocked(entry, cuid, skillUid, nil)
        return true
    end
    -- Heal stale positive if live says not unlocked
    if entry.unlocked[key] then
        entry.unlocked[key] = nil
    end
    return false
end

--- requirement = { category, uid, level? } or legacy string skill uid + category
function Skills.HasUnlockedRecipeSkill(src, requirement)
    if requirement == nil then return true end
    if Skills.ShouldBypassRequirements(src) then return true end
    if not Skills.IsAvailable() then
        return failClosed() and false or true
    end

    local category, uid, level
    if type(requirement) == 'string' then
        uid = requirement
        category = skillsCfg().defaultCategory or 'survival'
    elseif type(requirement) == 'table' then
        category = requirement.category or requirement.cat or requirement.categoryUid
        uid = requirement.uid or requirement.skillUid or requirement.skill or requirement.requiredSkill
        level = requirement.level or requirement.requiredLevel or requirement.requireLevel
    else
        return true
    end

    if level then
        local cur = Skills.GetLevel(src, category)
        if cur < tonumber(level) then
            return false, 'skill_level_low', { tonumber(level), cur, category }
        end
    end
    if type(uid) == 'string' and uid ~= '' then
        if Skills.HasUnlockedSkill(src, category, uid) ~= true then
            local label = Skills.SkillLabel(uid, category)
            return false, 'skill_locked', { label or uid, uid, resolveCategoryUid(category) }
        end
    end
    return true
end

function Skills.AddXp(src, categoryUidOrKey, amount)
    if skillsCfg().BypassAlsoSkipXP and Skills.ShouldBypassRequirements(src) then
        return false
    end
    amount = tonumber(amount)
    if not src or src < 1 or not amount or amount <= 0 then return false end
    if warnIfDown() then return false end
    local cuid = resolveCategoryUid(categoryUidOrKey)
    if not cuid then return false end
    local ok, granted = pexport('AddXp', cuid, amount, src)
    if not ok then return false end
    -- refresh level cache after our AddXp
    local key = (SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(categoryUidOrKey)) or categoryUidOrKey
    local entry = UnlockedCache[src]
    if entry then
        local lvl = fetchLevel(src, key)
        if key then entry.levels[key] = lvl end
        entry.levels[cuid] = lvl
        entry.loadedAt = nowMs()
    end
    return granted ~= false
end

--------------------------------------------------------------------------------
-- Recipe requirement parsing (canonical) — normalize at DATA SOURCE
--------------------------------------------------------------------------------

local function skillDebugEnabled()
    return integ().debug == true or (DebugEnabled and DebugEnabled() or false)
end

local function skillDebugLog(...)
    if not skillDebugEnabled() then return end
    local parts = { '[CRAFT][SkillIntegration]' }
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print(table.concat(parts, ' '))
end

--- Dedupe key: provider:categoryUid:skillUid (NEVER label alone).
local function skillReqDedupeKey(provider, categoryUid, skillUid)
    return tostring(provider or 'ml_skills')
        .. ':'
        .. tostring(categoryUid or '')
        .. ':'
        .. tostring(skillUid or '')
end

--- Canonical unique skill requirement list for gates + NUI.
--- Returns nil | { mode, skills=[{provider,category,categoryUid,categoryKey,uid,skillUid,label,level,unlocked?}], visibility, xp, rawCount, normalizedCount, duplicatesRemoved }

--- Resolve a skillUid against published ml_skills nodes only.
---@param skillUid string
---@param preferredCat string|nil category key or uid from the recipe
---@return table|nil { categoryUid, skillUid, label }
local function resolvePublishedSkill(skillUid, preferredCat)
    if type(skillUid) ~= 'string' or skillUid == '' then return nil end
    if publishedSkillByUid == nil then loadLabelIndex() end
    local bucket = publishedSkillByUid and publishedSkillByUid[skillUid]
    if type(bucket) ~= 'table' or #bucket == 0 then return nil end

    local preferredUid = nil
    if type(preferredCat) == 'string' and preferredCat ~= '' then
        preferredUid = resolveCategoryUid(preferredCat) or preferredCat
        -- Exact published category uid beats legacy aliases.
        if publishedCategoryUids and publishedCategoryUids[preferredCat] then
            preferredUid = preferredCat
        end
    end

    if preferredUid or preferredCat then
        for i = 1, #bucket do
            local row = bucket[i]
            if row.categoryUid == preferredUid or row.categoryUid == preferredCat then
                return row
            end
        end
        -- Legacy maps often alias agriculture→survival; if the uid exists only once
        -- in the published tree, still bind it rather than freeing the craft.
        if #bucket == 1 then return bucket[1] end
        return nil
    end
    if #bucket == 1 then return bucket[1] end
    return nil
end

--- Collect legacy skill refs from recipe fields (requireSkill / requiredSkill / …).
--- Used only to probe publishedSkillByUid — never invents a gate for orphans.
---@param recipe table
---@return { uid: string, cat: string|nil }[]
local function collectLegacySkillRefs(recipe)
    local out, seen = {}, {}
    local function push(uid, cat)
        if type(uid) ~= 'string' or uid == '' then return end
        local key = tostring(cat or '') .. ':' .. uid
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { uid = uid, cat = cat }
    end

    local defCat = recipe.requireSkillCategory or recipe.skillCategory
        or (recipe.xp and recipe.xp.category) or nil

    if type(recipe.requireSkill) == 'string' then
        push(recipe.requireSkill, defCat)
    elseif type(recipe.requireSkill) == 'table' then
        push(recipe.requireSkill.uid or recipe.requireSkill.skillUid or recipe.requireSkill.skill,
            recipe.requireSkill.category or recipe.requireSkill.categoryUid or defCat)
    end

    if type(recipe.requiredSkill) == 'string' then
        push(recipe.requiredSkill, defCat)
    elseif type(recipe.requiredSkill) == 'table' then
        push(recipe.requiredSkill.uid or recipe.requiredSkill.skillUid or recipe.requiredSkill.skill,
            recipe.requiredSkill.category or recipe.requiredSkill.categoryUid or defCat)
    end

    local rs = recipe.requiredSkills
    if type(rs) == 'table' then
        local list = rs.skills or rs
        if type(list) == 'table' then
            if list[1] ~= nil then
                for i = 1, #list do
                    local sk = list[i]
                    if type(sk) == 'string' then
                        push(sk, defCat)
                    elseif type(sk) == 'table' then
                        push(sk.uid or sk.skillUid or sk.skill, sk.category or sk.categoryUid or defCat)
                    end
                end
            end
        end
    end

    local st = recipe.skillTree
    if type(st) == 'table' then
        local uid = st.requiredSkill or st.skillUid or st.uid
        local cat = st.category or st.categoryUid or defCat
        if type(uid) == 'string' then push(uid, cat) end
    end

    return out
end

function Skills.normalizeSkillRequirements(recipe, src)
    if type(recipe) ~= 'table' then
        return nil
    end

    local provider = 'ml_skills'
    local visibility = recipe.skillVisibility
        or (recipe.hideIfSkillLocked and 'hidden_until_unlocked')
        or 'visible_locked'
    if visibility == 'mystery' then visibility = 'mystery_until_unlocked' end
    if visibility == 'discovered' then visibility = 'discovered_locked' end

    if recipeSkillIndex == nil then loadLabelIndex() end
    local linked = recipe.id and recipeSkillIndex and recipeSkillIndex[recipe.id] or nil
    if linked then
        local catUid = linked.categoryUid
        -- Keep the exact published UID. Legacy aliases are only for old recipe config.
        local catKey = catUid
        local skillUid = linked.skillUid
        local row = {
            provider = 'ml_skills',
            category = catKey,
            categoryKey = catKey,
            categoryUid = catUid,
            uid = skillUid,
            skillUid = skillUid,
            label = linked.label or Skills.SkillLabel(skillUid, catUid),
            source = 'ml_skills_tree',
        }
        if src then
            row.unlocked = Skills.HasUnlockedSkill(src, catUid, skillUid) == true
        end
        return {
            mode = 'all',
            skills = { row },
            visibility = visibility,
            xp = recipe.skillXp or recipe.xp,
            rawCount = 1,
            normalizedCount = 1,
            duplicatesRemoved = 0,
            provider = 'ml_skills',
            treeIndexed = true,
        }
    end
    -- Published trees available: try legacy requireSkill ONLY if that uid exists in the tree.
    -- Orphan skill_N (absent from published nodes) must never invent a gate.
    if recipeIndexLoaded then
        local refs = collectLegacySkillRefs(recipe)
        local skills, seen = {}, {}
        for i = 1, #refs do
            local ref = refs[i]
            local pub = resolvePublishedSkill(ref.uid, ref.cat)
            if pub then
                local key = pub.categoryUid .. ':' .. pub.skillUid
                if not seen[key] then
                    seen[key] = true
                    local row = {
                        provider = 'ml_skills',
                        category = pub.categoryUid,
                        categoryKey = pub.categoryUid,
                        categoryUid = pub.categoryUid,
                        uid = pub.skillUid,
                        skillUid = pub.skillUid,
                        label = pub.label or Skills.SkillLabel(pub.skillUid, pub.categoryUid),
                        source = 'ml_skills_published_uid',
                    }
                    if src then
                        row.unlocked = Skills.HasUnlockedSkill(src, pub.categoryUid, pub.skillUid) == true
                    end
                    skills[#skills + 1] = row
                end
            end
        end
        if #skills > 0 then
            -- Backfill recipe index so health/debug counts these as real gates.
            if recipe.id and recipeSkillIndex and not recipeSkillIndex[recipe.id] then
                recipeSkillIndex[recipe.id] = {
                    recipeId = recipe.id,
                    categoryUid = skills[1].categoryUid,
                    skillUid = skills[1].skillUid,
                    label = skills[1].label,
                }
            end
            return {
                mode = 'all',
                skills = skills,
                visibility = visibility,
                xp = recipe.skillXp or recipe.xp,
                rawCount = #refs,
                normalizedCount = #skills,
                duplicatesRemoved = math.max(0, #refs - #skills),
                provider = 'ml_skills',
                treeIndexed = true,
            }
        end
        -- Last chance: label / result item ↔ published node (lazy, once recipes+ox labels exist).
        if recipe.id and linkRecipesByPublishedLabels then
            linkRecipesByPublishedLabels()
            local linked2 = recipeSkillIndex and recipeSkillIndex[recipe.id]
            if linked2 then
                local row = {
                    provider = 'ml_skills',
                    category = linked2.categoryUid,
                    categoryKey = linked2.categoryUid,
                    categoryUid = linked2.categoryUid,
                    uid = linked2.skillUid,
                    skillUid = linked2.skillUid,
                    label = linked2.label or Skills.SkillLabel(linked2.skillUid, linked2.categoryUid),
                    source = 'ml_skills_label',
                }
                if src then
                    row.unlocked = Skills.HasUnlockedSkill(src, linked2.categoryUid, linked2.skillUid) == true
                end
                return {
                    mode = 'all',
                    skills = { row },
                    visibility = visibility,
                    xp = recipe.skillXp or recipe.xp,
                    rawCount = 1,
                    normalizedCount = 1,
                    duplicatesRemoved = 0,
                    provider = 'ml_skills',
                    treeIndexed = true,
                }
            end
        end
        return nil
    end

    -- Cold-start fallback only (ml_skills unavailable): keep legacy parsing/failClosed.
    local skills = {}
    local seen = {}
    local rawCount = 0
    local duplicatesRemoved = 0
    local mode = 'all'

    local function resolveCatKey(cat)
        if type(cat) ~= 'string' or cat == '' then
            return skillsCfg().defaultCategory or 'survival'
        end
        if SkillTree and SkillTree.ResolveKey then
            return SkillTree.ResolveKey(cat) or cat
        end
        return cat
    end

    local function pushSkill(obj, defaultCat, sourceTag)
        if obj == nil then return end
        rawCount = rawCount + 1
        local cat, uid, level
        if type(obj) == 'string' then
            cat = defaultCat or (skillsCfg().defaultCategory or 'survival')
            uid = obj
            level = nil
        elseif type(obj) == 'table' then
            cat = obj.category or obj.cat or obj.categoryUid or defaultCat
            uid = obj.uid or obj.skillUid or obj.skill or obj.requiredSkill
            level = obj.level or obj.requiredLevel or obj.requireLevel
            if type(uid) ~= 'string' or uid == '' then uid = nil end
            level = level and tonumber(level) or nil
            if uid == nil and level == nil then
                rawCount = rawCount - 1
                return
            end
        else
            rawCount = rawCount - 1
            return
        end

        local catKey = resolveCatKey(cat)
        local catUid = resolveCategoryUid(catKey) or resolveCategoryUid(cat)
        if type(catUid) ~= 'string' or catUid == '' then
            catUid = (type(cat) == 'string' and cat) or catKey
        end
        -- Level-only rows use empty skillUid in the dedupe key (distinct from real uids).
        local skillUid = uid or ''
        local key = skillReqDedupeKey(provider, catUid, skillUid)
        local existing = seen[key]
        if existing then
            duplicatesRemoved = duplicatesRemoved + 1
            if level and not existing.level then existing.level = level end
            if uid and not existing.uid then
                existing.uid = uid
                existing.skillUid = uid
            end
            if catKey and not existing.category then existing.category = catKey end
            skillDebugLog('dedupe', recipe.id or '?', sourceTag or '?', key)
            return
        end

        local label = nil
        if uid then
            label = Skills.SkillLabel(uid, catKey)
        end
        local row = {
            provider = provider,
            category = catKey,
            categoryKey = catKey,
            categoryUid = catUid,
            uid = uid,
            skillUid = uid,
            label = label,
            level = level,
            source = sourceTag,
        }
        if src and uid then
            row.unlocked = Skills.HasUnlockedSkill(src, catUid, uid) == true
        end
        skills[#skills + 1] = row
        seen[key] = row
    end

    -- 1) requiredSkills (multi) — merge, do not early-return alone
    if recipe.requiredSkills and type(recipe.requiredSkills) == 'table' then
        if recipe.requiredSkills.mode == 'any' then mode = 'any' end
        local list = recipe.requiredSkills.skills or recipe.requiredSkills
        if type(list) == 'table' and list.mode then
            list = recipe.requiredSkills.skills
        end
        if type(list) == 'table' then
            if list[1] ~= nil then
                for i = 1, #list do pushSkill(list[i], nil, 'requiredSkills') end
            else
                for _, v in pairs(list) do
                    if type(v) == 'table' and (v.uid or v.skillUid or v.category or v.level) then
                        pushSkill(v, nil, 'requiredSkills')
                    end
                end
            end
        end
    end

    -- 2) requiredSkill (canonical single)
    if recipe.requiredSkill ~= nil then
        local rs = recipe.requiredSkill
        if type(rs) == 'table' then
            pushSkill(rs, rs.category, 'requiredSkill')
        elseif type(rs) == 'string' then
            local cat = recipe.skillCategory
                or (recipe.skillTree and recipe.skillTree.category)
                or (recipe.xp and recipe.xp.category)
            pushSkill(rs, cat, 'requiredSkill')
        end
    end

    -- 3) skillTree / requiredSkillTree — ONLY as migrate mirror of ml fields (deduped).
    --    When provider=ml_skills we do NOT invent gates from SST/DevHub leftovers.
    local st = recipe.skillTree or recipe.requiredSkillTree
    if type(st) == 'table' then
        local cat = st.category or st.catKey or st.cat
        local level = st.requiredLevel or st.requireLevel or st.level
        local sk = st.requiredSkill or st.requireSkill or st.skill
        if sk or level then
            if type(sk) == 'table' then
                pushSkill(sk, cat, 'skillTree')
                if level and skills[#skills] and not skills[#skills].level then
                    skills[#skills].level = tonumber(level)
                end
            else
                pushSkill({ category = cat, uid = type(sk) == 'string' and sk or nil, level = level }, cat, 'skillTree')
            end
        elseif cat and level then
            pushSkill({ category = cat, uid = nil, level = level }, cat, 'skillTree')
        end
    end

    -- 4) legacy requireLevel / requireSkill (post-NormalizeRecipe mirrors)
    -- IMPORTANT: SkillTree.NormalizeRecipe mirrors requireSkill into requiredSkill/skillTree
    -- and clears requireSkillCategory. Re-pushing the bare string then falls back to
    -- Config.Skills.defaultCategory ('engineer') and creates a SECOND gate (mode=all)
    -- → inflated "invalid skill mapping" + impossible unlocks. Skip if uid already present.
    local function alreadyHasUid(uid)
        if type(uid) ~= 'string' or uid == '' then return false end
        for i = 1, #skills do
            if skills[i].uid == uid or skills[i].skillUid == uid then return true end
        end
        return false
    end
    if recipe.requireLevel or recipe.requiredLevel then
        local cat = recipe.requireSkillCategory or recipe.skillCategory
            or (recipe.xp and recipe.xp.category)
            or (skills[1] and skills[1].category)
        local level = recipe.requireLevel or recipe.requiredLevel
        local sk = recipe.requireSkill
        if type(sk) == 'string' and alreadyHasUid(sk) then
            -- only merge level onto existing row
            for i = 1, #skills do
                if (skills[i].uid == sk or skills[i].skillUid == sk) and level and not skills[i].level then
                    skills[i].level = tonumber(level)
                end
            end
        elseif type(sk) == 'string' or level then
            pushSkill({ category = cat, uid = type(sk) == 'string' and sk or nil, level = level }, cat, 'requireLevel')
        end
    elseif type(recipe.requireSkill) == 'string' then
        if not alreadyHasUid(recipe.requireSkill) then
            pushSkill(recipe.requireSkill, recipe.requireSkillCategory or recipe.skillCategory, 'requireSkill')
        end
    end

    -- 5) SST / DevHub / sanctuary leftovers — NEVER silently add as unlock OR.
    local legacyNoise = recipe.devhubSkill or recipe.sanctuarySkill or recipe.sanctuary_skilltree
        or recipe.sstSkill or recipe.requiredTalent or recipe.devhubTalent
    if legacyNoise ~= nil then
        print(('[CRAFT] IGNORE legacy skill field on recipe=%s (provider=ml_skills) — not added to gates'):format(
            tostring(recipe.id or '?')))
    end

    if #skills == 0 then
        if legacyNoise ~= nil or recipe.skillUid then
            print(('[CRAFT] UNMAPPED RECIPE SKILL id=%s fields present but incomplete — left unlocked/free'):format(
                tostring(recipe.id or '?')))
        end
        return nil
    end

    local normalized = {
        mode = mode,
        skills = skills,
        visibility = visibility,
        xp = recipe.skillXp or recipe.xp,
        rawCount = rawCount,
        normalizedCount = #skills,
        duplicatesRemoved = duplicatesRemoved,
        provider = provider,
    }

    if skillDebugEnabled() or duplicatesRemoved > 0 then
        skillDebugLog(
            'normalize',
            'recipe=' .. tostring(recipe.id or '?'),
            'raw=' .. tostring(rawCount),
            'normalized=' .. tostring(#skills),
            'dupesRemoved=' .. tostring(duplicatesRemoved)
        )
    end

    return normalized
end

--- Back-compat alias — always goes through normalizeSkillRequirements.
function Skills.ParseRecipeRequirement(recipe)
    return Skills.normalizeSkillRequirements(recipe, nil)
end

function Skills.CheckRecipeRequirement(src, recipe)
    local req = Skills.normalizeSkillRequirements(recipe, nil)
    if not req or not req.skills or #req.skills == 0 then
        return true
    end
    if Skills.ShouldBypassRequirements(src) then
        return true
    end
    if not integrationEnabled() then
        return false, 'skills_unavailable'
    end
    if not Skills.IsAvailable() then
        warnIfDown()
        if failClosed() then
            return false, 'skills_unavailable'
        end
        return true
    end

    local mode = req.mode or 'all'
    local lastFailReason, lastFailArgs
    local anyOk = false

    for i = 1, #req.skills do
        local sk = req.skills[i]
        local ok, reason, args = Skills.HasUnlockedRecipeSkill(src, sk)
        if ok then
            anyOk = true
            if mode == 'any' then return true end
        else
            lastFailReason, lastFailArgs = reason, args
            if mode == 'all' then
                if reason == 'skill_locked' then
                    return false, 'craft_skill_required', args
                elseif reason == 'skill_level_low' then
                    return false, 'craft_level_required', args
                elseif reason == 'skills_unavailable' then
                    return false, 'craft_skills_unavailable', args
                end
                return false, reason or 'craft_skill_required', args
            end
        end
    end

    if mode == 'any' and anyOk then return true end
    if lastFailReason == 'skill_locked' then
        return false, 'craft_skill_required', lastFailArgs
    elseif lastFailReason == 'skill_level_low' then
        return false, 'craft_level_required', lastFailArgs
    end
    return false, lastFailReason or 'craft_skill_required', lastFailArgs
end

--------------------------------------------------------------------------------
-- Facing / snapshot (NUI display — server authoritative)
--------------------------------------------------------------------------------

function Skills.LevelCategoryForRecipe(recipe)
    local req = Skills.ParseRecipeRequirement(recipe)
    if req and req.skills[1] and req.skills[1].category then
        return (SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(req.skills[1].category))
            or req.skills[1].category
    end
    if SkillTree and SkillTree.RecipeGate then
        local g = SkillTree.RecipeGate(recipe)
        if g.category then return g.category end
    end
    return skillsCfg().defaultCategory or 'survival'
end

function Skills.FacingSkill(src, recipe, _snap)
    local req = Skills.normalizeSkillRequirements(recipe, nil)
    local catKey = Skills.LevelCategoryForRecipe(recipe)
    local entry = Skills.GetCache(src)
    local primary = req and req.skills and req.skills[1] or nil
    local talentUid = primary and (primary.uid or primary.skillUid) or nil
    local talentLabel = talentUid and Skills.SkillLabel(talentUid, primary.category or catKey) or nil
    local requireLevel = primary and primary.level or nil

    local gateOk, gateReason, gateArgs = true, nil, nil
    if req then
        gateOk, gateReason, gateArgs = Skills.CheckRecipeRequirement(src, recipe)
    end
    local locked = req ~= nil and not gateOk
    local skillLocked = locked and (
        gateReason == 'craft_skill_required'
        or gateReason == 'skill_locked'
        or gateReason == 'craft_recipe_locked'
    )
    local levelLocked = locked and (
        gateReason == 'craft_level_required' or gateReason == 'skill_level_low'
    )

    local mode = (req and req.mode == 'any') and 'any' or 'all'
    local skillsDisplay = {}
    local seenDisplay = {}

    if req and type(req.skills) == 'table' then
        for i = 1, #req.skills do
            local sk = req.skills[i]
            if type(sk) == 'table' then
                local ckey = sk.categoryKey or sk.category or catKey
                if SkillTree and SkillTree.ResolveKey then
                    ckey = SkillTree.ResolveKey(ckey) or ckey
                end
                local catUid = sk.categoryUid or resolveCategoryUid(ckey)
                local uid = sk.uid or sk.skillUid
                local dkey = skillReqDedupeKey(sk.provider or 'ml_skills', catUid, uid or '')
                local existing = seenDisplay[dkey]
                if existing then
                    if sk.level and not existing.requireLevel then
                        existing.requireLevel = tonumber(sk.level)
                    end
                else
                    local unlocked = nil
                    if type(uid) == 'string' and uid ~= '' then
                        -- Strict: only true when HasUnlockedSkill == true (same path as gate).
                        unlocked = Skills.HasUnlockedSkill(src, catUid or ckey, uid) == true
                    end
                    local row = {
                        provider = sk.provider or 'ml_skills',
                        category = ckey,
                        categoryLabel = Skills.CategoryLabel(ckey),
                        categoryUid = catUid,
                        skillUid = uid,
                        skillLabel = (type(uid) == 'string' and uid ~= '')
                            and (sk.label or Skills.SkillLabel(uid, ckey))
                            or nil,
                        unlocked = unlocked,
                        requireLevel = sk.level and tonumber(sk.level) or nil,
                        level = Skills.GetLevel(src, ckey),
                    }
                    skillsDisplay[#skillsDisplay + 1] = row
                    seenDisplay[dkey] = row
                end
            end
        end
    end

    -- Reconcile display with gate: recipe-level hasRequiredSkill is false when skill-locked.
    -- Per-skill ✓ only when strict HasUnlockedSkill == true (already set above).
    -- If skill-locked yet every skill row still claims true (stale cache / contradiction), force all false.
    local hasRequiredSkill = nil
    if talentUid then
        hasRequiredSkill = Skills.HasUnlockedSkill(
            src,
            (primary and (primary.categoryUid or primary.category)) or catKey,
            talentUid
        ) == true
    end

    if skillLocked then
        hasRequiredSkill = false
        if mode == 'any' then
            for i = 1, #skillsDisplay do
                if skillsDisplay[i].skillUid then
                    skillsDisplay[i].unlocked = false
                end
            end
        else
            local anyMissing = false
            for i = 1, #skillsDisplay do
                local row = skillsDisplay[i]
                if row.skillUid then
                    if row.unlocked == true then
                        -- keep genuine unlocks for siblings
                    else
                        row.unlocked = false
                        anyMissing = true
                    end
                end
            end
            if not anyMissing then
                for i = 1, #skillsDisplay do
                    if skillsDisplay[i].skillUid then
                        skillsDisplay[i].unlocked = false
                    end
                end
            end
        end
    end

    if skillDebugEnabled() and req then
        skillDebugLog(
            'FacingSkill',
            'recipe=' .. tostring(recipe and recipe.id or '?'),
            'gateOk=' .. tostring(gateOk),
            'reason=' .. tostring(gateReason),
            'skills=' .. tostring(#skillsDisplay),
            'hasRequired=' .. tostring(hasRequiredSkill),
            'dupesRemoved=' .. tostring(req.duplicatesRemoved or 0)
        )
    end

    local playerLevel = Skills.GetLevel(src, catKey)

    return {
        category = catKey,
        categoryLabel = Skills.CategoryLabel(catKey),
        categoryUid = resolveCategoryUid(catKey),
        requireLevel = requireLevel,
        requireSkill = talentUid,
        requiredSkillLabel = talentLabel,
        hasRequiredSkill = hasRequiredSkill,
        playerSkillLevel = playerLevel,
        playerSkillXp = nil,
        playerTotalXp = nil,
        recipeLocked = locked and talentUid ~= nil,
        canAccessRecipe = not locked,
        skilltreeSkillUid = talentUid,
        skilltreeCategoryUid = resolveCategoryUid(primary and primary.category or catKey),
        skilltreeSkillLabel = talentLabel,
        openSkillHint = locked == true,
        skillVisibility = req and req.visibility or 'visible_locked',
        mysteryMode = (recipe and recipe.mysteryMode)
            or ((req and req.visibility == 'mystery_until_unlocked') and 'full')
            or 'recipe_only',
        skillsLoading = entry.loading == true and entry.available ~= true,
        visualStatus = locked and (talentUid and 'LOCKED_SKILL' or (requireLevel and 'LOCKED_LEVEL' or 'LOCKED_SKILL')) or nil,
        mode = mode,
        skills = skillsDisplay,
        lockReason = locked and gateReason or nil,
        lockArgs = locked and gateArgs or nil,
        normalizedCount = req and req.normalizedCount or 0,
        duplicatesRemoved = req and req.duplicatesRemoved or 0,
    }
end

function Skills.Snapshot(src, force)
    if force or not UnlockedCache[src] then
        Skills.RebuildCache(src)
    end
    local entry = Skills.GetCache(src)
    local categories = {}
    for key, def in pairs(Config.SkillCategories or {}) do
        local lvl = entry.levels[key] or 0
        categories[key] = {
            key = key,
            uid = def.categoryUid,
            label = Skills.CategoryLabel(key),
            level = lvl,
            xp = 0,
            totalXp = 0,
        }
    end
    return {
        available = entry.available == true,
        loading = entry.loading == true,
        provider = 'ml_skills',
        source = src,
        loadedAt = entry.loadedAt,
        categories = categories,
        unlocked = entry.list,
        unlockedSet = entry.unlocked,
        global = {
            totalXp = 0,
            totalLevel = 0,
            usedPoints = 0,
            unlockedSkills = #(entry.list or {}),
        },
    }
end

--------------------------------------------------------------------------------
-- Health / validation
--------------------------------------------------------------------------------

function Skills.HealthReport()
    local startedOk = Skills.IsAvailable()
    local cats = 0
    for _ in pairs(Config.SkillCategories or {}) do cats = cats + 1 end
    local withReq, valid, invalid = 0, 0, 0
    local indexedGates, ignoredLegacy = 0, 0
    local invalidList = {}
    if not labelIndex then loadLabelIndex() end
    local recipes = (Config.RecipeById or Config.Recipes or {})
    local list
    if recipes[1] ~= nil then
        list = recipes
    else
        list = {}
        for _, r in pairs(recipes) do list[#list + 1] = r end
    end
    for i = 1, #list do
        local r = list[i]
        if type(r) == 'table' then
            local linked = r.id and recipeSkillIndex and recipeSkillIndex[r.id] or nil
            if not linked and recipeIndexLoaded then
                -- Probe published uids from legacy requireSkill (same rules as normalize).
                local refs = collectLegacySkillRefs(r)
                for ri = 1, #refs do
                    local pub = resolvePublishedSkill(refs[ri].uid, refs[ri].cat)
                    if pub then
                        linked = {
                            recipeId = r.id,
                            categoryUid = pub.categoryUid,
                            skillUid = pub.skillUid,
                            label = pub.label,
                        }
                        if r.id and recipeSkillIndex then
                            recipeSkillIndex[r.id] = linked
                        end
                        break
                    end
                end
            end
            if linked then
                indexedGates = indexedGates + 1
            elseif recipeIndexLoaded and (r.requiredSkill ~= nil or r.requiredSkills ~= nil
                or r.skillTree ~= nil or r.requireSkill ~= nil or r.requireLevel ~= nil) then
                ignoredLegacy = ignoredLegacy + 1
            end
            local req = Skills.ParseRecipeRequirement(r)
            if req and req.skills and #req.skills > 0 then
                withReq = withReq + 1
                for j = 1, #req.skills do
                    local sk = req.skills[j]
                    local cuid = resolveCategoryUid(sk.category)
                    local knownCat = cuid and labelIndex and (labelIndex['cat:' .. cuid] or (Config.SkillCategories and SkillTree.ResolveKey(sk.category)))
                    local knownSkill = sk.uid == nil or (labelIndex and (labelIndex[sk.uid] or (cuid and labelIndex[cuid .. ':' .. sk.uid])))
                    -- if ml down, still count structural validity of category key
                    local catOk = SkillTree and SkillTree.ResolveKey and SkillTree.ResolveKey(sk.category) ~= nil
                        or (cuid ~= nil)
                    if catOk and (knownSkill or not startedOk) then
                        valid = valid + 1
                    else
                        invalid = invalid + 1
                        invalidList[#invalidList + 1] = {
                            recipeId = r.id,
                            category = sk.category,
                            uid = sk.uid,
                        }
                    end
                end
            end
        end
    end
    return {
        mlSkillsStarted = startedOk,
        resource = resourceName(),
        categoriesCount = cats,
        recipesWithSkillReq = withReq,
        validMappings = valid,
        invalidMappings = invalid,
        invalidList = invalidList,
        recipeIndexLoaded = recipeIndexLoaded,
        indexedRecipeGates = indexedGates,
        ignoredLegacyMappings = ignoredLegacy,
        failClosed = failClosed(),
        cache = cacheEnabled(),
        xpOn = integ().xpOn or (Config.StationOutput and Config.StationOutput.XpOn) or 'collect',
    }
end

function Skills.ValidateRecipesAtStartup()
    local report = Skills.HealthReport()
    if report.invalidMappings > 0 then
        print(('[CRAFT] ML SKILLS: %d invalid indexed mapping(s)'):format(report.invalidMappings))
        for i = 1, math.min(20, #report.invalidList) do
            local row = report.invalidList[i]
            print(('[CRAFT]   recipe=%s category=%s uid=%s'):format(
                tostring(row.recipeId), tostring(row.category), tostring(row.uid)))
        end
    else
        print(('[CRAFT] ML SKILLS: ok — %d published recipe gate(s), indexLoaded=%s, resource=%s started=%s'):format(
            report.indexedRecipeGates or 0, tostring(report.recipeIndexLoaded),
            tostring(report.resource), tostring(report.mlSkillsStarted)))
    end
    if (report.ignoredLegacyMappings or 0) > 0 then
        print(('[CRAFT] ML SKILLS: %d legacy skill field(s) ignored — recipes absent from published tree stay free'):format(
            report.ignoredLegacyMappings))
    end
    return report
end

--------------------------------------------------------------------------------
-- Lifecycle — AddEventHandler for local ml_skills:server:* (NOT RegisterNetEvent)
--------------------------------------------------------------------------------

local function notifyRecipeSkillUpdated(src, payload)
    if not src or src < 1 then return end
    TriggerClientEvent('sanctuary_crafting:client:recipeSkillUpdated', src, payload or {})
end

AddEventHandler('ml_skills:server:playerLoaded', function(src, ...)
    src = tonumber(src) or tonumber(source)
    if not src or src < 1 then return end
    Skills.RebuildCache(src)
    notifyRecipeSkillUpdated(src, { reason = 'playerLoaded' })
end)

AddEventHandler('ml_skills:server:skillUnlocked', function(src, categoryUid, skillUid, ...)
    src = tonumber(src) or tonumber(source)
    if not src or src < 1 then return end
    -- payload may be table as 2nd arg
    local payload = categoryUid
    local cat, uid
    if type(payload) == 'table' then
        cat = payload.categoryUid or payload.category_uid or payload.category
        uid = payload.skillUid or payload.skill_uid or payload.uid
    else
        cat = categoryUid
        uid = skillUid
        if type(skillUid) == 'table' then
            cat = skillUid.categoryUid or cat
            uid = skillUid.skillUid or skillUid.uid
        end
    end
    local entry = UnlockedCache[src] or Skills.RebuildCache(src)
    if type(uid) == 'string' then
        ingestUnlocked(entry, cat, uid, nil)
        entry.loadedAt = nowMs()
        UnlockedCache[src] = entry
        if NewlyLearned and NewlyLearned.MarkFromTalent then
            NewlyLearned.MarkFromTalent(src, uid)
        end
    else
        Skills.RebuildCache(src)
    end
    local recipeIds = {}
    if type(uid) == 'string' and MysteryView and MysteryView.RecipeIdsForSkill then
        recipeIds = MysteryView.RecipeIdsForSkill(cat, uid) or {}
    elseif type(uid) == 'string' then
        for _, recipe in pairs(Config.RecipeById or {}) do
            local g = SkillTree and SkillTree.RecipeGate and SkillTree.RecipeGate(recipe) or {}
            if g.requiredSkill == uid then
                recipeIds[#recipeIds + 1] = recipe.id
            end
        end
    end
    notifyRecipeSkillUpdated(src, {
        reason = 'skillUnlocked',
        categoryUid = cat,
        skillUid = uid,
        recipeIds = recipeIds,
        revealMs = 280,
    })
end)

AddEventHandler('ml_skills:server:playerUnloaded', function(src, ...)
    src = tonumber(src) or tonumber(source)
    if src and src > 0 then
        Skills.ClearCache(src)
    end
end)

-- Character / session cleanup
AddEventHandler('playerDropped', function()
    local src = source
    if src then Skills.ClearCache(src) end
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = type(playerId) == 'number' and playerId or source
    if src then
        Skills.RebuildCache(src)
        notifyRecipeSkillUpdated(src, { reason = 'esx:playerLoaded' })
    end
end)

local function onMlResource(res)
    if res ~= resourceName() and res ~= GetCurrentResourceName() then return end
    labelIndex = nil
    recipeSkillIndex = nil
    publishedSkillByUid = nil
    publishedByNormLabel = nil
    recipeIndexLoaded = false
    UnlockedCache = {}
    warnedDown = false
    if res == resourceName() and started(resourceName()) then
        loadLabelIndex()
        -- hot restart: rebuild for online players via playerLoaded-style refresh
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            if src then Skills.RebuildCache(src) end
        end
    end
end

AddEventHandler('onResourceStart', function(res)
    onMlResource(res)
    if res == GetCurrentResourceName() then
        CreateThread(function()
            Wait(1500)
            Skills.ValidateRecipesAtStartup()
        end)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == resourceName() then
        labelIndex = nil
        recipeSkillIndex = nil
        recipeIndexLoaded = false
        UnlockedCache = {}
        warnedDown = false
    end
end)

--------------------------------------------------------------------------------
-- Admin command
--------------------------------------------------------------------------------

lib.addCommand('craftskillcheck', {
    help = 'Health: ml_skills bridge + recipe skill mappings',
    restricted = 'group.admin',
}, function(src)
    local report = Skills.HealthReport()
    local lines = {
        ('ml_skills started: %s (%s)'):format(tostring(report.mlSkillsStarted), report.resource),
        ('categories: %s'):format(report.categoriesCount),
        ('recipes with skill req: %s'):format(report.recipesWithSkillReq),
        ('valid mappings: %s'):format(report.validMappings),
        ('invalid mappings: %s'):format(report.invalidMappings),
        ('failClosed=%s cache=%s xpOn=%s'):format(
            tostring(report.failClosed), tostring(report.cache), tostring(report.xpOn)),
    }
    for i = 1, #lines do
        if src and src > 0 then
            TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = lines[i] })
        end
        print('[CRAFT] ' .. lines[i])
    end
    for i = 1, math.min(10, #(report.invalidList or {})) do
        local row = report.invalidList[i]
        local msg = ('invalid: %s → %s/%s'):format(tostring(row.recipeId), tostring(row.category), tostring(row.uid))
        print('[CRAFT] ' .. msg)
        if src and src > 0 then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = msg })
        end
    end
end)


lib.addCommand('craftskilldebug', {
    help = 'Dump skill unlock path for a recipe (categoryUid/skillUid/raw/normalized/cache)',
    params = {
        { name = 'recipeId', type = 'string', help = 'Recipe id (e.g. craft_smallboat)' },
    },
    restricted = 'group.admin',
}, function(src, args)
    local recipeId = args and args.recipeId
    local recipe = recipeId and Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then
        local msg = ('craftskilldebug: unknown recipe %s'):format(tostring(recipeId))
        print('[CRAFT] ' .. msg)
        if src and src > 0 then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = msg })
        end
        return
    end

    local req = Skills.normalizeSkillRequirements(recipe, nil)
    local lines = {
        ('recipe=%s provider=%s'):format(tostring(recipeId), tostring(Skills.Provider())),
        ('rawCount=%s normalizedCount=%s dupesRemoved=%s mode=%s'):format(
            tostring(req and req.rawCount),
            tostring(req and req.normalizedCount),
            tostring(req and req.duplicatesRemoved),
            tostring(req and req.mode)
        ),
    }

    local entry = (src and src > 0) and Skills.GetCache(src) or emptyCache(src)
    local skills = (req and req.skills) or {}
    for i = 1, #skills do
        local sk = skills[i]
        local catUid = sk.categoryUid or resolveCategoryUid(sk.category)
        local skillUid = sk.uid or sk.skillUid
        local key = cacheKey(catUid, skillUid)
        local cacheVal = entry.unlocked and entry.unlocked[key]
        local rawOk, rawHas = false, nil
        if type(skillUid) == 'string' and skillUid ~= '' and type(catUid) == 'string' then
            rawOk, rawHas = pexport('HasUnlockedSkill', catUid, skillUid, src)
        end
        local normalized = Skills.HasUnlockedSkill(src, catUid or sk.category, skillUid) == true
        local inList = false
        for j = 1, #(entry.list or {}) do
            local u = entry.list[j]
            if u and u.uid == skillUid and (not catUid or u.categoryUid == catUid) then
                inList = true
                break
            end
        end
        lines[#lines + 1] = (
            ('[%d] catKey=%s categoryUid=%s skillUid=%s label=%s'):format(
                i, tostring(sk.category), tostring(catUid), tostring(skillUid), tostring(sk.label)
            )
        )
        lines[#lines + 1] = (
            ('    raw HasUnlockedSkill ok=%s result=%s (%s) | normalized=%s | cache[%s]=%s | in GetUnlockedSkills list=%s'):format(
                tostring(rawOk),
                tostring(rawHas),
                type(rawHas),
                tostring(normalized),
                tostring(key),
                tostring(cacheVal),
                tostring(inList)
            )
        )
    end

    local gateOk, gateReason = Skills.CheckRecipeRequirement(src, recipe)
    lines[#lines + 1] = ('CheckRecipeRequirement ok=%s reason=%s'):format(tostring(gateOk), tostring(gateReason))

    for i = 1, #lines do
        print('[CRAFT][craftskilldebug] ' .. lines[i])
        if src and src > 0 then
            TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = lines[i]:sub(1, 120) })
        end
    end
end)

-- NUI skill snapshot callback lives in crafting_skills compatibility layer
