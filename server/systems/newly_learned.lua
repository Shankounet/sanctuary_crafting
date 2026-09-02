--[[
    systems/newly_learned.lua — catalogue « NOUVEAUX » (serveur > localStorage)
    Sources: level | blueprint | teach | discovery
]]

NewlyLearned = NewlyLearned or {}

local cache = {} -- [identifier] = { [recipeId]=source }
local levelSnap = {} -- [identifier] = { [category]=level }

local function cfg()
    return Config.NewlyLearned or {}
end

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

local function currentLevels(src)
    local cats = (Config.Skills and Config.Skills.categories) or {}
    local out = {}
    if not CraftingSkills or not CraftingSkills.GetLevel then return out end
    for i = 1, #cats do
        local cat = cats[i]
        out[cat] = CraftingSkills.GetLevel(cat, src) or 0
    end
    return out
end

function NewlyLearned.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_player_recipe_unread` (
            `identifier` VARCHAR(60) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `source` VARCHAR(24) NOT NULL DEFAULT 'discovery',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `recipe_id`),
            KEY `idx_ident` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

function NewlyLearned.Load(src)
    local id = ident(src)
    if not id then return end
    cache[id] = {}
    local rows = MySQL.query.await(
        "SELECT recipe_id, source FROM sanctuary_player_recipe_unread WHERE identifier = ?", { id }
    ) or {}
    for i = 1, #rows do
        cache[id][rows[i].recipe_id] = rows[i].source
    end
    -- last-seen levels: RAM only (ml_skills is the sole XP source).
    -- Restart may miss unread level-unlock badges until the first post-restart craft.
    levelSnap[id] = currentLevels(src)
end

function NewlyLearned.List(src)
    if cfg().Enabled == false then return {} end
    local id = ident(src)
    if not id then return {} end
    if not cache[id] then NewlyLearned.Load(src) end
    local out = {}
    for rid, source in pairs(cache[id] or {}) do
        out[#out + 1] = { recipeId = rid, source = source }
    end
    table.sort(out, function(a, b) return a.recipeId < b.recipeId end)
    return out
end

function NewlyLearned.Ids(src)
    local list = NewlyLearned.List(src)
    local ids = {}
    for i = 1, #list do ids[#ids + 1] = list[i].recipeId end
    return ids
end

function NewlyLearned.IsUnread(src, recipeId)
    local id = ident(src)
    if not id then return false end
    if not cache[id] then NewlyLearned.Load(src) end
    return cache[id] and cache[id][recipeId] ~= nil
end

function NewlyLearned.Mark(src, recipeId, source)
    if cfg().Enabled == false then return end
    if type(recipeId) ~= "string" or recipeId == "" then return end
    local id = ident(src)
    if not id then return end
    if not cache[id] then NewlyLearned.Load(src) end
    if cache[id][recipeId] then return end
    source = source or "discovery"
    MySQL.query.await(
        "INSERT IGNORE INTO sanctuary_player_recipe_unread (identifier, recipe_id, source) VALUES (?,?,?)",
        { id, recipeId, source }
    )
    cache[id][recipeId] = source
end

function NewlyLearned.Consult(src, recipeId)
    local id = ident(src)
    if not id then return false end
    if type(recipeId) ~= "string" then return false end
    if not cache[id] then NewlyLearned.Load(src) end
    MySQL.query.await(
        "DELETE FROM sanctuary_player_recipe_unread WHERE identifier = ? AND recipe_id = ?",
        { id, recipeId }
    )
    if cache[id] then cache[id][recipeId] = nil end
    return true
end

local function saveSnap(id, levels)
    levelSnap[id] = levels
end

--- Compare getMenu / AddXP snapshot → mark recipes whose requireLevel is newly met
function NewlyLearned.ScanLevelUnlocks(src)
    if cfg().Enabled == false then return end
    local id = ident(src)
    if not id then return end
    if not cache[id] then NewlyLearned.Load(src) end
    local curr = currentLevels(src)
    local prev = levelSnap[id]
    local hadPrev = prev and next(prev) ~= nil
    if hadPrev then
        for _, recipe in pairs(Config.RecipeById or {}) do
            local need = recipe.requireLevel
            if need then
                local cat = CraftingSkills and CraftingSkills.LevelCategoryForRecipe and CraftingSkills.LevelCategoryForRecipe(recipe)
                if cat then
                    local before = tonumber(prev[cat]) or 0
                    local now = tonumber(curr[cat]) or 0
                    if before < need and now >= need then
                        NewlyLearned.Mark(src, recipe.id, "level")
                    end
                end
            end
        end
    end
    saveSnap(id, curr)
end

CreateThread(function()
    MySQL.ready.await()
    NewlyLearned.EnsureTable()
end)

AddEventHandler("esx:playerLoaded", function(playerId)
    local src = type(playerId) == "number" and playerId or source
    if src then NewlyLearned.Load(src) end
end)

AddEventHandler("playerDropped", function()
    local id = ident(source)
    if id then
        cache[id] = nil
        levelSnap[id] = nil
    end
end)

CraftingCore.On("blueprintLearned", function(src, blueprintId)
    if not src or not blueprintId then return end
    -- mark recipes gated by this blueprint
    for _, r in pairs(Config.RecipeById or {}) do
        local bp = r.requireBlueprint or r.blueprintId
        if bp == blueprintId or r.id == blueprintId then
            NewlyLearned.Mark(src, r.id, "blueprint")
        end
    end
    NewlyLearned.Mark(src, blueprintId, "blueprint")
end)

CraftingCore.On("reverseSuccess", function(src, recipeId)
    if recipeId then NewlyLearned.Mark(src, recipeId, "discovery") end
end)

lib.callback.register("sanctuary_crafting:newlyConsult", function(src, recipeId)
    return { ok = NewlyLearned.Consult(src, recipeId) }
end)

lib.callback.register("sanctuary_crafting:newlyList", function(src)
    return { ok = true, list = NewlyLearned.List(src) }
end)
