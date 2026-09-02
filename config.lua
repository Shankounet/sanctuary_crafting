Config = {}

--[[
================================================================================
  sanctuary_crafting — configuration (v2.0.0-phase1)
  Thème : post-apo (ferraille, médical de fortune, pièces d'armes, survie)

  ml_skills est la SEULE source de skill / XP / niveaux.
  Ne créez JAMAIS de XP/niveaux craft parallèles.

--------------------------------------------------------------------------------
  Schéma d'une recette (Config.Recipes) — Phase 1

  {
      id          = 'mon_item',              -- string unique (requis)
      label       = 'Mon objet',             -- string (requis)
      category    = 'scrap',                 -- scrap|medical|weapons|survival (requis)
      ingredients = {                        -- table (requis, >=1)
          { item = 'scrap_metal', count = 5 },
      },
      result      = { item = 'metal_plate', count = 1 },  -- requis
      duration    = 8000,                    -- ms (requis)
      xp          = { category = 'crafting', amount = 15 }, -- optionnel ml_skills
      requireLevel = 1,                      -- optionnel ; si ml_skills down → refuse
      requireSkill = 'crafting_basic',       -- optionnel UID ml_skills ; idem

      -- Multi-étapes (v2 polish) — steps[] OU chain (même craftId / craftUID) :
      -- steps = {
      --   { label = 'Étape 1', ingredients = { { item = 'scrap_metal', count = 2 } }, duration = 3000 },
      --   { label = 'Étape 2', ingredients = { { item = 'cloth', count = 1 } }, duration = 4000 },
      -- },
      -- chain = { 'next_recipe_id' },       -- après complete → chainNext (client / project)

      -- Champs Phase 2+ (flags Config.*.Enabled) :
      -- blueprintId   = 'bp_metal_plate',   -- Config.Blueprints.Enabled
      -- quality       = true,               -- Config.Quality.Enabled
      -- powerCost     = 0,                  -- Config.Power.Enabled (+ ExternalBridge)
      -- noiseLevel    = 0,                  -- Config.Noise.Enabled
      -- queueSlot     = 1,                  -- Config.Queue.Enabled
      -- projectId     = nil,                -- Config.Projects.Enabled
      -- dismantleFrom = nil,                -- Config.Dismantling.Enabled
  }
================================================================================
]]

Config.Locale = 'fr'
Config.Debug = false
Config.Version = '2.17.2'

--------------------------------------------------------------------------------
-- Feature flags (Phase 2–7) — stubs uniquement, aucun comportement Phase 1
--------------------------------------------------------------------------------
Config.Quality     = { Enabled = false }
Config.Blueprints  = { Enabled = false }
Config.Queue       = { Enabled = false }
Config.Projects    = { Enabled = false }
Config.Power = {
    Enabled = false,  -- false → CraftingPower.HasPower toujours true
    -- Pont externe optionnel (voir integrations/power.lua) ; sinon fallback power_cell
    ExternalBridge = nil, -- { resource="my_power", export="HasStationPower" } ou { fn = function(station, recipe) return true end }
    FallbackModules = { "power_cell", "generator" },
}
Config.Noise       = { Enabled = false }
Config.Dismantling = { Enabled = false }

--------------------------------------------------------------------------------
-- Distances
--------------------------------------------------------------------------------
Config.InteractDistance = 2.5
Config.CraftCancelDistance = 3.0

--------------------------------------------------------------------------------
-- Anti-exploit / pipeline craft
--------------------------------------------------------------------------------
Config.RateLimitMs = 1500
Config.MaxConcurrentCrafts = 1

Config.Crafting = {
    --- Retire les ingrédients au start (après validation complète) ; sinon au complete
    RemoveIngredientsOnStart = true,
    ConsumeOnStart = true,
    --- File: false = consume-on-enqueue (anti-dupe, défaut). true = escrow/lock 1:1.
    ReserveOnQueue = false,
    --- Rembourse les ingrédients si retirés et craft annulé
    RefundOnCancel = true,
    --- Rembourse à la déconnexion (si ingrédients déjà retirés)
    RefundOnDisconnect = true,
    --- Floor timing anti-speedhack (0.85 = 15% de marge latence)
    MinDurationFactor = 0.85,
    --- Remboursement partiel si annulation après X% (0 = full refund rules only)
    PartialRefund = true,
    PartialRefundAfter = 0.5, -- après 50% de progression : 50% des stacks arrondis
    --- [CRAFT] finalize watchdog prints (start / finished timestamp / reward / state)
    --- startedAt/finishesAt in logs are Unix seconds; startedAt/duration internally are ms
    FinalizeLogs = true,
}

--------------------------------------------------------------------------------
-- Admin
--------------------------------------------------------------------------------
Config.AdminAce = 'sanctuary.crafting.admin'
Config.AdminGroups = { 'admin', 'superadmin' }

Config.Admin = {
    Command = 'craftadmin',
    Ace = 'sanctuary.crafting.admin',
    Groups = { 'admin', 'superadmin' },
    CustomCallback = nil, -- optional function(src) -> boolean (OR with ACE / ESX group)
}

Config.SchemaVersion = 217

Config.EnableWorldBenchCommand = true
Config.WorldBenchCommand = 'placeworldbench'

--------------------------------------------------------------------------------
-- ml_skills (Micio Mods) — soft-fail via CraftingSkills
-- Si une recette a requireLevel / requireSkill et ml_skills est down → refuse
-- (PAS de bypass silencieux en prod). BypassRequirements = false par défaut.
--------------------------------------------------------------------------------
Config.Skills = {
    enabled = true,
    resource = 'ml_skills',
    -- Catégories ml_skills du pack Alex (requiredLevelCategory exactes)
    -- ingenieurs→ingenieur, survie, agriculture, medecin, forgeron, mechanic, armurier
    craftingCategory = 'ingenieur', -- défaut bonus durée (fallback)
    survivalCategory = 'survie',
    categories = {
        'ingenieur',
        'survie',
        'agriculture',
        'medecin',
        'forgeron',
        'mechanic',
        'armurier',
    },
    craftTimeBonus = true,
    maxCraftTimeReduction = 0.40,

    --[[ Mode test sans skills (DEV ONLY)
         BypassRequirements = true  → TOUS les joueurs sautent requireLevel / requireSkill
         BypassAce (optionnel)      → si défini, les joueurs avec cet ACE (ou Config.AdminGroups
                                       / Config.AdminAce via Validation.IsAdmin) bypassent même
                                       si BypassRequirements = false
         NE JAMAIS activer BypassRequirements sur un serveur public / production.
    ]]
    BypassRequirements = true,
    BypassAce = 'sanctuary.crafting.bypassskills',
    BypassAlsoSkipXP = false, -- false = toujours tenter AddXp si ml_skills est up
    BypassNotify = true,     -- true = notify ox_lib une fois (aussi si Config.Debug)
}

--------------------------------------------------------------------------------
-- Modèles de bancs (props GTA)
--------------------------------------------------------------------------------
Config.BenchModels = {
    scrap     = `prop_tool_bench02`,
    medical   = `prop_table_03`,
    weapons   = `prop_toolchest_05`,
    survival  = `prop_washer_01`,
    mechanic  = `prop_toolchest_01`,
}

Config.BenchLabels = {
    scrap    = 'bench_scrap',
    medical  = 'bench_medical',
    weapons  = 'bench_weapons',
    survival = 'bench_survival',
    mechanic = 'bench_mechanic',
    -- stations import (fallback si pas de bench.label)
    ingenieur = 'bench_ingenieur',
    tailleur = 'bench_tailleur',
    boucherie = 'bench_boucherie',
    forgeron = 'bench_forgeron',
    manche_forgeron = 'bench_manche_forgeron',
    agriculture = 'bench_agriculture',
    mecano = 'bench_mecano',
    schema = 'bench_schema',
    accessoires = 'bench_accessoires',
    fonderie_forgeron = 'bench_fonderie_forgeron',
    decoration = 'bench_decoration',
    munition = 'bench_munition',
    cuisine = 'bench_cuisine',
    reparation_forgeron = 'bench_reparation_forgeron',
    construction = 'bench_construction',
    survie = 'bench_survie',
    armurier = 'bench_armurier',
}

--------------------------------------------------------------------------------
-- Items ox_inventory pour bancs placeables
--------------------------------------------------------------------------------
Config.PlaceableItems = {
    scrap_bench    = { category = 'scrap',    model = Config.BenchModels.scrap },
    medical_bench  = { category = 'medical',  model = Config.BenchModels.medical },
    weapons_bench  = { category = 'weapons',  model = Config.BenchModels.weapons },
    survival_bench = { category = 'survival', model = Config.BenchModels.survival },
    mechanic_bench  = { category = 'mechanic',  model = Config.BenchModels.mechanic },
}

Config.Place = {
    maxDistance = 5.0,
    snapToGround = true,
    allowPickupOwner = true,
    allowPickupAdmin = true,
    requireOwnerToCraft = false,
}

--------------------------------------------------------------------------------
-- Bancs monde (fixes) — remplacés par config/world_benches.lua (import DevHub)
--------------------------------------------------------------------------------
Config.WorldBenches = {}

--------------------------------------------------------------------------------
-- Recettes — à remplir par le serveur (ne PAS inventer un gros pack)
--------------------------------------------------------------------------------
Config.Recipes = {}

--------------------------------------------------------------------------------
-- Lookup (rempli par server/recipes/registry.lua)
--------------------------------------------------------------------------------
Config.RecipeById = {}

--------------------------------------------------------------------------------
-- Feature modules (flags Phase 2+) — chargés après Config de base
-- Voir config/features.lua (inclus via fxmanifest shared)
--------------------------------------------------------------------------------
