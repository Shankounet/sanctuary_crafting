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
    MaxQueuePerPlayer = 5,          -- legacy (player-wide); station cap is authoritative
    MaxQueuePerStation = 6,         -- default if QueueByLevel missing
    -- Per station type/level slot cap. Count = processing + queued (completed = SORTIE, not a slot).
    QueueByLevel = { [1] = 3, [2] = 6, [3] = 10 },
    OfflineProgress = true,
    AllowAll = true,                -- FABRIQUER enqueues any recipe while processing
    ShowOtherJobs = true,           -- shared station: show every job in FILE
    ShowOwnerNames = false,         -- names on other players' jobs (permissions toggle)
    -- Reorder up/down: SKIP — FIFO only (created_at / queue_position).
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
    Enabled = true, -- maîtrise locale par recette — PAS d'XP global parallèle à devhub_skillTree
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
    -- SFX NUI sparse/premium (silence default; important actions only) — v2.28.0
    -- Legacy aliases still accepted by NUI: click→craft_start, success→craft_complete, error→ui_error
    Sounds = {
        Enabled = true,
        Volume = 0.25,          -- global default
        CooldownMs = 150,       -- per identical kind
        Files = {
            ui_open = '../sounds/ui_open.ogg',
            ui_close = '../sounds/ui_close.ogg',
            craft_start = '../sounds/craft_start.ogg',
            craft_complete = '../sounds/craft_complete.ogg',
            craft_collect = '../sounds/craft_collect.ogg',
            ui_error = '../sounds/ui_error.ogg',
            book_open = '../sounds/book_open.ogg',
            book_page = '../sounds/book_page.ogg',
            book_close = '../sounds/book_close.ogg',
            -- legacy keys (kept for older clients / tracker map)
            click = '../sounds/craft_start.ogg',
            success = '../sounds/craft_complete.ogg',
            error = '../sounds/ui_error.ogg',
            blueprint = '../sounds/craft_collect.ogg',
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
        HaveWhatIHave = true,     -- filtre AVEC CE QUE J'AI
        MaterialPopover = true,   -- popover clic matériau (recettes / chemin / courses)
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
-- Pause in-progress crafts when station power is lost (only if Config.Power.Enabled).
if Config.Power.PauseOnLoss == nil then
    Config.Power.PauseOnLoss = true
end

-- Survival Book : voir config/book.lua (Config.Book.*)

-- Floating Craft Tracker (indépendant du menu atelier) — v2.6.0
Config.CraftTracker = {
    Enabled = true,
    DefaultPosition = { top = 24, right = 24 }, -- px
    DefaultMode = 'expanded', -- expanded | compact | minimal | hidden ('normal' alias of expanded)
    AutoShowOnStart = true,
    HideWithMenuIfUnpinned = true,
    ShowOnNewCraftIfHidden = true, -- G: new active craft while hidden → compact
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
    -- true: pin/follow inserts a SINGLE parent recipe objective (kind='recipe').
    -- Gather / skill / blueprint children are reconstructed LIVE (inventory + skill tree snapshot)
    -- and NEVER persisted. Shopping list is RAM-only from pins + followed projects.
    AutoObjectives = true,
    -- ox_lib notify when a followed/pinned recipe becomes faisable (inventory / craft complete).
    NotifyWhenCraftable = true,
}

-- Catalogue filters (NUI, client-side on getMenu payload)
Config.Filters = {
    -- AVEC CE QUE J'AI = faisable + optionally PRESQUE with exactly 1 missing material
    HaveWhatIHaveIncludeAlmost = true,
}


--------------------------------------------------------------------------------
-- Station output (v2.23.0+) — results stay at the bench until collected. UI polish v2.23.1.
-- On timer end / offline catch-up: snapshot once, state=completed, NO AddItem.
-- Collect at the SAME station (default). Shared stations do not allow steal.
--------------------------------------------------------------------------------
Config.StationOutput = {
    Enabled = true,
    -- Collect only at the producing station (world:id / placed:id).
    SameStationOnly = true,
    -- XP + mastery: 'complete' (default, offline still gets XP on next login)
    --             | 'collect' (only when the player picks up the item)
    XpOn = 'complete',
}

-- Who may collect station output.
--   owner  = crafter identifier only (DEFAULT — shared stations cannot steal)
--   job    = same ESX job.name as stored at complete (owner_job)
--   crew   = stub of job (no crew framework; uses ESX job/group)
--   public = anyone at the station (still SameStationOnly unless disabled)
Config.OutputAccess = 'owner'

-- nil / false = never auto-purge completed output.
-- number = DELETE completed rows older than N days (maintenance timer).
Config.CompletedRetentionDays = false

-- Full craft history in sanctuary_book_history. Default OFF (sparse).
-- sanctuary_player_recent (≤10 catalogue « récemment ») stays regardless.
-- If Enabled=true, optional RetentionDays prunes craft_completed rows (book MaxHistory still caps).
Config.CraftHistory = {
    Enabled = false,
    RetentionDays = 7,
}

-- sanctuary_admin_logs retention. Purge on boot + every PurgeIntervalMs (not every frame).
-- craftCompleted rows are NOT written when CraftHistory.Enabled is false
-- (legendary / epic / weapon / unusualBatch / suspicious / anomaly / admin edits stay).
Config.AdminLogs = {
    RetentionDays = 14,
    PurgeIntervalMs = 21600000, -- 6h
}

Config.RecentlyCrafted = {
    Enabled = true,
    Max = 10,
}

Config.NewlyLearned = {
    Enabled = true,
}

-- v2.16 architecture
Config.RecipeOverlay = {
    Enabled = true,
    VersionHistory = true,
}

-- Discord webhooks: ALL OFF by default. Pipeline is HTTP-unaware (AddCraftingHook).
Config.Discord = {
    Enabled = false,
    Webhooks = {
        legendaryCraft  = { Enabled = false, Url = '' },
        epicCraft       = { Enabled = false, Url = '' },
        weaponCraft     = { Enabled = false, Url = '' },
        rareBlueprint   = { Enabled = false, Url = '' },
        unusualBatch    = { Enabled = false, Url = '' },
        adminRecipeEdit = { Enabled = false, Url = '' },
        validationFail  = { Enabled = false, Url = '' },
        suspicious      = { Enabled = false, Url = '' },
    },
}


-- Aliases (same table as Config.UI.Sounds) — user-facing / docs names
Config.UIAudio = Config.UI.Sounds
Config.UIAudioVolume = Config.UI.Sounds  -- Volume lives on Config.UI.Sounds.Volume / Config.UIAudio.Volume
