Locales = Locales or {}

--- Traduction simple
---@param key string
---@param ... any
---@return string
function _(key, ...)
    local lang = Config.Locale or 'fr'
    local pack = Locales[lang] or Locales['fr'] or {}
    local str = pack[key] or key
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end

--- Index des recettes par id
CreateThread(function()
    for i = 1, #Config.Recipes do
        local r = Config.Recipes[i]
        Config.RecipeById[r.id] = r
    end
end)

---@param category string
---@return table[]
function GetRecipesForCategory(category)
    local list = {}
    for i = 1, #Config.Recipes do
        local r = Config.Recipes[i]
        if r.category == category then
            list[#list + 1] = r
        end
    end
    return list
end

---@param coords vector3|vector4|table
---@param other vector3|vector4|table
---@return number
function Dist3(coords, other)
    local ax, ay, az = coords.x or coords[1], coords.y or coords[2], coords.z or coords[3]
    local bx, by, bz = other.x or other[1], other.y or other[2], other.z or other[3]
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function DebugPrint(...)
    if Config.Debug then
        print('[sanctuary_crafting]', ...)
    end
end
