Locales = Locales or {}

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

--- UUID v4 (craftId anti-replay)
---@return string
function GenerateCraftId()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end))
end

---@param src number
---@return string|nil
function GetPlayerIdentifierSafe(src)
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if xPlayer and xPlayer.identifier then
        return xPlayer.identifier
    end
    return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifierByType(src, 'license2')
end
