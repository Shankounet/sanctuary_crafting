--[[
    config/categories.lua — taxonomie CRAFT joueur (stable, configurable)

    Principes:
    - craftCategoryUid / craftSubcategoryUid = source de vérité UI (après normalize).
    - NE PAS dériver des labels, ox types, tokens, tags ML Skills, ou station.
    - ML Skills = unlock/XP seulement. Station (bench) ≠ catégorie craft.
    - "Divers" = dernier recours. Pas de catégorie "Toutes" (filtre global UI).
]]

---------------------------------------------------------------------------
-- Taxonomie principale (8–14) + sous-catégories optionnelles
---------------------------------------------------------------------------

---@class CraftSubcategoryDef
---@field uid string
---@field label string
---@field icon? string
---@field sortOrder number
---@field enabled? boolean

---@class CraftCategoryDef
---@field uid string
---@field label string
---@field icon string
---@field sortOrder number
---@field accent? string
---@field enabled? boolean
---@field subcategories? table<string, CraftSubcategoryDef>

Config.CraftCategories = {
    survie = {
        uid = 'survie',
        label = 'Survie',
        icon = 'fa-solid fa-campground',
        sortOrder = 10,
        accent = '#8B7355',
        enabled = true,
        subcategories = {
            eau = { uid = 'eau', label = 'Eau', icon = 'fa-solid fa-droplet', sortOrder = 10, enabled = true },
            abri = { uid = 'abri', label = 'Abri', icon = 'fa-solid fa-tent', sortOrder = 20, enabled = true },
            feu = { uid = 'feu', label = 'Feu', icon = 'fa-solid fa-fire', sortOrder = 30, enabled = true },
        },
    },
    soins = {
        uid = 'soins',
        label = 'Soins',
        icon = 'fa-solid fa-kit-medical',
        sortOrder = 20,
        accent = '#C45C5C',
        enabled = true,
        subcategories = {
            bandages = { uid = 'bandages', label = 'Bandages', icon = 'fa-solid fa-bandage', sortOrder = 10, enabled = true },
            medicaments = { uid = 'medicaments', label = 'Médicaments', icon = 'fa-solid fa-syringe', sortOrder = 20, enabled = true },
            anti_douleurs = { uid = 'anti_douleurs', label = 'Anti-douleurs', icon = 'fa-solid fa-capsules', sortOrder = 30, enabled = true },
            kits = { uid = 'kits', label = 'Kits', icon = 'fa-solid fa-briefcase-medical', sortOrder = 40, enabled = true },
            premiers_soins = { uid = 'premiers_soins', label = 'Premiers soins', icon = 'fa-solid fa-heart-pulse', sortOrder = 5, enabled = true },
        },
    },
    outils = {
        uid = 'outils',
        label = 'Outils',
        icon = 'fa-solid fa-hammer',
        sortOrder = 30,
        accent = '#A67C52',
        enabled = true,
        subcategories = {
            forge = { uid = 'forge', label = 'Forge', icon = 'fa-solid fa-fire-flame-curved', sortOrder = 10, enabled = true },
            reparation = { uid = 'reparation', label = 'Réparation', icon = 'fa-solid fa-screwdriver-wrench', sortOrder = 20, enabled = true },
        },
    },
    equipement = {
        uid = 'equipement',
        label = 'Équipement',
        icon = 'fa-solid fa-vest',
        sortOrder = 40,
        accent = '#6B8F71',
        enabled = true,
        subcategories = {
            gadgets = { uid = 'gadgets', label = 'Gadgets', icon = 'fa-solid fa-gears', sortOrder = 10, enabled = true },
            sacs = { uid = 'sacs', label = 'Sacs', icon = 'fa-solid fa-bag-shopping', sortOrder = 20, enabled = true },
            appareils = { uid = 'appareils', label = 'Appareils', icon = 'fa-solid fa-fan', sortOrder = 30, enabled = true },
            protections = { uid = 'protections', label = 'Protections', icon = 'fa-solid fa-shield-halved', sortOrder = 40, enabled = true },
            tech = { uid = 'tech', label = 'Tech', icon = 'fa-solid fa-microchip', sortOrder = 50, enabled = true },
        },
    },
    construction = {
        uid = 'construction',
        label = 'Construction',
        icon = 'fa-solid fa-helmet-safety',
        sortOrder = 50,
        accent = '#7A8B99',
        enabled = true,
        subcategories = {
            fonderie = { uid = 'fonderie', label = 'Fonderie', icon = 'fa-solid fa-temperature-high', sortOrder = 10, enabled = true },
            decoration = { uid = 'decoration', label = 'Décoration', icon = 'fa-solid fa-couch', sortOrder = 20, enabled = true },
        },
    },
    mecanique = {
        uid = 'mecanique',
        label = 'Mécanique',
        icon = 'fa-solid fa-wrench',
        sortOrder = 60,
        accent = '#5C7A8A',
        enabled = true,
        subcategories = {
            pneumatiques = { uid = 'pneumatiques', label = 'Pneumatiques', icon = 'fa-solid fa-circle', sortOrder = 10, enabled = true },
            entretien = { uid = 'entretien', label = 'Entretien', icon = 'fa-solid fa-oil-can', sortOrder = 20, enabled = true },
            fluides = { uid = 'fluides', label = 'Fluides / Stockage', icon = 'fa-solid fa-droplet', sortOrder = 30, enabled = true },
            carrosserie = { uid = 'carrosserie', label = 'Carrosserie', icon = 'fa-solid fa-spray-can', sortOrder = 40, enabled = true },
            customs = { uid = 'customs', label = 'Customs', icon = 'fa-solid fa-car', sortOrder = 50, enabled = true },
        },
    },
    electricite = {
        uid = 'electricite',
        label = 'Électricité',
        icon = 'fa-solid fa-bolt',
        sortOrder = 70,
        accent = '#D4A84B',
        enabled = true,
        subcategories = {
            eclairage = { uid = 'eclairage', label = 'Éclairage', icon = 'fa-solid fa-lightbulb', sortOrder = 10, enabled = true },
            batteries = { uid = 'batteries', label = 'Batteries', icon = 'fa-solid fa-car-battery', sortOrder = 20, enabled = true },
            radio = { uid = 'radio', label = 'Radio', icon = 'fa-solid fa-walkie-talkie', sortOrder = 30, enabled = true },
        },
    },
    armes = {
        uid = 'armes',
        label = 'Armes',
        icon = 'fa-solid fa-gun',
        sortOrder = 80,
        accent = '#8B4557',
        enabled = true,
        subcategories = {
            melee = { uid = 'melee', label = 'Corps à corps', icon = 'fa-solid fa-knife', sortOrder = 10, enabled = true },
            corps = { uid = 'corps', label = 'Corps', icon = 'fa-solid fa-cube', sortOrder = 20, enabled = true },
            canons = { uid = 'canons', label = 'Canons', icon = 'fa-solid fa-gun', sortOrder = 30, enabled = true },
            reparation = { uid = 'reparation', label = 'Réparations', icon = 'fa-solid fa-wrench', sortOrder = 40, enabled = true },
        },
    },
    munitions = {
        uid = 'munitions',
        label = 'Munitions',
        icon = 'fa-solid fa-crosshairs',
        sortOrder = 90,
        accent = '#9A6B3F',
        enabled = true,
        subcategories = {},
    },
    cuisine = {
        uid = 'cuisine',
        label = 'Cuisine',
        icon = 'fa-solid fa-utensils',
        sortOrder = 100,
        accent = '#C47A4A',
        enabled = true,
        subcategories = {
            viandes = { uid = 'viandes', label = 'Viandes', icon = 'fa-solid fa-bacon', sortOrder = 10, enabled = true },
            poissons = { uid = 'poissons', label = 'Poissons', icon = 'fa-solid fa-fish', sortOrder = 20, enabled = true },
            crustaces = { uid = 'crustaces', label = 'Crustacés', icon = 'fa-solid fa-shrimp', sortOrder = 30, enabled = true },
        },
    },
    agriculture = {
        uid = 'agriculture',
        label = 'Agriculture',
        icon = 'fa-solid fa-seedling',
        sortOrder = 110,
        accent = '#5F8F5A',
        enabled = true,
        subcategories = {
            pousses = { uid = 'pousses', label = 'Pousses', icon = 'fa-solid fa-seedling', sortOrder = 10, enabled = true },
            equipement = { uid = 'equipement', label = 'Équipement agricole', icon = 'fa-solid fa-faucet-drip', sortOrder = 20, enabled = true },
            consommables = { uid = 'consommables', label = 'Consommables', icon = 'fa-solid fa-leaf', sortOrder = 30, enabled = true },
        },
    },
    chimie = {
        uid = 'chimie',
        label = 'Chimie',
        icon = 'fa-solid fa-flask',
        sortOrder = 120,
        accent = '#7B6B9A',
        enabled = true,
        subcategories = {
            poudres = { uid = 'poudres', label = 'Poudres', icon = 'fa-solid fa-mortar-pestle', sortOrder = 10, enabled = true },
        },
    },
    transport = {
        uid = 'transport',
        label = 'Transport',
        icon = 'fa-solid fa-ship',
        sortOrder = 130,
        accent = '#4A7C8C',
        enabled = true,
        subcategories = {
            nautique = { uid = 'nautique', label = 'Nautique', icon = 'fa-solid fa-sailboat', sortOrder = 10, enabled = true },
            navigation = { uid = 'navigation', label = 'Navigation', icon = 'fa-solid fa-location-crosshairs', sortOrder = 20, enabled = true },
        },
    },
    divers = {
        uid = 'divers',
        label = 'Divers',
        icon = 'fa-solid fa-box',
        sortOrder = 999,
        accent = '#6E6E6E',
        enabled = true,
        subcategories = {},
    },
}

---------------------------------------------------------------------------
-- Migration: ancien recipe.category (pack) → suggestion (jamais auto-vérité admin)
-- Utilisé par normalizeRecipeClassification + rapport d'audit / suggest admin.
---------------------------------------------------------------------------

--- @type table<string, { category: string, subcategory?: string }>
Config.CraftCategoryLegacyMap = {
    painkillers = { category = 'soins', subcategory = 'anti_douleurs' },
    bandages = { category = 'soins', subcategory = 'bandages' },
    remedies = { category = 'soins', subcategory = 'medicaments' },
    med_kits = { category = 'soins', subcategory = 'kits' },
    medecin = { category = 'soins' },
    powders = { category = 'chimie', subcategory = 'poudres' },
    electricity = { category = 'electricite' }, -- Electriciter → Électricité
    lamps = { category = 'electricite', subcategory = 'eclairage' },
    batteries = { category = 'electricite', subcategory = 'batteries' },
    radio = { category = 'electricite', subcategory = 'radio' },
    gadgets = { category = 'equipement', subcategory = 'gadgets' },
    tools = { category = 'outils' },
    bags = { category = 'equipement', subcategory = 'sacs' },
    appliances = { category = 'equipement', subcategory = 'appareils' },
    armor = { category = 'equipement', subcategory = 'protections' },
    tickets = { category = 'divers' },
    weapons = { category = 'armes' },
    melee = { category = 'armes', subcategory = 'melee' },
    ammo = { category = 'munitions' },
    weapon_body = { category = 'armes', subcategory = 'corps' },
    weapon_barrel = { category = 'armes', subcategory = 'canons' },
    weapon_repair = { category = 'armes', subcategory = 'reparation' },
    repair_kits = { category = 'outils', subcategory = 'reparation' },
    tires = { category = 'mecanique', subcategory = 'pneumatiques' },
    vehicle_customs = { category = 'mecanique', subcategory = 'customs' },
    paint = { category = 'mecanique', subcategory = 'carrosserie' },
    mechanic = { category = 'mecanique' },
    sprouts = { category = 'agriculture', subcategory = 'pousses' },
    farm_equipment = { category = 'agriculture', subcategory = 'equipement' },
    consumables = { category = 'agriculture', subcategory = 'consommables' },
    meats = { category = 'cuisine', subcategory = 'viandes' },
    fish = { category = 'cuisine', subcategory = 'poissons' },
    shellfish = { category = 'cuisine', subcategory = 'crustaces' },
    cooker = { category = 'cuisine' },
    smelting = { category = 'construction', subcategory = 'fonderie' },
    survie = { category = 'survie' },
    agriculture = { category = 'agriculture' },
    forgeron = { category = 'outils', subcategory = 'forge' },
    armurier = { category = 'armes' },
    ingenieur = { category = 'electricite' },
    techno = { category = 'equipement', subcategory = 'tech' },
    artisan_prod = { category = 'agriculture' },
    decoration = { category = 'construction', subcategory = 'decoration' },
    all = { category = 'divers' },
}

--- Overrides explicites par recipe id (exemples brief + corrections évidentes)
--- @type table<string, { category: string, subcategory?: string }>
Config.CraftRecipeClassificationOverrides = {
    craft_smallboat = { category = 'transport', subcategory = 'nautique' },
    craft_chambre_air = { category = 'mecanique', subcategory = 'pneumatiques' },
    craft_kit_entretien_velo = { category = 'mecanique', subcategory = 'entretien' },
    craft_vehicle_gps = { category = 'transport', subcategory = 'navigation' },
    craft_medium_water_tank = { category = 'survie', subcategory = 'eau' },
    craft_large_water_tank = { category = 'survie', subcategory = 'eau' },
    craft_small_water_tank = { category = 'survie', subcategory = 'eau' },
    craft_water_tank = { category = 'survie', subcategory = 'eau' },
    craft_water_collector = { category = 'survie', subcategory = 'eau' },
    craft_recuperateur = { category = 'survie', subcategory = 'eau' },
    craft_oil_tank = { category = 'mecanique', subcategory = 'fluides' },
    craft_cuve_huile = { category = 'mecanique', subcategory = 'fluides' },
    craft_bandage = { category = 'soins', subcategory = 'bandages' },
    craft_dough = { category = 'cuisine' },
    craft_cosmetics = { category = 'equipement' },
    craft_binoculars = { category = 'equipement', subcategory = 'gadgets' },
    craft_med_kit = { category = 'soins', subcategory = 'kits' },
    craft_black_powder = { category = 'chimie', subcategory = 'poudres' },
}

---------------------------------------------------------------------------
-- Compat dépréciée: Config.RecipeCategories (flat) — ne plus utiliser pour UI
-- Conservé pour lectures legacy / admin transition. Pas de clé "all".
---------------------------------------------------------------------------

Config.RecipeCategories = {}
Config.RecipeCategoryList = {}

do
    local flat = {}
    local list = {}
    for uid, def in pairs(Config.CraftCategories) do
        local row = {
            id = def.uid or uid,
            uid = def.uid or uid,
            label = def.label,
            icon = def.icon,
            order = def.sortOrder or 99,
            sortOrder = def.sortOrder or 99,
            accent = def.accent,
            enabled = def.enabled ~= false,
            deprecated = false,
        }
        flat[uid] = row
        list[#list + 1] = row
    end
    table.sort(list, function(a, b) return (a.sortOrder or 99) < (b.sortOrder or 99) end)
    Config.RecipeCategories = flat
    Config.RecipeCategoryList = list
end
