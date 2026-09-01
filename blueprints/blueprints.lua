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

lib.callback.register('sanctuary_crafting:learnBlueprint', function(src, bpId)
    local ok, err = Blueprints.Learn(src, bpId)
    return { ok = ok, reason = err }
end)

lib.callback.register('sanctuary_crafting:forgetBlueprint', function(src, bpId)
    local ok, err = Blueprints.Forget(src, bpId)
    return { ok = ok, reason = err }
end)

lib.callback.register('sanctuary_crafting:listBlueprints', function(src)
    return { ok = true, list = Blueprints.List(src) }
end)
