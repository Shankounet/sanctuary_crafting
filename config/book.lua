--[[
    Config.Book — Carnet de survie (Survival Book)
    Manuel de terrain personnel. ml_skills = lecture seule via CraftingSkills.
]]

Config = Config or {}

Config.Book = {
    Enabled = true,
    ItemName = 'survival_book',
    Accent = '#9a8866',
    Theme = 'field_manual', -- industrial dark personal dossier (not rusty)
    LazyLoad = true,
    MaxPins = 8,
    MaxNotes = 64,
    MaxObjectives = 24,
    MaxHistory = 120,
    MaxOrders = 20,
    -- Future comfort tiers (limits only — no parallel XP)
    ComfortTiers = {
        survival_book = { label = 'Carnet de survie', tier = 1 },
        technical_manual = { label = 'Manuel technique', tier = 2 }, -- optional future item
    },

    Dashboard     = { Enabled = true },
    Progression   = { Enabled = true }, -- READ-ONLY ml_skills
    NextUnlocks   = { Enabled = true },
    Objectives    = { Enabled = true },
    Pins          = { Enabled = true, MiniHud = true },
    Shopping      = { Enabled = true, MaxDepth = 5 }, -- smart recursive, no double-count
    CraftTree     = { Enabled = true },
    Resources     = { Enabled = true, UnknownLabel = '???' },
    Discoveries   = { Enabled = true },
    Blueprints    = { Enabled = true }, -- reuse crafting knowledge
    Artisans      = { Enabled = true },
    Network       = { Enabled = true },
    Orders        = { Enabled = true, AllowTeleport = false }, -- physical/RP only
    Projects      = { Enabled = true }, -- overlay on crafting projects
    Notes         = { Enabled = true },
    Search        = { Enabled = true },
    Suggestions   = { Enabled = true },
    CanCraft      = { Enabled = true },
    Workshop      = { Enabled = true },
    Maintenance   = { Enabled = true },
    Productions   = { Enabled = true }, -- queues
    Notifications = { Enabled = true, CooldownMs = 8000 },
    History       = { Enabled = true },
    Stats         = { Enabled = true }, -- counts only
}
