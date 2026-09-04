--[[
    shared/specialty_icons.lua — resolve specialty pictograms for NUI.
    Sparse: Config.SkillCategories + Config.SpecialtyIcons + legacy/station aliases.
    No SQL. No DevHub UIDs exposed to players.
]]

SpecialtyIcon = SpecialtyIcon or {}

local function norm(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    return raw:lower()
end

local function fromCat(key)
    local cats = (Config and Config.SkillCategories) or {}
    local def = cats[key]
    if not def then return nil end
    return {
        label = def.label,
        icon = def.icon or 'fa-circle',
        tint = def.tint or '#9a8866',
        skillCategory = key,
    }
end

local function fromExtras(key)
    local extras = (Config and Config.SpecialtyIcons) or {}
    local def = extras[key]
    if not def then return nil end
    return {
        label = def.label,
        icon = def.icon or 'fa-circle',
        tint = def.tint or '#9a8866',
        skillCategory = def.skillCategory,
    }
end

--- Resolve any specialty / station / legacy key → { label, icon, tint, skillCategory? }
---@param key string|nil
---@return table|nil
function SpecialtyIcon.Resolve(key)
    local nk = norm(key)
    if not nk then return nil end

    local hit = fromExtras(nk) or fromCat(nk)
    if hit then return hit end

    local legacy = (Config.SkillLegacyMap or {})[nk] or (Config.SkillLegacyMap or {})[key]
    if legacy then
        hit = fromExtras(legacy) or fromCat(legacy)
        if hit then return hit end
    end

    if SkillTree and SkillTree.ResolveKey then
        local cat = SkillTree.ResolveKey(nk)
        if cat then
            hit = fromExtras(cat) or fromCat(cat)
            if hit then return hit end
        end
    end

    local station = (Config.StationSkillCategory or {})[nk]
    if station and station ~= nk then
        return SpecialtyIcon.Resolve(station)
    end

    return nil
end

--- Flat map for NUI bootstrap (normalized keys → def).
---@return table
function SpecialtyIcon.BuildNuiMap()
    local out = {}
    local function put(k, def)
        local nk = norm(k)
        if not nk or type(def) ~= 'table' or not def.icon then return end
        out[nk] = {
            label = def.label,
            icon = def.icon,
            tint = def.tint or '#9a8866',
            skillCategory = def.skillCategory,
        }
    end

    for k, d in pairs((Config and Config.SkillCategories) or {}) do
        put(k, {
            label = d.label,
            icon = d.icon,
            tint = d.tint,
            skillCategory = k,
        })
    end
    for k, d in pairs((Config and Config.SpecialtyIcons) or {}) do
        put(k, d)
    end
    for alias, target in pairs((Config and Config.SkillLegacyMap) or {}) do
        if not out[norm(alias) or ''] then
            local def = SpecialtyIcon.Resolve(alias) or SpecialtyIcon.Resolve(target)
            if def then put(alias, def) end
        end
    end
    for alias, target in pairs((Config and Config.StationSkillCategory) or {}) do
        if not out[norm(alias) or ''] then
            local def = SpecialtyIcon.Resolve(alias) or SpecialtyIcon.Resolve(target)
            if def then put(alias, def) end
        end
    end
    return out
end
