fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sanctuary_crafting'
author 'Shankounet / Sanctuary'
description 'Ateliers de craft post-apocalyptiques — ESX Legacy, ox_lib, ox_inventory, ox_target, ml_skills'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
    'shared/*.lua',
    'locales/*.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
}

-- ml_skills est optionnel (soft-fail)
