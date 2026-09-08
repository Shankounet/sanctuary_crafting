--[[
    mastery/mastery.lua — maîtrise PAR RECETTE (locale), PAS d'XP global parallèle à ml_skills
]]

Mastery = Mastery or {}

local cache = {} -- [identifier][recipeId] = number

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

function Mastery.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_recipe_mastery` (
            `identifier` VARCHAR(60) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `xp` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`, `recipe_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

function Mastery.Load(src)
    if not Config.Mastery or not Config.Mastery.Enabled then return end
    local id = ident(src)
    if not id then return end
    cache[id] = {}
    local rows = MySQL.query.await(
        'SELECT recipe_id, xp FROM sanctuary_recipe_mastery WHERE identifier = ?', { id }
    ) or {}
    for i = 1, #rows do
        cache[id][rows[i].recipe_id] = tonumber(rows[i].xp) or 0
    end
end

function Mastery.Get(src, recipeId)
    if not Config.Mastery or not Config.Mastery.Enabled then return 0 end
    local id = ident(src)
    if not id then return 0 end
    if not cache[id] then Mastery.Load(src) end
    return (cache[id] and cache[id][recipeId]) or 0
end

function Mastery.Add(src, recipeId, amount)
    if not Config.Mastery or not Config.Mastery.Enabled then return 0 end
    local id = ident(src)
    if not id or not recipeId then return 0 end
    cache[id] = cache[id] or {}
    local max = Config.Mastery.MaxMastery or 100
    local cur = cache[id][recipeId] or 0
    local nxt = math.min(max, cur + (amount or 1))
    cache[id][recipeId] = nxt
    MySQL.query.await([[
        INSERT INTO sanctuary_recipe_mastery (identifier, recipe_id, xp) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = VALUES(xp)
    ]], { id, recipeId, nxt })
    local threshold = (Config.Mastery and (Config.Mastery.MasteredThreshold or Config.Mastery.MaxMastery)) or 100
    if cur < threshold and nxt >= threshold and CraftingCore and CraftingCore.Emit then
        CraftingCore.Emit('recipeMastered', src, recipeId, nxt)
    end
    return nxt
end

CreateThread(function()
    MySQL.ready.await()
    Mastery.EnsureTable()
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    Mastery.Load(playerId)
end)
