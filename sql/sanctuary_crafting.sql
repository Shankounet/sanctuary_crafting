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
