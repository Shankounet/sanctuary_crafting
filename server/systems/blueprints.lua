--[[
    blueprints/blueprints.lua — Learn / Has / Forget + SQL + item physique
]]

Blueprints = Blueprints or {}

local cache = {} -- [identifier] = { [blueprintId] = true }

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

function Blueprints.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_player_recipes` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(60) NOT NULL,
            `blueprint_id` VARCHAR(64) NOT NULL,
            `learned_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_player_bp` (`identifier`, `blueprint_id`),
            KEY `idx_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

function Blueprints.LoadPlayer(src)
    local id = ident(src)
    if not id then return end
    cache[id] = {}
    local rows = MySQL.query.await(
        'SELECT blueprint_id FROM sanctuary_player_recipes WHERE identifier = ?', { id }
    ) or {}
    for i = 1, #rows do
        cache[id][rows[i].blueprint_id] = true
    end
end

function Blueprints.Has(src, blueprintId)
    if not Config.Blueprints or not Config.Blueprints.Enabled then
        return true -- gates ignored when system off
    end
    if not blueprintId then return true end
    local id = ident(src)
    if not id then return false end
    if not cache[id] then Blueprints.LoadPlayer(src) end
    return cache[id] and cache[id][blueprintId] == true
end

function Blueprints.Learn(src, blueprintId)
    if not Config.Blueprints or not Config.Blueprints.Enabled then
        return false, 'blueprints_disabled'
    end
    if not blueprintId then return false, 'craft_invalid' end
    local id = ident(src)
    if not id then return false, 'craft_invalid' end
    if Blueprints.Has(src, blueprintId) then return true, 'already' end
    MySQL.insert.await(
        'INSERT IGNORE INTO sanctuary_player_recipes (identifier, blueprint_id) VALUES (?, ?)',
        { id, blueprintId }
    )
    cache[id] = cache[id] or {}
    cache[id][blueprintId] = true
    CraftingCore.Emit('blueprintLearned', src, blueprintId)
    CraftingCore.Emit('recipeLearned', src, blueprintId)
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = _('blueprint_learned', blueprintId) })
    return true
end

function Blueprints.Forget(src, blueprintId)
    if not Config.Blueprints or not Config.Blueprints.Enabled then
        return false, 'blueprints_disabled'
    end
    if not Config.Blueprints.ForgetEnabled then return false, 'forget_disabled' end
    local id = ident(src)
    if not id or not blueprintId then return false end
    MySQL.query.await(
        'DELETE FROM sanctuary_player_recipes WHERE identifier = ? AND blueprint_id = ?',
        { id, blueprintId }
    )
    if cache[id] then cache[id][blueprintId] = nil end
    CraftingCore.Emit('blueprintForgotten', src, blueprintId)
    return true
end


--- No blueprintId → implicitly known. requiresLearn → knowledge row (recipe.id).
function Blueprints.KnowsRecipe(src, recipe)
    if not recipe then return false end
    local bpId = recipe.requireBlueprint or recipe.blueprintId
    if bpId then
        if not Config.Blueprints or not Config.Blueprints.Enabled then
            return true
        end
        return Blueprints.Has(src, bpId)
    end
    if recipe.requiresLearn == true then
        return Blueprints.Has(src, recipe.id)
    end
    return true
end

function Blueprints.GrantKnowledge(src, recipe, source)
    if not recipe then return false end
    local bpId = recipe.requireBlueprint or recipe.blueprintId
    if bpId then
        local ok = Blueprints.Learn(src, bpId)
        if ok and NewlyLearned and NewlyLearned.Mark then
            NewlyLearned.Mark(src, recipe.id, source or "blueprint")
        end
        return ok and true or false
    end
    -- knowledge row stored as blueprint_id = recipe.id
    local ok = Blueprints.Learn(src, recipe.id)
    if ok and NewlyLearned and NewlyLearned.Mark then
        NewlyLearned.Mark(src, recipe.id, source or "discovery")
    end
    return ok and true or false
end

function Blueprints.List(src)
    local id = ident(src)
    if not id then return {} end
    if not cache[id] then Blueprints.LoadPlayer(src) end
    local list = {}
    for bp in pairs(cache[id] or {}) do list[#list + 1] = bp end
    return list
end

--- Use physical blueprint item (metadata.blueprintId)
exports('useBlueprintItem', function(event, item, inventory, slot, data)
    if event ~= 'usingItem' then return end
    if not Config.Blueprints or not Config.Blueprints.Enabled then return false end
    local src = inventory.id
    local meta = item.metadata or {}
    local bpId = meta.blueprintId or meta.blueprint_id
    if not bpId then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('blueprint_invalid') })
        return false
    end
    local ok = Blueprints.Learn(src, bpId)
    if ok then
        exports.ox_inventory:RemoveItem(src, item.name, 1, nil, slot)
    end
    return false
end)

CreateThread(function()
    MySQL.ready.await()
    Blueprints.EnsureTable()
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    Blueprints.LoadPlayer(playerId)
end)

RegisterNetEvent('sanctuary_crafting:server:requestBlueprints', function()
    Blueprints.LoadPlayer(source)
end)

-- CLOSE THE HOLE: keep callback name, require item use OR admin. No client grant-any.
lib.callback.register('sanctuary_crafting:learnBlueprint', function(src, bpId)
    if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then
        local ok, err = Blueprints.Learn(src, bpId)
        return { ok = ok, reason = err }
    end
    if CraftingAnomaly then
        CraftingAnomaly.Warn('learn_bypass', src, { bpId = bpId })
    end
    return { ok = false, reason = 'admin_denied' }
end)

lib.callback.register('sanctuary_crafting:forgetBlueprint', function(src, bpId)
    if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then
        local ok, err = Blueprints.Forget(src, bpId)
        return { ok = ok, reason = err }
    end
    if CraftingAnomaly then
        CraftingAnomaly.Warn('forget_bypass', src, { bpId = bpId })
    end
    return { ok = false, reason = 'admin_denied' }
end)

lib.callback.register('sanctuary_crafting:listBlueprints', function(src)
    return { ok = true, list = Blueprints.List(src) }
end)
