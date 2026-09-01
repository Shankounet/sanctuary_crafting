fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sanctuary_crafting'
author 'Shankounet / Sanctuary'
description 'Plateforme de craft post-apo + Carnet de survie — ESX, ox_*, ml_skills, NUI industrielle'
version '2.2.9'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/style.css',
    'web/dist/app.js',
    'web/dist/book.css',
    'web/dist/book.js',
    'web/sounds/*.ogg',
}

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
    'config/features.lua',
    'config/categories.lua',
    'config/world_benches.lua',
    'config/community_projects.lua',
    'config/recipes_import.lua',
    'config/examples.lua', -- demos ; Config.LoadExampleRecipes = false par défaut si import actif
    'config/book.lua',
    'shared/*.lua',
    'locales/*.lua',
}

client_scripts {
    'client/main.lua',
    'client/benches.lua',
    'client/place.lua',
    'client/nui.lua',
    'client/craft.lua',
    'book/client/book.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- integrations
    'integrations/ml_skills.lua',
    'integrations/permissions.lua',
    'integrations/power.lua',
    -- core
    'core/registry.lua',
    'core/boot.lua',
    -- security + recipes
    'security/validation.lua',
    'recipes/registry.lua',
    -- stations
    'stations/benches.lua',
    -- systems
    'blueprints/blueprints.lua',
    'tools/tools.lua',
    'quality/quality.lua',
    'mastery/mastery.lua',
    'queue/queue.lua',
    'projects/projects.lua',
    'reverse/reverse.lua',
    'favorites/favorites.lua',
    'shopping/shopping.lua',
    'tree/craft_tree.lua',
    'dismantle/dismantle.lua',
    -- crafting pipeline last (depends on above)
    'crafting/pipeline.lua',
    -- survival book (after crafting systems)
    'book/server/db.lua',
    'book/server/core.lua',
    'book/server/services.lua',
    'book/server/api.lua',
    'book/server/bridge.lua',
    'book/server/main.lua',
    'hooks/exports.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
}

-- ml_skills optionnel (soft-fail ; gates requises → refuse si down)
