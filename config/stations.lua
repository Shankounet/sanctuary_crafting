--[[
    config/stations.lua — v2.15 stations: modules, levels I–III, condition, heat
    World benches skip modules (WorldSkipModules). Placed benches must work.
]]

Config = Config or {}

local function up2(skill)
    return {
        label = 'Niveau II',
        requireLevel = 2,
        skillCategory = skill,
        costItems = { { item = 'scrapmetal', count = 12 }, { item = 'metal_plate', count = 2 } },
    }
end

local function up3(skill)
    return {
        label = 'Niveau III',
        requireLevel = 5,
        skillCategory = skill,
        costItems = { { item = 'metal_plate', count = 6 }, { item = 'electronicscrap', count = 4 } },
    }
end

local function ups(skill)
    return { [2] = up2(skill), [3] = up3(skill) }
end

Config.Stations = {
    UpgradesEnabled = true,
    DefaultLevel = 1,
    MaxLevel = 3,
    WorldSkipModules = true,
    Modules = {
        'reinforced_tools', 'power_cell', 'reinforced_bench', 'precision_kit',
        'cooling', 'ventilation', 'filter', 'electric', 'storage_rack',
    },
    ModuleDefs = {
        reinforced_tools = {
            label = 'Outils renforcés', item = 'reinforced_tools',
            modifiers = { speed = 0.06, durability = 0.15 },
        },
        power_cell = {
            label = 'Cellule d\'énergie', item = 'power_cell',
            modifiers = { energy = 1 },
        },
        reinforced_bench = {
            label = 'Établi renforcé', item = 'reinforced_bench',
            modifiers = { durability = 0.25, efficiency = 0.04 },
        },
        precision_kit = {
            label = 'Kit de précision', item = 'precision_kit',
            modifiers = { quality = 1, efficiency = 0.08, speed = -0.03 },
        },
        cooling = {
            label = 'Refroidissement', item = 'cooling',
            modifiers = { temperature = -15, energy = 0.05 },
        },
        ventilation = {
            label = 'Ventilation', item = 'ventilation',
            modifiers = { temperature = -10, noise = -1 },
        },
        filter = {
            label = 'Filtre', item = 'filter',
            modifiers = { noise = -0.5, quality = 0.3 },
        },
        electric = {
            label = 'Kit électrique', item = 'electric',
            modifiers = { energy = 0.5, speed = 0.04 },
        },
        storage_rack = {
            label = 'Rack de stockage', item = 'storage_rack',
            modifiers = { queueSize = 2 },
        },
    },
    Upgrades = {
        -- 18 real stations
        armurier = ups('armurier'),
        munition = ups('armurier'),
        survie = ups('survie'),
        tailleur = ups('survie'),
        forgeron = ups('forgeron'),
        reparation_forgeron = ups('forgeron'),
        medical = ups('medecin'),
        agriculture = ups('agriculture'),
        boucherie = ups('agriculture'),
        ingenieur = ups('ingenieur'),
        mecano = ups('mechanic'),
        cuisine = ups('survie'),
        fonderie_forgeron = ups('forgeron'),
        manche_forgeron = ups('forgeron'),
        construction = ups('ingenieur'),
        decoration = ups('ingenieur'),
        schema = ups('ingenieur'),
        accessoires = ups('armurier'),
        -- legacy
        scrap = ups('ingenieur'),
        weapons = ups('armurier'),
        survival = ups('survie'),
        mechanic = ups('mechanic'),
    },
    Condition = {
        Enabled = true,
        WorldMode = 'skip', -- skip | light
        Max = 100,
        DegradePerCraft = 1.2,
        FailBelow = 8,
        BrokenStop = 3,
        Maintain = {
            parts = { { item = 'cloth', count = 2 } },
            restore = 12,
        },
        Repair = {
            parts = { { item = 'scrapmetal', count = 6 }, { item = 'metal_plate', count = 1 } },
            tools = { { item = 'WEAPON_WRENCHKNIFE', durabilityCost = 2 } },
            restore = 45,
            requireLevel = 1,
            skillCategory = 'ingenieur',
            requireSpec = false,
        },
        BrokenParts = {
            Enabled = true,
            Threshold = 20,
            Chance = 0.10,
            Pool = {
                belt = { item = 'rubber', count = 2, label = 'Courroie' },
                filter = { item = 'cloth', count = 1, label = 'Filtre' },
                motor = { item = 'scrapmetal', count = 4, label = 'Moteur' },
                circuit = { item = 'electronicscrap', count = 2, label = 'Circuit' },
            },
        },
    },
    Heat = {
        Enabled = true,
        -- Heat is RAM-only (v2.17). CoolTick never SQL. On resource restart, heat
        -- resets to Ambient — it does not survive restart. Condition/modules/level do.
        Particles = false,
        Ambient = 20,
        RisePerCraft = 8,
        IdleCoolPerTick = 4,
        OverheatAt = 85,
        PauseAt = 95,
        BreakdownChanceOverheat = 0.04,
        CoolingModule = 12,
        VentilationModule = 8,
        Industrial = {
            fonderie_forgeron = true,
            forgeron = true,
            cuisine = true,
            munition = true,
            construction = true,
            ingenieur = true,
            mecano = true,
            mechanic = true,
            scrap = true,
            manche_forgeron = true,
            reparation_forgeron = true,
        },
    },
}
