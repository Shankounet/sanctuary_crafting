fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sanctuary_crafting'
author 'Shankounet / Sanctuary'
description 'Plateforme de craft post-apo — ESX, ox_*, ml_skills, NUI industrielle'
version '2.0.0'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/style.css',
    'web/dist/app.js',
    'web/sounds/*.ogg',
}

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
    'config/features.lua',
    'config/examples.lua',
    'shared/*.lua',
    'locales/*.lua',
}

client_scripts {
    'client/main.lua',
    'client/benches.lua',
    'client/place.lua',
    'client/nui.lua',
    'client/craft.lua',
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
