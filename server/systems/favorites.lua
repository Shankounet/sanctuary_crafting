Favorites = Favorites or {}
local cache = {}

local function ident(src) return GetPlayerIdentifierSafe(src) end

function Favorites.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_favorites` (
            `identifier` VARCHAR(60) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`identifier`, `recipe_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

function Favorites.Load(src)
    local id = ident(src)
    if not id then return end
    cache[id] = {}
    local rows = MySQL.query.await('SELECT recipe_id FROM sanctuary_favorites WHERE identifier=?', { id }) or {}
    for i = 1, #rows do cache[id][rows[i].recipe_id] = true end
end

function Favorites.Get(src)
    local id = ident(src)
    if not id then return {} end
    if not cache[id] then Favorites.Load(src) end
    local list = {}
    for rid in pairs(cache[id] or {}) do list[#list + 1] = rid end
    return list
end

function Favorites.Toggle(src, recipeId)
    local id = ident(src)
    if not id or not recipeId then return false end
    if not cache[id] then Favorites.Load(src) end
    if cache[id][recipeId] then
        cache[id][recipeId] = nil
        MySQL.query.await('DELETE FROM sanctuary_favorites WHERE identifier=? AND recipe_id=?', { id, recipeId })
        return false
    end
    cache[id][recipeId] = true
    MySQL.insert.await('INSERT IGNORE INTO sanctuary_favorites (identifier, recipe_id) VALUES (?,?)', { id, recipeId })
    return true
end

CreateThread(function()
    MySQL.ready.await()
    Favorites.EnsureTable()
end)

AddEventHandler('esx:playerLoaded', function(pid) Favorites.Load(pid) end)

lib.callback.register('sanctuary_crafting:toggleFavorite', function(src, recipeId)
    local favored = Favorites.Toggle(src, recipeId)
    return { ok = true, favored = favored, favorites = Favorites.Get(src) }
end)
