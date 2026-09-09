--[[
    shared/craft_taxonomy.lua — classification craft (SoT après normalize)

    - craftCategoryUid / craftSubcategoryUid explicites
    - Indépendant de ML Skills et de la station
    - Index recipesByCategory / recipesBySubcategory au rebuild
]]

CraftTaxonomy = CraftTaxonomy or {}

local FALLBACK_UID = 'divers'

local function cats()
    return Config.CraftCategories or {}
end

---@param uid string|nil
---@return CraftCategoryDef|nil
function CraftTaxonomy.GetCategory(uid)
    if type(uid) ~= 'string' or uid == '' then return nil end
    return cats()[uid]
end

---@param catUid string|nil
---@param subUid string|nil
---@return CraftSubcategoryDef|nil
function CraftTaxonomy.GetSubcategory(catUid, subUid)
    local cat = CraftTaxonomy.GetCategory(catUid)
    if not cat or type(subUid) ~= 'string' or subUid == '' then return nil end
    local subs = cat.subcategories
    if type(subs) ~= 'table' then return nil end
    return subs[subUid]
end

---@param uid string|nil
---@return boolean
function CraftTaxonomy.IsValidCategory(uid)
    local cat = CraftTaxonomy.GetCategory(uid)
    return cat ~= nil and cat.enabled ~= false
end

---@param catUid string|nil
---@param subUid string|nil
---@return boolean
function CraftTaxonomy.IsValidSubcategory(catUid, subUid)
    local sub = CraftTaxonomy.GetSubcategory(catUid, subUid)
    return sub ~= nil and sub.enabled ~= false
end

---@return table[] sorted enabled mains (no "all")
function CraftTaxonomy.ListCategories()
    local out = {}
    for uid, def in pairs(cats()) do
        if def and def.enabled ~= false then
            out[#out + 1] = def
        end
    end
    table.sort(out, function(a, b)
        return (a.sortOrder or 99) < (b.sortOrder or 99)
    end)
    return out
end

---@param catUid string
---@return table[]
function CraftTaxonomy.ListSubcategories(catUid)
    local cat = CraftTaxonomy.GetCategory(catUid)
    local out = {}
    if not cat or type(cat.subcategories) ~= 'table' then return out end
    for _, def in pairs(cat.subcategories) do
        if def and def.enabled ~= false then
            out[#out + 1] = def
        end
    end
    table.sort(out, function(a, b)
        return (a.sortOrder or 99) < (b.sortOrder or 99)
    end)
    return out
end

--- Payload joueur/admin: catégories + sous-cats (labels FR depuis config)
function CraftTaxonomy.PayloadForClient()
    local list = {}
    for _, def in ipairs(CraftTaxonomy.ListCategories()) do
        local subs = {}
        for _, s in ipairs(CraftTaxonomy.ListSubcategories(def.uid)) do
            subs[#subs + 1] = {
                uid = s.uid,
                label = s.label,
                icon = s.icon,
                sortOrder = s.sortOrder,
            }
        end
        list[#list + 1] = {
            uid = def.uid,
            label = def.label,
            icon = def.icon,
            sortOrder = def.sortOrder,
            accent = def.accent,
            subcategories = subs,
        }
    end
    return list
end

--- Suggestion admin-only (jamais auto-vérité). Retourne category, subcategory, source.
---@param recipe table
---@return { category: string, subcategory: string|nil, source: string, legacyCategory: string|nil }
function CraftTaxonomy.SuggestClassification(recipe)
    if type(recipe) ~= 'table' then
        return { category = FALLBACK_UID, subcategory = nil, source = 'fallback', legacyCategory = nil }
    end
    local rid = recipe.id
    -- Overrides (admin migration examples) beat bare legacy category; explicit uid still wins in Normalize
    local overrides = Config.CraftRecipeClassificationOverrides or {}
    if type(rid) == 'string' and overrides[rid] then
        local o = overrides[rid]
        return {
            category = o.category or FALLBACK_UID,
            subcategory = o.subcategory,
            source = 'override',
            legacyCategory = recipe.category,
        }
    end
    if type(recipe.craftCategoryUid) == 'string' and recipe.craftCategoryUid ~= '' then
        return {
            category = recipe.craftCategoryUid,
            subcategory = recipe.craftSubcategoryUid,
            source = 'explicit',
            legacyCategory = recipe.category,
        }
    end
    local legacy = recipe.category
    local map = Config.CraftCategoryLegacyMap or {}
    if type(legacy) == 'string' and map[legacy] then
        local m = map[legacy]
        return {
            category = m.category or FALLBACK_UID,
            subcategory = m.subcategory,
            source = 'legacy_map',
            legacyCategory = legacy,
        }
    end
    return {
        category = FALLBACK_UID,
        subcategory = nil,
        source = 'fallback',
        legacyCategory = legacy,
    }
end

--- Normalise la classification sur la recette (SoT).
--- Ne lit PAS les labels / ox types / ML Skills / station pour inventer une cat.
---@param recipe table
---@return table recipe
function CraftTaxonomy.NormalizeRecipeClassification(recipe)
    if type(recipe) ~= 'table' then return recipe end

    local suggested = CraftTaxonomy.SuggestClassification(recipe)
    local catUid = suggested.category
    local subUid = suggested.subcategory

    -- Prefer already-explicit valid uids when present
    if type(recipe.craftCategoryUid) == 'string' and recipe.craftCategoryUid ~= '' then
        catUid = recipe.craftCategoryUid
        subUid = recipe.craftSubcategoryUid
    end

    local invalid = false
    if not CraftTaxonomy.IsValidCategory(catUid) then
        invalid = true
        catUid = FALLBACK_UID
        subUid = nil
    elseif subUid ~= nil and subUid ~= '' and not CraftTaxonomy.IsValidSubcategory(catUid, subUid) then
        -- drop unknown subcategory, keep main
        subUid = nil
    end
    if subUid == '' then subUid = nil end

    recipe.craftCategoryUid = catUid
    recipe.craftSubcategoryUid = subUid
    recipe._craftCategorySource = suggested.source
    recipe._craftCategoryInvalid = invalid or nil
    recipe._craftCategoryLegacy = suggested.legacyCategory

    -- Deprecated mirror for transitional filters only (not SoT)
    -- Keep raw legacy in _legacyCategory; do not overwrite recipe.category if it was a pack field
    -- used elsewhere — station matching must use recipe.station.
    recipe._legacyUiCategory = recipe.category

    local catDef = CraftTaxonomy.GetCategory(catUid)
    recipe._craftCategoryLabel = catDef and catDef.label or catUid
    recipe._craftCategoryIcon = catDef and catDef.icon or 'fa-solid fa-tag'
    local subDef = CraftTaxonomy.GetSubcategory(catUid, subUid)
    recipe._craftSubcategoryLabel = subDef and subDef.label or nil

    return recipe
end

-- Alias demandé par le brief
normalizeRecipeClassification = function(recipe)
    return CraftTaxonomy.NormalizeRecipeClassification(recipe)
end

---------------------------------------------------------------------------
-- Index au load (pas de filtre lourd chaque frame)
---------------------------------------------------------------------------

CraftTaxonomy.recipesByCategory = {}
CraftTaxonomy.recipesBySubcategory = {}

function CraftTaxonomy.RebuildIndexes()
    local byCat = {}
    local bySub = {}
    for id, r in pairs(Config.RecipeById or {}) do
        if type(r) == 'table' then
            CraftTaxonomy.NormalizeRecipeClassification(r)
            local c = r.craftCategoryUid or FALLBACK_UID
            byCat[c] = byCat[c] or {}
            byCat[c][#byCat[c] + 1] = id
            if type(r.craftSubcategoryUid) == 'string' and r.craftSubcategoryUid ~= '' then
                local key = c .. ':' .. r.craftSubcategoryUid
                bySub[key] = bySub[key] or {}
                bySub[key][#bySub[key] + 1] = id
            end
            if r._craftCategoryInvalid then
                print(('[^3sanctuary_crafting^0] craftCategory invalide [%s] → Divers (legacy=%s)'):format(
                    tostring(id), tostring(r._craftCategoryLegacy or r.category)))
            end
        end
    end
    CraftTaxonomy.recipesByCategory = byCat
    CraftTaxonomy.recipesBySubcategory = bySub
    Config.RecipesByCraftCategory = byCat
    Config.RecipesByCraftSubcategory = bySub
end

---@param catUid string
---@return string[] recipe ids
function CraftTaxonomy.RecipeIdsForCategory(catUid)
    return CraftTaxonomy.recipesByCategory[catUid] or {}
end

---@param catUid string
---@param subUid string
---@return string[]
function CraftTaxonomy.RecipeIdsForSubcategory(catUid, subUid)
    return CraftTaxonomy.recipesBySubcategory[(catUid or '') .. ':' .. (subUid or '')] or {}
end

--- Rapport d'audit migration (admin / docs)
function CraftTaxonomy.BuildMigrationAudit()
    local byLegacy = {}
    local rows = {}
    for id, r in pairs(Config.RecipeById or {}) do
        if type(r) == 'table' then
            local sug = CraftTaxonomy.SuggestClassification(r)
            local legacy = tostring(r.category or r._legacyUiCategory or '?')
            byLegacy[legacy] = byLegacy[legacy] or { count = 0, suggested = {}, samples = {} }
            local bucket = byLegacy[legacy]
            bucket.count = bucket.count + 1
            local sk = sug.category .. '>' .. tostring(sug.subcategory or '-')
            bucket.suggested[sk] = (bucket.suggested[sk] or 0) + 1
            if #bucket.samples < 5 then
                bucket.samples[#bucket.samples + 1] = id
            end
            rows[#rows + 1] = {
                recipeId = id,
                label = r.label,
                legacyCategory = legacy,
                suggestedCategory = sug.category,
                suggestedSubcategory = sug.subcategory,
                source = sug.source,
                currentCategory = r.craftCategoryUid,
                currentSubcategory = r.craftSubcategoryUid,
            }
        end
    end
    local summary = {}
    for legacy, info in pairs(byLegacy) do
        local topSug, topN = FALLBACK_UID, 0
        for sk, n in pairs(info.suggested) do
            if n > topN then topSug, topN = sk, n end
        end
        summary[#summary + 1] = {
            legacyCategory = legacy,
            count = info.count,
            suggested = topSug,
            samples = info.samples,
        }
    end
    table.sort(summary, function(a, b) return (a.count or 0) > (b.count or 0) end)
    return { summary = summary, rows = rows }
end

-- Compat: IsValidRecipeCategory → craft taxonomy (+ legacy map keys for soft validate)
function IsValidRecipeCategory(category)
    if not category then return false end
    if CraftTaxonomy.IsValidCategory(category) then return true end
    if Config.CraftCategoryLegacyMap and Config.CraftCategoryLegacyMap[category] then return true end
    if Config.RecipeCategories and Config.RecipeCategories[category] then return true end
    return BenchTypes and BenchTypes[category] == true
end
