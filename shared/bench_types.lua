--[[
    Types de bancs / stations craft.
    Inclut les bancs legacy (scrap/medical/…) + stations import DevHub.
]]

BenchTypes = {
    -- legacy / exemples
    scrap = true,
    medical = true,
    weapons = true,
    survival = true,
    mechanic = true,
    -- stations pack Alex (Shared.Crafts keys)
    ingenieur = true,
    tailleur = true,
    boucherie = true,
    forgeron = true,
    manche_forgeron = true,
    agriculture = true,
    mecano = true,
    schema = true,
    accessoires = true,
    fonderie_forgeron = true,
    decoration = true,
    munition = true,
    cuisine = true,
    reparation_forgeron = true,
    construction = true,
    survie = true,
    armurier = true,
}

---@param category string
---@return boolean
function IsValidBenchCategory(category)
    return BenchTypes[category] == true
end

---@param category string
---@return number|nil
function GetBenchModel(category)
    return Config.BenchModels and Config.BenchModels[category]
end

---@param category string
---@return boolean
function IsValidRecipeCategory(category)
    if not category then return false end
    if Config.RecipeCategories and Config.RecipeCategories[category] then
        return true
    end
    -- fallback: exemples / anciens packs
    return BenchTypes[category] == true
end
