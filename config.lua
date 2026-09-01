Config = {}

--[[
    sanctuary_crafting — configuration
    Thème : post-apo (ferraille, médical de fortune, pièces d'armes, survie)

    Remplissez Config.Recipes avec VOS recettes. Schéma d'une entrée :

    {
        id = 'mon_item',
        label = 'Mon objet',
        category = 'scrap',          -- scrap | medical | weapons | survival (type de banc)
        ingredients = {
            { item = 'scrap_metal', count = 5 },
        },
        result = { item = 'metal_plate', count = 1 },
        duration = 8000,             -- ms
        xp = { category = 'crafting', amount = 15 },  -- optionnel ; category ml_skills
        requireLevel = 1,            -- optionnel ; niveau min dans xp.category ou Skills.craftingCategory
        requireSkill = 'crafting_basic', -- optionnel ; UID skill ml_skills
    }
]]

Config.Locale = 'fr'
Config.Debug = false

-- Distance max joueur ↔ banc pour craft / interaction
Config.InteractDistance = 2.5
Config.CraftCancelDistance = 3.0

-- Anti-exploit
Config.RateLimitMs = 1500          -- délai min entre deux tentatives de craft
Config.MaxConcurrentCrafts = 1

-- Admin : ACE ou groupe ESX
Config.AdminAce = 'sanctuary.crafting.admin'
Config.AdminGroups = { 'admin', 'superadmin' } -- groupes ESX Legacy

-- Commande optionnelle pour prévisualiser un banc monde (coords à reporter dans Config.WorldBenches)
Config.EnableWorldBenchCommand = true
Config.WorldBenchCommand = 'placeworldbench'

--------------------------------------------------------------------------------
-- ml_skills (Micio Mods) — soft-fail si la ressource n'est pas démarrée
--------------------------------------------------------------------------------
Config.Skills = {
    enabled = true,
    resource = 'ml_skills',
    -- Catégories utilisées par ce craft
    craftingCategory = 'crafting',
    survivalCategory = 'survival',
    -- Bonus craft-time : GetTotalCategoryBonus('crafting') réduit la durée
    -- duration = base * (1 - min(bonus/100, maxReduction))
    craftTimeBonus = true,
    maxCraftTimeReduction = 0.40, -- 40% max
}

--------------------------------------------------------------------------------
-- Modèles de bancs (props GTA)
--------------------------------------------------------------------------------
Config.BenchModels = {
    scrap     = `prop_tool_bench02`,
    medical   = `prop_table_03`,
    weapons   = `prop_toolchest_05`,
    survival  = `prop_washer_01`,
}

Config.BenchLabels = {
    scrap    = 'bench_scrap',
    medical  = 'bench_medical',
    weapons  = 'bench_weapons',
    survival = 'bench_survival',
}

--------------------------------------------------------------------------------
-- Items ox_inventory pour bancs placeables
-- Ajoutez ces items dans ox_inventory/data/items.lua (voir README)
--------------------------------------------------------------------------------
Config.PlaceableItems = {
    scrap_bench    = { category = 'scrap',    model = Config.BenchModels.scrap },
    medical_bench  = { category = 'medical',  model = Config.BenchModels.medical },
    weapons_bench  = { category = 'weapons',  model = Config.BenchModels.weapons },
    survival_bench = { category = 'survival', model = Config.BenchModels.survival },
}

-- Placement
Config.Place = {
    maxDistance = 5.0,
    snapToGround = true,
    allowPickupOwner = true,
    allowPickupAdmin = true,
}

--------------------------------------------------------------------------------
-- Bancs monde (fixes) — coords + modèle + heading + catégorie
-- Adaptez les coords à votre map
--------------------------------------------------------------------------------
Config.WorldBenches = {
    {
        id = 'world_scrap_01',
        category = 'scrap',
        coords = vec3(2330.0, 2570.0, 46.7),
        heading = 90.0,
        model = Config.BenchModels.scrap,
    },
    {
        id = 'world_medical_01',
        category = 'medical',
        coords = vec3(1839.0, 3672.0, 34.3),
        heading = 210.0,
        model = Config.BenchModels.medical,
    },
    {
        id = 'world_weapons_01',
        category = 'weapons',
        coords = vec3(16.0, -1110.0, 29.8),
        heading = 160.0,
        model = Config.BenchModels.weapons,
    },
    {
        id = 'world_survival_01',
        category = 'survival',
        coords = vec3(1960.0, 3740.0, 32.3),
        heading = 300.0,
        model = Config.BenchModels.survival,
    },
}

--------------------------------------------------------------------------------
-- Recettes — à remplir par le serveur
-- Voir le commentaire en tête de fichier pour le schéma
--------------------------------------------------------------------------------
Config.Recipes = {}

--------------------------------------------------------------------------------
-- Lookup helpers (remplis au chargement shared)
--------------------------------------------------------------------------------
Config.RecipeById = {}
