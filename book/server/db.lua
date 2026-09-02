--[[
    book/server/db.lua — tables Survival Book (minimal, no ml_skills XP)
]]

BookDB = BookDB or {}

function BookDB.Ensure()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_player` (
        `identifier` VARCHAR(60) NOT NULL,
        `prefs` LONGTEXT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_objectives` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(60) NOT NULL,
        `kind` VARCHAR(24) NOT NULL DEFAULT 'manual',
        `title` VARCHAR(128) NOT NULL,
        `payload` LONGTEXT NULL,
        `done` TINYINT(1) NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `idx_ident` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_pins` (
        `identifier` VARCHAR(60) NOT NULL,
        `recipe_id` VARCHAR(80) NOT NULL,
        `sort_order` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`, `recipe_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    pcall(function()
        MySQL.query.await('ALTER TABLE sanctuary_book_pins MODIFY recipe_id VARCHAR(80) NOT NULL')
    end)

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_notes` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(60) NOT NULL,
        `title` VARCHAR(128) NOT NULL,
        `body` LONGTEXT NOT NULL,
        `checklist` LONGTEXT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `idx_ident` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_discovered_resources` (
        `identifier` VARCHAR(60) NOT NULL,
        `item` VARCHAR(64) NOT NULL,
        `discovered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `note` TEXT NULL,
        PRIMARY KEY (`identifier`, `item`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    pcall(function()
        MySQL.query.await('ALTER TABLE sanctuary_book_discovered_resources ADD COLUMN note TEXT NULL')
    end)

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_artisans` (
        `identifier` VARCHAR(60) NOT NULL,
        `contact_id` VARCHAR(80) NOT NULL,
        `display_name` VARCHAR(64) NOT NULL,
        `specialty` VARCHAR(32) NULL,
        `tier` VARCHAR(24) NULL,
        `source` VARCHAR(24) NOT NULL DEFAULT 'meet',
        `meta` LONGTEXT NULL,
        `met_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`, `contact_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_history` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(60) NOT NULL,
        `event_type` VARCHAR(32) NOT NULL,
        `payload` LONGTEXT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `idx_ident_time` (`identifier`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `sanctuary_book_orders` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `order_uid` VARCHAR(64) NOT NULL,
        `owner` VARCHAR(60) NOT NULL,
        `target_contact` VARCHAR(80) NULL,
        `recipe_id` VARCHAR(64) NULL,
        `items` LONGTEXT NOT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'open',
        `note` VARCHAR(255) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), UNIQUE KEY `uniq_uid` (`order_uid`), KEY `idx_owner` (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
end

function BookDB.Ident(src)
    return GetPlayerIdentifierSafe(src)
end

function BookDB.Enabled()
    return Config.Book and Config.Book.Enabled ~= false
end

function BookDB.Mod(name)
    if not BookDB.Enabled() then return false end
    local m = Config.Book and Config.Book[name]
    if m == nil then return true end
    if type(m) == 'table' then return m.Enabled ~= false end
    return true
end
