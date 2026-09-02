--[[ Feature flags — chaque module est implémenté ; Enabled bascule le comportement ]]

Config = Config or {}

-- Config.Stations : voir config/stations.lua (v2.15 modules / niveaux / usure / chaleur)

Config.Blueprints = {
    Enabled = true,
    ItemName = 'blueprint_scroll',
    ForgetEnabled = true,
}

Config.Quality = {
    Enabled = true,
    Tiers = { 'poor', 'normal', 'good', 'excellent', 'masterwork' },
    DefaultTier = 'normal',
    SkillInfluence = true,
}

Config.Tools = {
    Enabled = true,
    DurabilityKey = 'durability',
    DefaultDurability = 100,
    WearPerCraft = 1,
}

Config.Byproducts = { Enabled = true }

Config.Batch = {
    Enabled = true,
    MaxBatch = 50,
    HardCap = 100,
    Presets = { 1, 5, 10, 'max' },
}

Config.Signature = {
    Enabled = true,
    DefaultMode = 'batch', -- none | batch | individual
}

Config.Noise = {
    Enabled = true,
    ExportEvent = 'sanctuary_crafting:noise',
}

Config.Animations = {
    Enabled = true,
    Default = { dict = 'mini@repair', clip = 'fixing_a_ped' },
}

Config.Queue = {
    Enabled = true,
    MaxQueuePerPlayer = 5,
    OfflineProgress = true,
    AllowAll = false,
}

Config.Projects = {
    Enabled = true,
    MaxContributors = 4,
}

Config.Dismantling = {
    Enabled = true,
    SkillYieldBonus = true,
}

Config.Mastery = {
    Enabled = true, -- maîtrise locale par recette — PAS d'XP global parallèle à ml_skills
    XpPerCraft = 1,
    MaxMastery = 100,
    MasteredThreshold = 100, -- mastery >= threshold → état « maîtrisé »
}

-- Connaissance recette (états UI) — serveur autoritaire ; client n'invente rien
Config.Knowledge = {
    Enabled = true,
    States = true, -- unknown / partial / blueprint / learned / mastered
}

Config.Tags = {
    Enabled = true,
    Substitution = true,
}

Config.ReverseEngineering = { Enabled = true }

Config.ShoppingList = { Enabled = true }

Config.UI = {
    UseNui = true,
    Accent = '#9a8866',
    CompactDefault = false,
    Theme = 'industrial_dark',
    -- SFX NUI (WebAudio + placeholders web/sounds/*.ogg) — désactivable
    Sounds = {
        Enabled = true,
        Volume = 0.35,
        Files = {
            click = '../sounds/click.ogg',
            success = '../sounds/success.ogg',
            error = '../sounds/error.ogg',
            blueprint = '../sounds/blueprint.ogg',
        },
    },
    -- Micro-UX craft catalogue (v2.2.22) — chaque flag est opt-in côté NUI
    Ux = {
        AlmostCraftable = true,   -- badge PRESQUE (sinon binaire FAISABLE / NON FAISABLE)
        BadgeTooltips = true,     -- tooltip raison courte sur le badge
        NouveauIndicator = true,  -- pastille NOUVEAU (tags/isNew ; localStorage seen)
        SelectionTransition = true, -- micro-transition sélection CSS
        RarityFilters = true,      -- filtres rareté optionnels (colonne gauche)
        CatalogSort = true,        -- tri catalogue
        MasteryDots = true,       -- 3 segments maîtrise sur la carte
        PinFollow = true,         -- titre « Suivre dans le Carnet » + état pin
        FabReadyConsole = true,   -- lignes idle STATION READY / File / Dernier craft
        MicroToasts = true,       -- toasts discrets dans le shell craft
        SmartSearch = true,       -- index client multi-champs (ingrédients, résultat, station…)
        MasteredBadge = true,     -- pastille MAÎTRISÉ compacte
        KnowledgeMarks = true,    -- marques knowledge (silhouette / voile / plan / maîtrise)
        PathHints = true,         -- module CHEMIN RECOMMANDÉ (fiche droite)
        ArtisanHints = true,      -- module ARTISANS CONNUS (fiche droite)
    },
}

-- Comparaison légère entre recettes liées (bouton optionnel, pas de layout forcé)
Config.Compare = {
    Enabled = false,
    -- Map optionnelle recipeId -> relatedRecipeId (sinon recipe.compareWith / relatedRecipeId)
    Map = {},
}

-- Power : conserver ExternalBridge / FallbackModules ; Enabled reste celui de config.lua
Config.Power = Config.Power or { Enabled = false }
if Config.Power.FallbackModules == nil then
    Config.Power.FallbackModules = { 'power_cell', 'generator' }
end

-- Survival Book : voir config/book.lua (Config.Book.*)

-- Floating Craft Tracker (indépendant du menu atelier) — v2.6.0
Config.CraftTracker = {
    Enabled = true,
    DefaultPosition = { top = 24, right = 24 }, -- px
    DefaultMode = 'normal', -- normal | compact | minimal
    AutoShowOnStart = true,
    HideWithMenuIfUnpinned = true,
    PersistPin = true,
    PersistMode = true,
    PersistPosition = true,
    AllowDrag = true,
    CompletedLingerMs = 2000,
    AutoRemoveCompleted = true,
    TickMs = 250, -- NUI local tick interval (NOT per-frame Lua)
    Phases = {
        medical = { 'Préparation', 'Assemblage', 'Stérilisation', 'Finalisation' },
        mechanical = { 'Découpe', 'Assemblage', 'Calibrage', 'Finition' },
        cooking = { 'Préparation', 'Cuisson', 'Conditionnement' },
        default = { 'Préparation', 'Assemblage', 'Finition' },
    },
    Sounds = {
        Enabled = true,
        OnStart = true,
        OnComplete = true,
        OnError = true,
    },
}

Config.Teaching = {
    Enabled = true,
    Distance = 2.5,
    DurationMs = 30000,
    RequireTeacherKnown = true,
    RequireTeacherSpec = true,
    RequireTeacherLevel = true,
    RequireStudentSpec = true,
    RequireStudentLevel = false,
    RequireTeacherMastery = 0,
    DefaultTeachable = false,
}

Config.Follow = {
    AutoObjectives = true,
}

Config.RecentlyCrafted = {
    Enabled = true,
    Max = 10,
}

Config.NewlyLearned = {
    Enabled = true,
}
