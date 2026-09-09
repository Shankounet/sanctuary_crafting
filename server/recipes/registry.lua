--[[
    recipes/registry.lua — index + validation schéma recettes
]]

RecipeRegistry = RecipeRegistry or {}

local validated = false

local function fail(id, msg)
    print(('[^1sanctuary_crafting^0] recette invalide [%s]: %s'):format(tostring(id), msg))
    return false
end

---@param r table
---@return boolean
function RecipeRegistry.Validate(r)
    if type(r) ~= 'table' then return fail('?', 'pas une table') end
    if type(r.id) ~= 'string' or r.id == '' then return fail(r.id, 'id manquant') end
    if type(r.label) ~= 'string' then return fail(r.id, 'label manquant') end
    -- craftCategoryUid = taxonomie UI ; station = banc (BenchTypes).
    -- recipe.category (legacy pack) est déprécié pour l'UI — normalisé via CraftTaxonomy.
    if CraftTaxonomy and CraftTaxonomy.NormalizeRecipeClassification then
        CraftTaxonomy.NormalizeRecipeClassification(r)
    end
    if type(r.craftCategoryUid) ~= 'string' or r.craftCategoryUid == '' then
        return fail(r.id, 'craftCategoryUid manquant')
    end
    if r._craftCategoryInvalid then
        print(('[^3sanctuary_crafting^0] craftCategory invalide [%s] → Divers (legacy=%s)'):format(
            tostring(r.id), tostring(r._craftCategoryLegacy or r.category)))
    end
    -- Soft: legacy category still useful for migration audit
    if type(r.category) ~= 'string' or r.category == '' then
        -- allow if craftCategoryUid present (new recipes)
        r.category = r.craftCategoryUid
    end
    if r.station ~= nil and type(r.station) == 'string' and r.station ~= '' then
        if not IsValidBenchCategory(r.station) then
            print(('[^3sanctuary_crafting^0] station inconnue [%s]: %s'):format(tostring(r.id), tostring(r.station)))
        end
    elseif type(r.station) ~= 'string' or r.station == '' then
        print(('[^3sanctuary_crafting^0] station manquante [%s]'):format(tostring(r.id)))
    end
    local hasSteps = type(r.steps) == 'table' and #r.steps > 0
    if hasSteps then
        for si = 1, #r.steps do
            local step = r.steps[si]
            if type(step) ~= 'table' then return fail(r.id, 'step #' .. si) end
            if type(step.ingredients) ~= 'table' or #step.ingredients < 1 then
                return fail(r.id, 'step #' .. si .. ' ingredients')
            end
            for i = 1, #step.ingredients do
                local ing = step.ingredients[i]
                if type(ing.item) ~= 'string' or type(ing.count) ~= 'number' or ing.count < 1 then
                    return fail(r.id, 'step #' .. si .. ' ingredient #' .. i)
                end
            end
            if step.duration ~= nil and (type(step.duration) ~= 'number' or step.duration < 500) then
                return fail(r.id, 'step #' .. si .. ' duration')
            end
        end
        r.ingredients = r.ingredients or {}
    else
        if type(r.ingredients) ~= 'table' or #r.ingredients < 1 then
            return fail(r.id, 'ingredients vides')
        end
    end
    for i = 1, #(r.ingredients or {}) do
        local ing = r.ingredients[i]
        if type(ing.item) ~= 'string' or type(ing.count) ~= 'number' or ing.count < 1 then
            return fail(r.id, 'ingredient #' .. i)
        end
    end
    -- chain: liste d'ids recettes suivants (serveur avance sous même craftUID / project)
    if r.chain ~= nil then
        if type(r.chain) == 'string' then
            r.chain = { r.chain }
        elseif type(r.chain) ~= 'table' then
            return fail(r.id, 'chain invalide')
        end
    end
    if type(r.result) ~= 'table' or type(r.result.item) ~= 'string' then
        return fail(r.id, 'result invalide')
    end
    r.result.count = r.result.count or 1
    if type(r.duration) ~= 'number' or r.duration < 500 then
        return fail(r.id, 'duration invalide')
    end
    return true
end

function RecipeRegistry.Rebuild()
    Config.RecipeById = {}
    local working = {}
    for i = 1, #(Config.Recipes or {}) do
        local src = Config.Recipes[i]
        local clone = (RecipeSnapshot and RecipeSnapshot.Clone and RecipeSnapshot.Clone(src)) or src
        working[#working + 1] = clone
    end
    if RecipeOverlay and RecipeOverlay.MergeInto then
        RecipeOverlay.MergeInto(working)
    end
    local okCount, bad, skipped = 0, 0, 0
    for i = 1, #working do
        local r = working[i]
        if r and SkillTree and SkillTree.NormalizeRecipe then
            SkillTree.NormalizeRecipe(r)
        end
        if r and r._disabled then
            skipped = skipped + 1
        elseif RecipeRegistry.Validate(r) then
            if Config.RecipeById[r.id] then
                print(('[^3sanctuary_crafting^0] id dupliqué: %s'):format(r.id))
            end
            Config.RecipeById[r.id] = r
            okCount = okCount + 1
        else
            bad = bad + 1
        end
    end
    validated = true
    if CraftTaxonomy and CraftTaxonomy.RebuildIndexes then
        CraftTaxonomy.RebuildIndexes()
    end
    DebugPrint('RecipeRegistry:', okCount, 'ok,', bad, 'bad, skipped', skipped)
    return okCount
end

---@param category string bench/station id (NOM HISTORIQUE — ce n'est PAS craftCategoryUid)
---@return table[]
--- Recettes pour un banc : match recipe.station uniquement.
--- Legacy: si station absente et recipe.category est un BenchType, fallback.
function GetRecipesForCategory(category)
    local list = {}
    for _, r in pairs(Config.RecipeById or {}) do
        if r and not r._disabled then
            local station = r.station
            if (not station or station == '') and r.category and IsValidBenchCategory and IsValidBenchCategory(r.category) then
                station = r.category
            end
            if station == category then
                list[#list + 1] = r
            end
        end
    end
    return list
end

function GetRecipesForStation(station)
    return GetRecipesForCategory(station)
end

--- Recettes indexées par taxonomie craft (SoT craftCategoryUid)
function GetRecipesForCraftCategory(craftCategoryUid)
    local list = {}
    local ids = CraftTaxonomy and CraftTaxonomy.RecipeIdsForCategory and CraftTaxonomy.RecipeIdsForCategory(craftCategoryUid) or {}
    for i = 1, #ids do
        local r = Config.RecipeById[ids[i]]
        if r and not r._disabled then list[#list + 1] = r end
    end
    return list
end

---@param id string
---@return table|nil
function RecipeRegistry.Get(id)
    return Config.RecipeById[id]
end

---@return table[]
function RecipeRegistry.GetAll()
    local list = {}
    for id, r in pairs(Config.RecipeById) do
        list[#list + 1] = r
    end
    return list
end

CreateThread(function()
    Wait(0)
    RecipeRegistry.Rebuild()
end)
