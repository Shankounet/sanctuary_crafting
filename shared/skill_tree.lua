--[[
    shared/skill_tree.lua — category KEY resolution + recipe skill schema migration.
    No ml_skills exports here. UIDs live in Config.SkillCategories (+ CategoryMapping).

    Canonical recipe skill fields:
      requiredSkill = nil | { category, uid, level? }
      requiredSkills = { mode = 'all'|'any', skills = { ... } }
      skillVisibility = 'visible_locked' | 'hidden_until_unlocked' | 'mystery_until_unlocked' | 'discovered_locked'
      mysteryMode = 'full' | 'recipe_only'  -- FULL hides skill name; RECIPE_ONLY shows SAVOIR REQUIS category
      skillXp = { category?, amount }
    Legacy skillTree / require* / hideIfSkillLocked migrated at NormalizeRecipe.
]]

SkillTree = SkillTree or {}

local function cfgCats()
    return (Config and Config.SkillCategories) or {}
end

--- Map any legacy UID / alias / KEY → SkillCategories KEY (survival/medic/engineer/gunsmith).
---@param raw string|nil
---@return string|nil
function SkillTree.ResolveKey(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local cats = cfgCats()
    if cats[raw] then return raw end
    local lower = raw:lower()
    if cats[lower] then return lower end
    local map = (Config.SkillIntegration and Config.SkillIntegration.CategoryMapping) or {}
    if map[raw] and cats[map[raw]] then return map[raw] end
    if map[lower] and cats[map[lower]] then return map[lower] end
    local legacy = (Config.SkillLegacyMap or {})[raw] or (Config.SkillLegacyMap or {})[lower]
    if legacy and cats[legacy] then return legacy end
    for key, def in pairs(cats) do
        if def and (def.categoryUid == raw or def.categoryUid == lower) then
            return key
        end
    end
    return nil
end

---@param catKey string|nil
---@return string|nil
function SkillTree.CategoryUid(catKey)
    local key = SkillTree.ResolveKey(catKey)
    if not key then
        local map = Config.SkillIntegration and Config.SkillIntegration.CategoryMapping
        if type(map) == 'table' and map[catKey] then return map[catKey] end
        return catKey -- may already be a published UID
    end
    local def = cfgCats()[key]
    return def and def.categoryUid or nil
end

---@param catKey string|nil
---@return string
function SkillTree.CategoryLabel(catKey)
    local key = SkillTree.ResolveKey(catKey) or catKey
    local def = key and cfgCats()[key]
    if def and def.label then return def.label end
    return key or ''
end

---@param station string|nil
---@return string|nil
function SkillTree.StationCategory(station)
    if type(station) ~= 'string' or station == '' then
        return Config.Skills and Config.Skills.defaultCategory or 'survival'
    end
    local map = Config.StationSkillCategory or {}
    local mapped = map[station]
    if mapped then return SkillTree.ResolveKey(mapped) or mapped end
    return SkillTree.ResolveKey(station) or (Config.Skills and Config.Skills.defaultCategory) or 'survival'
end

local function numOrNil(v)
    if v == nil or v == false then return nil end
    local n = tonumber(v)
    if not n then return nil end
    return n
end

local function strOrNil(v)
    if type(v) ~= 'string' or v == '' then return nil end
    return v
end

--- Canonical gate table from requiredSkill / requiredSkills / skillTree / legacy.
---@param recipe table
---@return table { category, requiredLevel, requiredSkill, visibility }
function SkillTree.RecipeGate(recipe)
    if type(recipe) ~= 'table' then
        return { category = nil, requiredLevel = nil, requiredSkill = nil, visibility = 'visible_locked' }
    end

    local visibility = recipe.skillVisibility
        or (recipe.hideIfSkillLocked and 'hidden_until_unlocked')
        or 'visible_locked'
    if visibility == 'mystery' then visibility = 'mystery_until_unlocked' end
    if visibility == 'discovered' then visibility = 'discovered_locked' end

    -- New schema: requiredSkill table
    if type(recipe.requiredSkill) == 'table' then
        local rs = recipe.requiredSkill
        return {
            category = SkillTree.ResolveKey(rs.category or rs.cat or rs.categoryUid),
            requiredLevel = numOrNil(rs.level or rs.requiredLevel or rs.requireLevel),
            requiredSkill = strOrNil(rs.uid or rs.skillUid or rs.skill),
            visibility = visibility,
        }
    end

    -- requiredSkills multi
    if type(recipe.requiredSkills) == 'table' then
        local list = recipe.requiredSkills.skills or recipe.requiredSkills
        local first = type(list) == 'table' and (list[1] or nil) or nil
        if not first then
            for _, v in pairs(type(list) == 'table' and list or {}) do
                if type(v) == 'table' then first = v break end
            end
        end
        if type(first) == 'table' then
            return {
                category = SkillTree.ResolveKey(first.category or first.cat or first.categoryUid),
                requiredLevel = numOrNil(first.level or first.requiredLevel),
                requiredSkill = strOrNil(first.uid or first.skillUid or first.skill),
                visibility = visibility,
            }
        end
    end

    local st = recipe.skillTree or recipe.requiredSkillTree
    local category, requiredLevel, requiredSkill
    if type(st) == 'table' then
        category = st.category or st.catKey or st.cat
        requiredLevel = st.requiredLevel or st.requireLevel or st.level
        requiredSkill = st.requiredSkill or st.requireSkill or st.skill
        if type(requiredSkill) == 'table' then
            category = requiredSkill.category or category
            requiredLevel = requiredSkill.level or requiredLevel
            requiredSkill = requiredSkill.uid or requiredSkill.skillUid
        end
    end
    if not category then
        category = recipe.requireSkillCategory or recipe.skillCategory
            or (type(recipe.requiredSkill) == 'string' and (recipe.xp and recipe.xp.category))
            or (recipe.xp and recipe.xp.category)
            or (recipe.station and SkillTree.StationCategory(recipe.station))
    end
    if requiredLevel == nil then
        requiredLevel = recipe.requireLevel or recipe.requiredLevel or recipe.level
    end
    if requiredSkill == nil then
        local sk = recipe.requireSkill or recipe.requiredSkill
        if type(sk) == 'string' and sk ~= '' then
            requiredSkill = sk
        end
    end
    local key = SkillTree.ResolveKey(category)
    return {
        category = key,
        requiredLevel = numOrNil(requiredLevel),
        requiredSkill = strOrNil(requiredSkill),
        visibility = visibility,
    }
end

function SkillTree.NeedsGate(recipe)
    local g = SkillTree.RecipeGate(recipe)
    return (g.requiredLevel ~= nil) or (g.requiredSkill ~= nil)
        or (type(recipe) == 'table' and type(recipe.requiredSkills) == 'table')
end

--- Mutate recipe in place toward canonical requiredSkill (+ mirrored legacy skillTree).
---@param recipe table
---@return table
function SkillTree.NormalizeRecipe(recipe)
    if type(recipe) ~= 'table' then return recipe end

    -- Uncertain DevHub/SST-only fields without clear mapping
    if not recipe.requiredSkill and not recipe.requiredSkills and not recipe.skillTree
        and not recipe.requireSkill and not recipe.requireLevel then
        if recipe.devhubSkill or recipe.sanctuary_skilltree or recipe.sstSkill then
            print(('[CRAFT] UNMAPPED RECIPE SKILL id=%s — left free (no dangerous rewrite)'):format(
                tostring(recipe.id or '?')))
        end
    end

    local g = SkillTree.RecipeGate(recipe)

    if type(recipe.requiredSkill) == 'table' then
        local rs = recipe.requiredSkill
        local cat = SkillTree.ResolveKey(rs.category or rs.cat or rs.categoryUid) or rs.category
        recipe.requiredSkill = {
            category = cat,
            uid = strOrNil(rs.uid or rs.skillUid or rs.skill),
            level = numOrNil(rs.level or rs.requiredLevel or rs.requireLevel),
        }
    elseif g.category or g.requiredLevel or g.requiredSkill then
        recipe.requiredSkill = {
            category = g.category,
            uid = g.requiredSkill,
            level = g.requiredLevel,
        }
    end

    if g.category or g.requiredLevel or g.requiredSkill then
        recipe.skillTree = {
            category = g.category,
            requiredLevel = g.requiredLevel,
            requiredSkill = g.requiredSkill,
        }
    end

    if not recipe.skillVisibility then
        if recipe.hideIfSkillLocked then
            recipe.skillVisibility = 'hidden_until_unlocked'
        else
            recipe.skillVisibility = g.visibility or 'visible_locked'
        end
    end
    do
        local v = recipe.skillVisibility
        if v == 'mystery' then recipe.skillVisibility = 'mystery_until_unlocked' end
        if v == 'discovered' then recipe.skillVisibility = 'discovered_locked' end
    end
    if type(recipe.mysteryMode) == 'string' then
        local m = recipe.mysteryMode:lower()
        if m == 'recipe_only' or m == 'recipe-only' or m == 'recipeonly' then
            recipe.mysteryMode = 'recipe_only'
        else
            recipe.mysteryMode = 'full'
        end
    elseif recipe.skillVisibility == 'mystery_until_unlocked' then
        recipe.mysteryMode = 'full' -- default for secrets
    end

    recipe.requireLevel = g.requiredLevel
    recipe.requireSkill = g.requiredSkill
    recipe.requireSkillCategory = nil

    -- skillXp → xp (category defaults to requiredSkill.category)
    if type(recipe.skillXp) == 'table' then
        local cat = SkillTree.ResolveKey(recipe.skillXp.category)
            or (recipe.requiredSkill and recipe.requiredSkill.category)
            or g.category
        recipe.xp = recipe.xp or {}
        if type(recipe.xp) ~= 'table' then recipe.xp = {} end
        recipe.xp.category = cat or recipe.xp.category
        recipe.xp.amount = tonumber(recipe.skillXp.amount) or recipe.xp.amount
    elseif type(recipe.xp) == 'table' then
        local xpKey = SkillTree.ResolveKey(recipe.xp.category) or g.category
        if xpKey then recipe.xp.category = xpKey end
        recipe.xp.amount = tonumber(recipe.xp.amount) or recipe.xp.amount
    end

    return recipe
end

function SkillTree.XpAmount(recipe)
    if type(recipe) ~= 'table' then return nil, nil end
    local xp = recipe.skillXp or recipe.xp
    if type(xp) ~= 'table' then return nil, nil end
    local key = SkillTree.ResolveKey(xp.category)
        or (recipe.requiredSkill and type(recipe.requiredSkill) == 'table' and recipe.requiredSkill.category)
    local amt = tonumber(xp.amount)
    if not key or not amt or amt <= 0 then return key, nil end
    return key, amt
end

function SkillTree.IsHiddenForPlayer(recipe, hasSkill)
    local vis = recipe and (recipe.skillVisibility or (recipe.hideIfSkillLocked and 'hidden_until_unlocked'))
    if vis == 'hidden_until_unlocked' and hasSkill == false then
        return true
    end
    return false
end

--- Mystery card (shown as ???) while skill locked — NOT omitted from menu.
function SkillTree.IsMysteryForPlayer(recipe, hasSkill)
    local vis = recipe and recipe.skillVisibility
    return vis == 'mystery_until_unlocked' and hasSkill == false
end

function SkillTree.MysteryMode(recipe)
    if MysteryView and MysteryView.ResolveMysteryMode then
        return MysteryView.ResolveMysteryMode(recipe, recipe and recipe.skillVisibility)
    end
    local m = recipe and recipe.mysteryMode
    if m == 'recipe_only' then return 'recipe_only' end
    if (recipe and recipe.skillVisibility) == 'mystery_until_unlocked' then return 'full' end
    return 'recipe_only'
end
