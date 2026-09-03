--[[
    core/boot.lua — bootstrap serveur
]]

local function registerPlaceableHooks()
    for itemName, def in pairs(Config.PlaceableItems or {}) do
        DebugPrint('Placeable item:', itemName, def.category)
    end
end

exports('useBenchItem', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        local src = inventory.id
        local itemName = item.name
        local def = Config.PlaceableItems[itemName]
        if not def then return false end
        TriggerClientEvent('sanctuary_crafting:client:startPlace', src, def.category, itemName)
        return false
    end
end)

-- Public exports for other resources
exports('GetRecipe', function(id)
    return RecipeRegistry and RecipeRegistry.Get(id)
end)

exports('GetRecipesForCategory', function(category)
    return GetRecipesForCategory(category)
end)

exports('IsCrafting', function(src)
    return CraftingPipeline and CraftingPipeline.HasActive(src)
end)

CreateThread(function()
    registerPlaceableHooks()
    local nRecipes = RecipeRegistry and select(1, RecipeRegistry.Rebuild()) or #(Config.Recipes or {})
    print(('[^2sanctuary_crafting^0] v%s — %d recettes, %d bancs monde | NUI=%s Blueprints=%s Quality=%s Queue=%s'):format(
        Config.Version or '?',
        type(nRecipes) == 'number' and nRecipes or #(Config.Recipes or {}),
        #(Config.WorldBenches or {}),
        tostring(Config.UI and Config.UI.UseNui),
        tostring(Config.Blueprints and Config.Blueprints.Enabled),
        tostring(Config.Quality and Config.Quality.Enabled),
        tostring(Config.Queue and Config.Queue.Enabled)
    ))
end)

if Config.EnableWorldBenchCommand then
    RegisterCommand(Config.WorldBenchCommand or 'placeworldbench', function(src, args)
        if src == 0 then
            print('Commande in-game uniquement')
            return
        end
        if not Validation.IsAdmin(src) then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('admin_denied') })
            return
        end
        local category = args[1] or 'scrap'
        if not IsValidBenchCategory(category) then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = _('admin_place_usage') })
            return
        end
        TriggerClientEvent('sanctuary_crafting:client:adminPreviewBench', src, category)
    end, false)
end


local function autoMigrate()
    if not MySQL or not MySQL.query or not MySQL.query.await then return end
    local statements = {
        [[CREATE TABLE IF NOT EXISTS `sanctuary_player_spec` (
            `identifier` VARCHAR(60) NOT NULL,
            `spec_id` VARCHAR(32) NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS `sanctuary_player_recent` (
            `identifier` VARCHAR(60) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `crafted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `recipe_id`),
            KEY `idx_ident_time` (`identifier`, `crafted_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS `sanctuary_player_recipe_unread` (
            `identifier` VARCHAR(60) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `source` VARCHAR(24) NOT NULL DEFAULT 'discovery',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `recipe_id`),
            KEY `idx_ident` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    }
    for i = 1, #statements do
        MySQL.query.await(statements[i])
    end
    -- v2.15 placed-bench columns (ignore duplicate)
    pcall(function() MySQL.query.await('ALTER TABLE sanctuary_placed_benches ADD COLUMN condition_pct FLOAT NOT NULL DEFAULT 100') end)
    pcall(function() MySQL.query.await('ALTER TABLE sanctuary_placed_benches ADD COLUMN heat FLOAT NOT NULL DEFAULT 20') end)
    pcall(function() MySQL.query.await('ALTER TABLE sanctuary_placed_benches ADD COLUMN broken_parts LONGTEXT NULL') end)

    -- v2.16 schema version + overlay/logs (overlay ONLY — never dump Config.Recipes)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_schema_version` (
        `id` TINYINT NOT NULL PRIMARY KEY DEFAULT 1,
        `version` INT NOT NULL,
        `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    if RecipeOverlay and RecipeOverlay.EnsureTables then RecipeOverlay.EnsureTables() end
    if AdminLogs and AdminLogs.EnsureTable then AdminLogs.EnsureTable() end
    pcall(function() MySQL.query.await('ALTER TABLE sanctuary_craft_queue ADD COLUMN recipe_snapshot LONGTEXT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE sanctuary_craft_queue ADD COLUMN recipe_version INT NULL') end)
    local target = (Config.SchemaVersion or 218)
    local cur = 0
    local row = MySQL.query.await('SELECT version FROM sanctuary_schema_version WHERE id = 1')
    if row and row[1] then cur = tonumber(row[1].version) or 0 end

    -- v2.17 sparse SQL: no derived objective rows, no skill_watch, no resource labels,
    -- prune done projects + craft_completed history (CraftHistory default false).
    -- Do NOT INSERT any recipe×player rows. Do NOT DROP knowledge/mastery/favorites/queue/pins/notes.
    if cur < 217 then
        pcall(function()
            MySQL.query.await("DELETE FROM sanctuary_book_objectives WHERE kind IN ('gather','skill','blueprint')")
        end)
        pcall(function()
            MySQL.query.await('DROP TABLE IF EXISTS sanctuary_player_skill_watch')
        end)
        pcall(function()
            MySQL.query.await('ALTER TABLE sanctuary_book_discovered_resources DROP COLUMN label')
        end)
        pcall(function()
            MySQL.query.await("DELETE FROM sanctuary_projects WHERE status='done'")
        end)
        pcall(function()
            MySQL.query.await("DELETE FROM sanctuary_book_history WHERE event_type='craft_completed'")
        end)
        local days = math.floor((Config.AdminLogs and tonumber(Config.AdminLogs.RetentionDays)) or 14)
        if days < 1 then days = 14 end
        pcall(function()
            MySQL.query.await(
                ('DELETE FROM sanctuary_admin_logs WHERE created_at < (NOW() - INTERVAL %d DAY)'):format(days)
            )
        end)
    end

    -- v2.18 optional personal note on identified resources (no labels/images)
    if cur < 218 then
        pcall(function()
            MySQL.query.await('ALTER TABLE sanctuary_book_discovered_resources ADD COLUMN note TEXT NULL')
        end)
        pcall(function()
            MySQL.query.await('ALTER TABLE sanctuary_book_pins MODIFY recipe_id VARCHAR(80) NOT NULL')
        end)
    end

    -- v2.23 (223): station output columns on sanctuary_craft_queue (sparse)
    if cur < 223 then
        if StationOutput and StationOutput.EnsureColumns then
            StationOutput.EnsureColumns()
        end
    end

    -- v2.24 (224): production FIFO columns (started_at, queue_position, duration_ms)
    if cur < 224 then
        if CraftQueue and CraftQueue.EnsureTable then
            CraftQueue.EnsureTable()
        end
        if StationOutput and StationOutput.EnsureColumns then
            StationOutput.EnsureColumns()
        end
    end

    if cur < target then
        MySQL.query.await([[
            INSERT INTO sanctuary_schema_version (id, version) VALUES (1, ?)
            ON DUPLICATE KEY UPDATE version = VALUES(version)
        ]], { target })
        print(('[sanctuary_crafting] schema migrated %s → %s'):format(tostring(cur), tostring(target)))
    end
end

CreateThread(function()
    MySQL.ready.await()
    autoMigrate()
end)

