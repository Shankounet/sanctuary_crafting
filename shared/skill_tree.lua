--[[
    shared/skill_tree.lua — category KEY resolution + one-time recipe migration.
    No DevHub exports here. UIDs live only in Config.SkillCategories (+ legacy map).
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
    if not key then return nil end
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

--- Canonical gate table from skillTree / requiredSkillTree / legacy require* / skill / xp.
---@param recipe table
---@return table { category, requiredLevel, requiredSkill }
function SkillTree.RecipeGate(recipe)
    if type(recipe) ~= 'table' then
        return { category = nil, requiredLevel = nil, requiredSkill = nil }
    end
    local st = recipe.skillTree or recipe.requiredSkillTree
    local category, requiredLevel, requiredSkill
    if type(st) == 'table' then
        category = st.category or st.catKey or st.cat
        requiredLevel = st.requiredLevel or st.requireLevel or st.level
        requiredSkill = st.requiredSkill or st.requireSkill or st.skill
    end
    if not category then
        category = recipe.requireSkillCategory or recipe.skillCategory
            or recipe.skill or (recipe.xp and recipe.xp.category)
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
    }
end

function SkillTree.NeedsGate(recipe)
    local g = SkillTree.RecipeGate(recipe)
    return (g.requiredLevel ~= nil) or (g.requiredSkill ~= nil)
end

--- Mutate recipe in place: skillTree KEY form + mirrored require* + xp.category KEY.
---@param recipe table
---@return table
function SkillTree.NormalizeRecipe(recipe)
    if type(recipe) ~= 'table' then return recipe end
    local g = SkillTree.RecipeGate(recipe)
    if g.category or g.requiredLevel or g.requiredSkill then
        recipe.skillTree = {
            category = g.category,
            requiredLevel = g.requiredLevel,
            requiredSkill = g.requiredSkill,
        }
    end
    recipe.requireLevel = g.requiredLevel
    recipe.requireSkill = g.requiredSkill
    recipe.requireSkillCategory = nil
    if type(recipe.xp) == 'table' then
        local xpKey = SkillTree.ResolveKey(recipe.xp.category) or g.category
        if xpKey then recipe.xp.category = xpKey end
        recipe.xp.amount = tonumber(recipe.xp.amount) or recipe.xp.amount
    end
    return recipe
end

function SkillTree.XpAmount(recipe)
    if type(recipe) ~= 'table' or type(recipe.xp) ~= 'table' then return nil, nil end
    local key = SkillTree.ResolveKey(recipe.xp.category)
    local amt = tonumber(recipe.xp.amount)
    if not key or not amt or amt <= 0 then return key, nil end
    return key, amt
end
