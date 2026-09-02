--[[
    systems/recently_crafted.lua — catalogue « RÉCEMMENT FABRIQUÉS » (serveur)
    Unique newest-first, cap Config.RecentlyCrafted.Max. Pas de localStorage.
]]

RecentlyCrafted = RecentlyCrafted or {}

local cache = {} -- [identifier] = { {recipeId, at}, ... } newest first

local function cfg()
    return Config.RecentlyCrafted or {}
end

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

function RecentlyCrafted.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_player_recent` (
            `identifier` VARCHAR(60) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `crafted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `recipe_id`),
            KEY `idx_ident_time` (`identifier`, `crafted_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

function RecentlyCrafted.Load(src)
    local id = ident(src)
    if not id then return end
    local maxN = tonumber(cfg().Max) or 10
    local rows = MySQL.query.await(
        "SELECT recipe_id, UNIX_TIMESTAMP(crafted_at) AS ts FROM sanctuary_player_recent WHERE identifier = ? ORDER BY crafted_at DESC LIMIT ?",
        { id, maxN }
    ) or {}
    cache[id] = {}
    for i = 1, #rows do
        cache[id][i] = { recipeId = rows[i].recipe_id, at = rows[i].ts }
    end
end

function RecentlyCrafted.List(src)
    if cfg().Enabled == false then return {} end
    local id = ident(src)
    if not id then return {} end
    if not cache[id] then RecentlyCrafted.Load(src) end
    local out, seen = {}, {}
    for i = 1, #(cache[id] or {}) do
        local rid = cache[id][i].recipeId
        if rid and not seen[rid] then
            seen[rid] = true
            out[#out + 1] = rid
        end
    end
    local maxN = tonumber(cfg().Max) or 10
    while #out > maxN do out[#out] = nil end
    return out
end

function RecentlyCrafted.Append(src, recipeId)
    if cfg().Enabled == false then return end
    if type(recipeId) ~= "string" or recipeId == "" then return end
    local id = ident(src)
    if not id then return end
    MySQL.query.await([[
        INSERT INTO sanctuary_player_recent (identifier, recipe_id, crafted_at)
        VALUES (?,?,CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE crafted_at = CURRENT_TIMESTAMP
    ]], { id, recipeId })
    if not cache[id] then cache[id] = {} end
    local list = {}
    list[1] = { recipeId = recipeId, at = os.time() }
    for i = 1, #cache[id] do
        if cache[id][i].recipeId ~= recipeId then
            list[#list + 1] = cache[id][i]
        end
    end
    local maxN = tonumber(cfg().Max) or 10
    while #list > maxN do list[#list] = nil end
    cache[id] = list
    MySQL.query.await([[
        DELETE FROM sanctuary_player_recent WHERE identifier = ? AND recipe_id NOT IN (
            SELECT recipe_id FROM (
                SELECT recipe_id FROM sanctuary_player_recent WHERE identifier = ? ORDER BY crafted_at DESC LIMIT ?
            ) t
        )
    ]], { id, id, maxN })
end

CreateThread(function()
    MySQL.ready.await()
    RecentlyCrafted.EnsureTable()
end)

AddEventHandler("esx:playerLoaded", function(playerId)
    local src = type(playerId) == "number" and playerId or source
    if src then RecentlyCrafted.Load(src) end
end)

CraftingCore.On("craftCompleted", function(src, craft)
    if craft and craft.recipeId then
        RecentlyCrafted.Append(src, craft.recipeId)
    end
end)

CraftingCore.On("queueCollected", function(src, entry)
    if entry and entry.recipeId then
        RecentlyCrafted.Append(src, entry.recipeId)
    end
end)
