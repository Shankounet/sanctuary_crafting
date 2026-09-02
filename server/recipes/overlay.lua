--[[
    recipes/overlay.lua — SQL overlay on top of Config.Recipes
    Overlay only: disabled / version / payload / updatedAt / updatedBy.
    Do NOT dump the config pack (379 imports) into SQL on boot.
]]

RecipeOverlay = RecipeOverlay or {}

local rows = {} -- [recipe_id] = { payload, disabled, version, updatedAt, updatedBy }
local ready = false

function RecipeOverlay.EnsureTables()
    if not MySQL or not MySQL.query or not MySQL.query.await then return end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_recipes` (
            `recipe_id` VARCHAR(64) NOT NULL,
            `payload` LONGTEXT NOT NULL,
            `disabled` TINYINT(1) NOT NULL DEFAULT 0,
            `version` INT NOT NULL DEFAULT 1,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `updated_by` VARCHAR(60) NULL,
            PRIMARY KEY (`recipe_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_recipe_versions` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `recipe_id` VARCHAR(64) NOT NULL,
            `version` INT NOT NULL,
            `payload` LONGTEXT NOT NULL,
            `disabled` TINYINT(1) NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_by` VARCHAR(60) NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_recipe_ver` (`recipe_id`, `version`),
            KEY `idx_recipe` (`recipe_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

function RecipeOverlay.Load()
    rows = {}
    if not MySQL or not MySQL.query or not MySQL.query.await then
        ready = true
        return 0
    end
    local list = MySQL.query.await('SELECT recipe_id, payload, disabled, version, updated_at, updated_by FROM sanctuary_recipes') or {}
    for i = 1, #list do
        local r = list[i]
        local payload = r.payload
        if type(payload) == 'string' then
            local ok, decoded = pcall(json.decode, payload)
            payload = (ok and type(decoded) == 'table') and decoded or {}
        elseif type(payload) ~= 'table' then
            payload = {}
        end
        rows[r.recipe_id] = {
            payload = payload,
            disabled = tonumber(r.disabled) == 1,
            version = tonumber(r.version) or 1,
            updatedAt = r.updated_at,
            updatedBy = r.updated_by,
        }
    end
    ready = true
    DebugPrint('RecipeOverlay loaded', #list, 'rows')
    return #list
end

function RecipeOverlay.Ready()
    return ready
end

function RecipeOverlay.Get(recipeId)
    return rows[recipeId]
end

local function mergeFields(base, overlay)
    if type(overlay) ~= 'table' then return base end
    for k, v in pairs(overlay) do
        if k ~= '_version' and k ~= '_disabled' then
            base[k] = v
        end
    end
    return base
end

--- Merge overlay into a working list of cloned config recipes.
--- SQL-only recipes (not in Config) are appended. Disabled marked _disabled.
function RecipeOverlay.MergeInto(list)
    list = list or {}
    local byId = {}
    for i = 1, #list do
        local r = list[i]
        if r and r.id then byId[r.id] = r end
    end
    for id, ov in pairs(rows) do
        local target = byId[id]
        if not target then
            target = {}
            list[#list + 1] = target
            byId[id] = target
        end
        mergeFields(target, ov.payload)
        target.id = id
        target._version = ov.version
        target._updatedAt = ov.updatedAt
        target._updatedBy = ov.updatedBy
        target._overlay = true
        if ov.disabled then
            target._disabled = true
        end
    end
    return list
end

local function actorOf(src)
    if not src or src == 0 then return 'console' end
    return GetPlayerIdentifierSafe(src) or ('src:' .. tostring(src))
end

--- Persist overlay row, bump version, history, rebuild.
function RecipeOverlay.Save(recipe, src, opts)
    opts = opts or {}
    if type(recipe) ~= 'table' or type(recipe.id) ~= 'string' or recipe.id == '' then
        return false, 'craft_invalid'
    end
    if RecipeRegistry and RecipeRegistry.Validate then
        local check = RecipeSnapshot and RecipeSnapshot.Clone(recipe) or recipe
        if not RecipeRegistry.Validate(check) then
            return false, 'craft_invalid'
        end
    end
    local prev = rows[recipe.id]
    local version = (prev and (prev.version or 0) or 0) + 1
    local disabled = recipe._disabled == true or opts.disabled == true
    if opts.disabled == false then disabled = false end
    local payload = RecipeSnapshot and RecipeSnapshot.Clone(recipe) or recipe
    payload._disabled = nil
    payload._version = nil
    payload._overlay = nil
    payload._updatedAt = nil
    payload._updatedBy = nil
    local encoded = json.encode(payload)
    local by = actorOf(src)
    MySQL.query.await([[
        INSERT INTO sanctuary_recipes (recipe_id, payload, disabled, version, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE payload = VALUES(payload), disabled = VALUES(disabled),
            version = VALUES(version), updated_by = VALUES(updated_by)
    ]], { recipe.id, encoded, disabled and 1 or 0, version, by })
    pcall(function()
        MySQL.insert.await(
            'INSERT INTO sanctuary_recipe_versions (recipe_id, version, payload, disabled, updated_by) VALUES (?, ?, ?, ?, ?)',
            { recipe.id, version, encoded, disabled and 1 or 0, by }
        )
    end)
    rows[recipe.id] = {
        payload = payload,
        disabled = disabled,
        version = version,
        updatedAt = os.date('%Y-%m-%d %H:%M:%S'),
        updatedBy = by,
    }
    if RecipeRegistry and RecipeRegistry.Rebuild then
        RecipeRegistry.Rebuild()
    end
    if CraftingCore and CraftingCore.Emit then
        CraftingCore.Emit('adminRecipeEdit', src, recipe.id, version, disabled)
    end
    return true, version
end

function RecipeOverlay.SetDisabled(recipeId, disabled, src)
    if type(recipeId) ~= 'string' then return false, 'craft_invalid' end
    local prev = rows[recipeId]
    local payload = (prev and prev.payload) or {}
    if not prev then
        local live = RecipeRegistry and RecipeRegistry.Get and RecipeRegistry.Get(recipeId)
        if live then
            payload = RecipeSnapshot and RecipeSnapshot.Clone(live) or live
        else
            return false, 'craft_invalid'
        end
    end
    payload.id = recipeId
    payload._disabled = disabled and true or false
    return RecipeOverlay.Save(payload, src, { disabled = disabled and true or false })
end

function RecipeOverlay.Restore(recipeId, version, src)
    version = tonumber(version)
    if type(recipeId) ~= 'string' or not version then return false, 'craft_invalid' end
    local hist = MySQL.query.await(
        'SELECT payload, disabled FROM sanctuary_recipe_versions WHERE recipe_id = ? AND version = ? LIMIT 1',
        { recipeId, version }
    )
    if not hist or not hist[1] then return false, 'craft_invalid' end
    local payload = hist[1].payload
    if type(payload) == 'string' then
        local ok, decoded = pcall(json.decode, payload)
        payload = (ok and type(decoded) == 'table') and decoded or nil
    end
    if type(payload) ~= 'table' then return false, 'craft_invalid' end
    payload.id = recipeId
    return RecipeOverlay.Save(payload, src, { disabled = tonumber(hist[1].disabled) == 1 })
end

function RecipeOverlay.Versions(recipeId)
    if type(recipeId) ~= 'string' then return {} end
    local list = MySQL.query.await(
        'SELECT version, disabled, updated_at, updated_by FROM sanctuary_recipe_versions WHERE recipe_id = ? ORDER BY version DESC LIMIT 50',
        { recipeId }
    ) or {}
    return list
end

--- Admin catalog: config + overlay (including disabled). Never dumps ox items.
function RecipeOverlay.ListForAdmin()
    local list = {}
    local seen = {}
    for i = 1, #(Config.Recipes or {}) do
        local r = Config.Recipes[i]
        if r and r.id then
            local clone = RecipeSnapshot and RecipeSnapshot.Clone(r) or r
            local ov = rows[r.id]
            if ov then
                mergeFields(clone, ov.payload)
                clone._version = ov.version
                clone._disabled = ov.disabled
                clone._updatedAt = ov.updatedAt
                clone._updatedBy = ov.updatedBy
                clone._overlay = true
            else
                clone._version = 0
                clone._disabled = false
                clone._overlay = false
            end
            clone.id = r.id
            list[#list + 1] = clone
            seen[r.id] = true
        end
    end
    for id, ov in pairs(rows) do
        if not seen[id] then
            local clone = RecipeSnapshot and RecipeSnapshot.Clone(ov.payload) or (ov.payload or {})
            clone.id = id
            clone._version = ov.version
            clone._disabled = ov.disabled
            clone._updatedAt = ov.updatedAt
            clone._updatedBy = ov.updatedBy
            clone._overlay = true
            clone._sqlOnly = true
            list[#list + 1] = clone
        end
    end
    table.sort(list, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

CreateThread(function()
    if not MySQL or not MySQL.ready then
        ready = true
        return
    end
    MySQL.ready.await()
    RecipeOverlay.EnsureTables()
    RecipeOverlay.Load()
    if RecipeRegistry and RecipeRegistry.Rebuild then
        RecipeRegistry.Rebuild()
    end
end)
