fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sanctuary_crafting'
author 'Shankounet / Sanctuary'
description 'Plateforme de craft post-apo + Carnet de survie — ESX, ox_*, devhub_skillTree, NUI industrielle'
version '2.25.0'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/style.css',
    'web/dist/app.js',
    'web/dist/hud-settings.js',
    'web/dist/tracker.css',
    'web/dist/tracker.js',
    'web/dist/book.css',
    'web/dist/book.js',
    'web/dist/pins-hud.css',
    'web/dist/pins-hud.js',
    'web/dist/admin.css',
    'web/dist/admin.js',
    'web/sounds/*.ogg',
    'web/dist/tex/*.png',
}

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
    'config/features.lua',
    'config/stations.lua',
    'config/categories.lua',
    'config/world_benches.lua',
    'config/community_projects.lua',
    'config/recipes_import.lua',
    'config/examples.lua', -- demos ; Config.LoadExampleRecipes = false par défaut si import actif
    'config/book.lua',
    'config/specializations.lua',
    'shared/*.lua',
    'locales/*.lua',
}

client_scripts {
    'client/main.lua',
    'client/benches.lua',
    'client/place.lua',
    'client/nui.lua',
    'client/tracker.lua',
    'client/craft.lua',
    'client/teaching.lua',
    'client/admin.lua',
    'book/client/book.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- integrations
    'server/integrations/devhub_skillTree.lua',
    'server/integrations/permissions.lua',
    'server/integrations/ox_items.lua',
    'server/integrations/power.lua',
    -- core
    'server/core/registry.lua',
    'server/core/boot.lua',
    -- security + recipes
    'server/security/validation.lua',
    'server/systems/locks.lua',
    'server/systems/anomaly.lua',
    'server/recipes/registry.lua',
    'server/recipes/snapshot.lua',
    'server/recipes/overlay.lua',
    -- stations
    'server/stations/benches.lua',
    'server/stations/runtime.lua',
    -- systems
    'server/systems/blueprints.lua',
    'server/systems/tools.lua',
    'server/systems/materials.lua',
    'server/systems/batch.lua',
    'server/systems/signature.lua',
    'server/systems/quality.lua',
    'server/systems/mastery.lua',
    'server/systems/queue.lua',
    'server/systems/station_output.lua',
    'server/systems/projects.lua',
    'server/systems/reverse.lua',
    'server/systems/favorites.lua',
    'server/systems/shopping.lua',
    'server/systems/craft_tree.lua',
    'server/systems/dismantle.lua',
    'server/systems/specializations.lua',
    'server/systems/teaching.lua',
    'server/systems/recently_crafted.lua',
    'server/systems/newly_learned.lua',
    -- crafting pipeline last (depends on above)
    'server/crafting/pipeline.lua',
    -- survival book (after crafting systems)
    'book/server/db.lua',
    'book/server/core.lua',
    'book/server/services.lua',
    'book/server/api.lua',
    'book/server/bridge.lua',
    'book/server/main.lua',
    'server/systems/follow.lua',
    'server/systems/admin_logs.lua',
    'server/admin/admin.lua',
    'server/hooks/exports.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
    'devhub_skillTree',
}

-- devhub_lib typically pulled in by the skill tree itself (not a hard dep here)
-- skill tree down: print [CRAFT] devhub_skillTree is not started. Gates fail closed; ungated crafts still work.
