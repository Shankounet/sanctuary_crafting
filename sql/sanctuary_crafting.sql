CREATE TABLE IF NOT EXISTS `sanctuary_placed_benches` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner` VARCHAR(60) NOT NULL,
    `category` VARCHAR(32) NOT NULL DEFAULT 'scrap',
    `model` VARCHAR(64) NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0,
    `station_level` INT NOT NULL DEFAULT 1,
    `modules` LONGTEXT NULL,
    `condition_pct` FLOAT NOT NULL DEFAULT 100,
    `heat` FLOAT NOT NULL DEFAULT 20,
    `broken_parts` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_player_recipes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `blueprint_id` VARCHAR(64) NOT NULL,
    `learned_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_player_bp` (`identifier`, `blueprint_id`),
    KEY `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_recipe_mastery` (
    `identifier` VARCHAR(60) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `xp` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`, `recipe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_craft_queue` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `craft_id` VARCHAR(64) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `bench_key` VARCHAR(64) NOT NULL,
    `batch` INT NOT NULL DEFAULT 1,
    `ingredients` LONGTEXT NOT NULL,
    `finish_at` INT NOT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_ident` (`identifier`),
    UNIQUE KEY `uniq_craft` (`craft_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_projects` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `project_uid` VARCHAR(64) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `bench_key` VARCHAR(64) NOT NULL,
    `owner` VARCHAR(60) NOT NULL,
    `contributors` LONGTEXT NOT NULL,
    `deposited` LONGTEXT NOT NULL,
    `required` LONGTEXT NOT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'open',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_uid` (`project_uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_favorites` (
    `identifier` VARCHAR(60) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`identifier`, `recipe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Survival Book (minimal — no ml_skills XP storage)
CREATE TABLE IF NOT EXISTS `sanctuary_book_player` (
    `identifier` VARCHAR(60) NOT NULL,
    `prefs` LONGTEXT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_objectives` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `kind` VARCHAR(24) NOT NULL DEFAULT 'manual',
    `title` VARCHAR(128) NOT NULL,
    `payload` LONGTEXT NULL,
    `done` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ident` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_pins` (
    `identifier` VARCHAR(60) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `sort_order` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `recipe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_notes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `title` VARCHAR(128) NOT NULL,
    `body` LONGTEXT NOT NULL,
    `checklist` LONGTEXT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ident` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_discovered_resources` (
    `identifier` VARCHAR(60) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NULL,
    `discovered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_artisans` (
    `identifier` VARCHAR(60) NOT NULL,
    `contact_id` VARCHAR(80) NOT NULL,
    `display_name` VARCHAR(64) NOT NULL,
    `specialty` VARCHAR(32) NULL,
    `tier` VARCHAR(24) NULL,
    `source` VARCHAR(24) NOT NULL DEFAULT 'meet',
    `meta` LONGTEXT NULL,
    `met_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `contact_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_history` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `event_type` VARCHAR(32) NOT NULL,
    `payload` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ident_time` (`identifier`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_book_orders` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `order_uid` VARCHAR(64) NOT NULL,
    `owner` VARCHAR(60) NOT NULL,
    `target_contact` VARCHAR(80) NULL,
    `recipe_id` VARCHAR(64) NULL,
    `items` LONGTEXT NOT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'open',
    `note` VARCHAR(255) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_uid` (`order_uid`),
    KEY `idx_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS `sanctuary_player_spec` (
    `identifier` VARCHAR(60) NOT NULL,
    `spec_id` VARCHAR(32) NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_player_recent` (
    `identifier` VARCHAR(60) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `crafted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `recipe_id`),
    KEY `idx_ident_time` (`identifier`, `crafted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_player_recipe_unread` (
    `identifier` VARCHAR(60) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `source` VARCHAR(24) NOT NULL DEFAULT 'discovery',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `recipe_id`),
    KEY `idx_ident` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sanctuary_player_skill_watch` (
    `identifier` VARCHAR(60) NOT NULL,
    `category` VARCHAR(32) NOT NULL,
    `level` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
