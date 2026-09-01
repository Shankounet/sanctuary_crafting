--[[
    config/categories.lua — catégories de recettes (pack Alex / DevHub import)
    IDs propres (pas category_1775…). Labels FR conservés.
]]

Config.RecipeCategories = {
    ['all'] = {
        id = 'all',
        label = 'Tout',
        icon = 'fa-solid fa-layer-group',
        order = 1,
    },
    ['ammo'] = {
        id = 'ammo',
        label = 'Munitions',
        icon = 'fa-solid fa-crosshairs',
        order = 2,
    },
    ['weapons'] = {
        id = 'weapons',
        label = 'Armes',
        icon = 'fa-solid fa-gun',
        order = 3,
    },
    ['repair_kits'] = {
        id = 'repair_kits',
        label = 'Kit de Réparation',
        icon = 'fa-solid fa-wrench',
        order = 4,
    },
    ['weapon_body'] = {
        id = 'weapon_body',
        label = 'Corps',
        icon = 'fa-solid fa-gun',
        order = 5,
    },
    ['weapon_barrel'] = {
        id = 'weapon_barrel',
        label = 'Canon',
        icon = 'fa-solid fa-gun',
        order = 6,
    },
    ['powders'] = {
        id = 'powders',
        label = 'Poudres',
        icon = 'fa-solid fa-mortar-pestle',
        order = 7,
    },
    ['weapon_repair'] = {
        id = 'weapon_repair',
        label = 'Réparations d\'Armes',
        icon = 'fa-solid fa-wrench',
        order = 8,
    },
    ['bandages'] = {
        id = 'bandages',
        label = 'Bandages et Pensements',
        icon = 'fa-solid fa-bandage',
        order = 9,
    },
    ['painkillers'] = {
        id = 'painkillers',
        label = 'Anti-Douleurs',
        icon = 'fa-solid fa-capsules',
        order = 10,
    },
    ['remedies'] = {
        id = 'remedies',
        label = 'Remèdes',
        icon = 'fa-solid fa-syringe',
        order = 11,
    },
    ['med_kits'] = {
        id = 'med_kits',
        label = 'Kit',
        icon = 'fa-solid fa-kit-medical',
        order = 12,
    },
    ['tickets'] = {
        id = 'tickets',
        label = 'Tickets',
        icon = 'fa-solid fa-ticket',
        order = 13,
    },
    ['electricity'] = {
        id = 'electricity',
        label = 'Electriciter',
        icon = 'fa-solid fa-bolt',
        order = 14,
    },
    ['lamps'] = {
        id = 'lamps',
        label = 'Lampes',
        icon = 'fa-solid fa-lightbulb',
        order = 15,
    },
    ['gadgets'] = {
        id = 'gadgets',
        label = 'Gadgets',
        icon = 'fa-solid fa-gears',
        order = 16,
    },
    ['radio'] = {
        id = 'radio',
        label = 'Radio',
        icon = 'fa-solid fa-walkie-talkie',
        order = 17,
    },
    ['appliances'] = {
        id = 'appliances',
        label = 'Appareils domestiques',
        icon = 'fa-solid fa-fan',
        order = 18,
    },
    ['vehicle_customs'] = {
        id = 'vehicle_customs',
        label = 'Customs',
        icon = 'fa-solid fa-car',
        order = 19,
    },
    ['batteries'] = {
        id = 'batteries',
        label = 'Batterie',
        icon = 'fa-solid fa-car-battery',
        order = 20,
    },
    ['paint'] = {
        id = 'paint',
        label = 'Livrer',
        icon = 'fa-solid fa-spray-can',
        order = 21,
    },
    ['tires'] = {
        id = 'tires',
        label = 'Pneu et Roue',
        icon = 'fa-solid fa-tire',
        order = 22,
    },
    ['melee'] = {
        id = 'melee',
        label = 'Armes Corps a Coprs',
        icon = 'fa-solid fa-knife',
        order = 23,
    },
    ['tools'] = {
        id = 'tools',
        label = 'Outils',
        icon = 'fa-solid fa-hammer',
        order = 24,
    },
    ['smelting'] = {
        id = 'smelting',
        label = 'Fonderie',
        icon = 'fa-solid fa-temperature-high',
        order = 25,
    },
    ['armor'] = {
        id = 'armor',
        label = 'Protections',
        icon = 'fa-solid fa-shield-halved',
        order = 26,
    },
    ['sprouts'] = {
        id = 'sprouts',
        label = 'Pousse',
        icon = 'fa-solid fa-seedling',
        order = 27,
    },
    ['farm_equipment'] = {
        id = 'farm_equipment',
        label = 'Equipement',
        icon = 'fa-solid fa-faucet-drip',
        order = 28,
    },
    ['consumables'] = {
        id = 'consumables',
        label = 'Consomables',
        icon = 'fa-solid fa-leaf',
        order = 29,
    },
    ['meats'] = {
        id = 'meats',
        label = 'Viandes',
        icon = 'fa-solid fa-bacon',
        order = 30,
    },
    ['fish'] = {
        id = 'fish',
        label = 'Poissons',
        icon = 'fa-solid fa-fish',
        order = 31,
    },
    ['shellfish'] = {
        id = 'shellfish',
        label = 'Crustacé',
        icon = 'fa-solid fa-fish',
        order = 32,
    },
    ['bags'] = {
        id = 'bags',
        label = 'Sac',
        icon = 'fa-solid fa-backpack',
        order = 33,
    },
    ['artisan_prod'] = {
        id = 'artisan_prod',
        label = 'Production artisanale',
        icon = 'fa-solid fa-gear',
        order = 34,
    },
    ['decoration'] = {
        id = 'decoration',
        label = 'Decoration',
        icon = 'fa-solid fa-couch',
        order = 134,
    },
    ['cooker'] = {
        id = 'cooker',
        label = 'Cuisine',
        icon = 'fa-solid fa-utensils',
        order = 135,
    },
    ['techno'] = {
        id = 'techno',
        label = 'Techno',
        icon = 'fa-solid fa-microchip',
        order = 136,
    },
    ['survie'] = {
        id = 'survie',
        label = 'Survie',
        icon = 'fa-solid fa-campground',
        order = 137,
    },
}

-- Lookup rapide
Config.RecipeCategoryList = {}
do
    local tmp = {}
    for id, cat in pairs(Config.RecipeCategories) do
        tmp[#tmp + 1] = cat
    end
    table.sort(tmp, function(a, b) return (a.order or 999) < (b.order or 999) end)
    Config.RecipeCategoryList = tmp
end
