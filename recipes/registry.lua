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
    if type(r.category) ~= 'string' or not IsValidBenchCategory(r.category) then
        return fail(r.id, 'category invalide: ' .. tostring(r.category))
    end
    if type(r.ingredients) ~= 'table' or #r.ingredients < 1 then
        return fail(r.id, 'ingredients vides')
    end
    for i = 1, #r.ingredients do
        local ing = r.ingredients[i]
        if type(ing.item) ~= 'string' or type(ing.count) ~= 'number' or ing.count < 1 then
            return fail(r.id, 'ingredient #' .. i)
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
    local okCount, bad = 0, 0
    for i = 1, #(Config.Recipes or {}) do
        local r = Config.Recipes[i]
        if RecipeRegistry.Validate(r) then
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
    DebugPrint('RecipeRegistry:', okCount, 'ok,', bad, 'bad')
    return okCount
end

---@param category string
---@return table[]
function GetRecipesForCategory(category)
    local list = {}
    for i = 1, #(Config.Recipes or {}) do
        local r = Config.Recipes[i]
        if r.category == category and Config.RecipeById[r.id] then
            list[#list + 1] = r
        end
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
