--[[
    9 recettes d'EXEMPLE minimales (pas un pack économie).
    Activées seulement si Config.LoadExampleRecipes == true.
    Couvrent : simple, skill, blueprint, tool, quality, mechanic, byproducts, machine/queue, dismantle.

    Multi-étapes (optionnel) :
      steps = {
        { label = 'Découpe', ingredients = { { item = 'scrap_metal', count = 3 } }, duration = 4000 },
        { label = 'Assemblage', ingredients = { { item = 'cloth', count = 1 } }, duration = 5000 },
      },
      -- OU chain = { 'ex_reinforced_plate' }  -- après complete, serveur renvoie chainNext (même craftUID)
]]

Config.LoadExampleRecipes = Config.LoadExampleRecipes ~= false -- default true for examples pack

local Examples = {
    -- 1. Simple scrap
    {
        id = 'ex_metal_plate',
        label = 'Plaque de métal (exemple)',
        category = 'scrap',
        tags = { 'metal', 'basic' },
        ingredients = {
            { item = 'scrap_metal', count = 5 },
        },
        result = { item = 'metal_plate', count = 1 },
        duration = 6000,
        xp = { category = 'crafting', amount = 10 },
    },
    -- 2. Skill-gated
    {
        id = 'ex_reinforced_plate',
        label = 'Plaque renforcée (exemple skill)',
        category = 'scrap',
        tags = { 'metal', 'advanced' },
        ingredients = {
            { item = 'metal_plate', count = 2 },
            { item = 'scrap_metal', count = 3 },
        },
        result = { item = 'reinforced_plate', count = 1 },
        duration = 10000,
        xp = { category = 'crafting', amount = 25 },
        requireLevel = 3,
        requireSkill = 'crafting_basic',
    },
    -- 3. Blueprint-gated
    {
        id = 'ex_filter_mask',
        label = 'Masque filtrant (exemple blueprint)',
        category = 'survival',
        tags = { 'survival', 'gear' },
        ingredients = {
            { item = 'cloth', count = 4 },
            { item = 'plastic', count = 2 },
        },
        result = { item = 'filter_mask', count = 1 },
        duration = 12000,
        xp = { category = 'survival', amount = 20 },
        requireBlueprint = 'bp_filter_mask',
        blueprintId = 'bp_filter_mask',
    },
    -- 4. Tool + multi-step (steps[] sous le même craftId)
    {
        id = 'ex_cut_pipe',
        label = 'Tuyau découpé (exemple outil + steps)',
        category = 'scrap',
        tags = { 'metal', 'tool', 'steps' },
        ingredients = {}, -- remplacé par steps[].ingredients
        steps = {
            { label = 'Mesure / découpe', ingredients = { { item = 'scrap_metal', count = 3 } }, duration = 4000 },
            { label = 'Ébavurage', ingredients = { { item = 'cloth', count = 1 } }, duration = 4000 },
        },
        result = { item = 'cut_pipe', count = 1 },
        duration = 8000,
        xp = { category = 'crafting', amount = 12 },
        requireTool = { item = 'hand_saw', durabilityCost = 5 },
        -- chain = { 'ex_reinforced_plate' }, -- décommenter pour enchaîner (réponse chainNext)
    },
    -- 5. Quality roll
    {
        id = 'ex_medkit_basic',
        label = 'Kit médical de fortune (exemple qualité)',
        category = 'medical',
        tags = { 'medical' },
        ingredients = {
            { item = 'cloth', count = 2 },
            { item = 'alcohol', count = 1 },
        },
        result = { item = 'medkit_basic', count = 1 },
        duration = 9000,
        xp = { category = 'crafting', amount = 15 },
        quality = true,
    },
    -- 6. Mechanic station
    {
        id = 'ex_repair_kit',
        label = 'Kit de réparation (exemple mechanic)',
        category = 'mechanic',
        tags = { 'vehicle', 'repair' },
        ingredients = {
            { item = 'metal_plate', count = 1 },
            { item = 'scrap_metal', count = 4 },
        },
        result = { item = 'repair_kit', count = 1 },
        duration = 15000,
        xp = { category = 'crafting', amount = 30 },
        requireLevel = 2,
        stationLevel = 1,
    },
    -- 7. Byproducts
    {
        id = 'ex_smelt_scrap',
        label = 'Fonte de ferraille (exemple sous-produits)',
        category = 'scrap',
        tags = { 'smelt' },
        ingredients = {
            { item = 'scrap_metal', count = 10 },
        },
        result = { item = 'metal_ingot', count = 1 },
        duration = 14000,
        xp = { category = 'crafting', amount = 18 },
        byproducts = {
            { item = 'slag', count = 1, chance = 0.6 },
            { item = 'coal_dust', count = 1, chance = 0.25 },
        },
        noiseLevel = 2,
    },
    -- 8. Machine / queue-friendly (longer duration)
    {
        id = 'ex_ammo_press',
        label = 'Presse munitions (exemple machine/queue)',
        category = 'weapons',
        tags = { 'ammo', 'machine' },
        ingredients = {
            { item = 'gunpowder', count = 2 },
            { item = 'brass', count = 5 },
        },
        result = { item = 'ammo_9mm', count = 12 },
        duration = 45000,
        xp = { category = 'crafting', amount = 40 },
        requireLevel = 4,
        powerCost = 1,
        queueable = true,
        batchMax = 5,
    },
    -- 9. Dismantle recipe (source item → yields)
    {
        id = 'ex_dismantle_pistol',
        label = 'Démontage pistolet (exemple)',
        category = 'weapons',
        tags = { 'dismantle' },
        dismantle = true,
        ingredients = {
            { item = 'weapon_pistol', count = 1 },
        },
        result = { item = 'weapon_parts', count = 3 },
        duration = 20000,
        xp = { category = 'crafting', amount = 22 },
        dismantleYields = {
            { item = 'weapon_parts', count = 2, chance = 1.0 },
            { item = 'spring', count = 1, chance = 0.5 },
            { item = 'scrap_metal', count = 2, chance = 0.8 },
        },
        requireSkill = 'weapons_basic',
    },
}

if Config.LoadExampleRecipes then
    for i = 1, #Examples do
        Config.Recipes[#Config.Recipes + 1] = Examples[i]
    end
end
