--[[ Feature flags — chaque module est implémenté ; Enabled bascule le comportement ]]

Config = Config or {}

Config.Stations = {
    UpgradesEnabled = true,
    DefaultLevel = 1,
    MaxLevel = 5,
    Upgrades = {
        scrap = {
            [2] = { label = 'Établi renforcé', requireLevel = 2, costItems = { { item = 'scrap_metal', count = 20 } } },
            [3] = { label = 'Établi industriel', requireLevel = 4, costItems = { { item = 'metal_plate', count = 5 } } },
        },
        mechanic = {
            [2] = { label = 'Pont basique', requireLevel = 2, costItems = { { item = 'metal_plate', count = 3 } } },
        },
    },
    Modules = {
        'power_cell', 'storage_rack', 'precision_kit',
    },
}

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
}

Config.Byproducts = { Enabled = true }

Config.Batch = {
    Enabled = true,
    MaxBatch = 10,
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
}

-- Power : conserver ExternalBridge / FallbackModules ; Enabled reste celui de config.lua
Config.Power = Config.Power or { Enabled = false }
if Config.Power.FallbackModules == nil then
    Config.Power.FallbackModules = { 'power_cell', 'generator' }
end

-- Survival Book : voir config/book.lua (Config.Book.*)
