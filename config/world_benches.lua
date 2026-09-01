--[[
    config/world_benches.lua — bancs monde importés (Shared.Craftings)
    category/station = craftsId (filtre recettes via recipe.station).
    type = "coords" → pas de spawn prop (point d'interaction seul).
]]

Config.WorldBenches = {
    {
        id = 'weapon_crafting',
        label = 'Table d\'Armes',
        station = 'armurier',
        category = 'armurier', -- craftsId / station
        coords = vec3(149.3667144775391, -2204.89404296875, 3.68802309036254),
        heading = 178.14955139160156,
        model = 'marimonstore_bancada_arma', -- prop name (joaat côté client si besoin)
        prop = 'marimonstore_bancada_arma',
        queueSize = 6,
        -- camera skipped: camera = {              x = 149.67352294922,              y = -2202.5795898438,              z = 5.5639848709106,       
    },
    {
        id = 'munition_crafting',
        label = 'Table de Munitions',
        station = 'munition',
        category = 'munition', -- craftsId / station
        coords = vec3(2677.69482421875, 1347.7078857421875, 23.65589904785156),
        heading = 0.88159996271133,
        model = 'b3ast_explosive_bench', -- prop name (joaat côté client si besoin)
        prop = 'b3ast_explosive_bench',
        queueSize = 6,
        -- camera skipped: camera = {              x = 2677.6750488282,              y = 1346.5950927734,              z = 25.352533340454,        
    },
    {
        id = 'attachement_crafting',
        label = 'Table d\'Attachement',
        station = 'armurier',
        category = 'armurier', -- craftsId / station
        coords = vec3(-453.62847900390625, 1148.3885498046875, 324.9732055664063),
        heading = 74.48211669921875,
        model = 'b3ast_weapon_bench', -- prop name (joaat côté client si besoin)
        prop = 'b3ast_weapon_bench',
        queueSize = 6,
        -- camera skipped: camera = {              x = -452.12609863282,              y = 1148.0187988282,              z = 326.53091430664,       
    },
    {
        id = 'survie_crafting',
        label = 'Table de Survie',
        station = 'survie',
        category = 'survie', -- craftsId / station
        coords = vec3(-454.9021606445313, 1143.5489501953125, 324.99871826171875),
        heading = 74.37775421142578,
        model = 'diamond_tiertwo', -- prop name (joaat côté client si besoin)
        prop = 'diamond_tiertwo',
        queueSize = 6,
        blip = { name = 'Table de Survie', sprite = 566, size = 0.8, color = 5 },
        -- camera skipped: camera = {              x = -453.82940673828,              y = 1143.0400390625,              z = 326.64797973632,       
    },
    {
        id = 'tailleur_crafting',
        label = 'Table de Tailleur',
        station = 'tailleur',
        category = 'tailleur', -- craftsId / station
        coords = vec3(-454.38330078125, 1145.564208984375, 327.7487487792969),
        heading = 74.98344421386719,
        model = 'bzzz_tailor_crafttable_b', -- prop name (joaat côté client si besoin)
        prop = 'bzzz_tailor_crafttable_b',
        queueSize = 6,
        blip = { name = 'Guilde des Tailleurs', sprite = 71, size = 0.8, color = 12 },
        -- camera skipped: camera = {              x = -453.06155395508,              y = 1145.1708984375,              z = 329.36883544922,       
    },
    {
        id = 'forgeron_crafting',
        label = 'Table de Forgeron',
        station = 'forgeron',
        category = 'forgeron', -- craftsId / station
        coords = vec3(1653.2550048828125, 4844.63916015625, 42.11318969726562),
        heading = 0.0,
        type = 'coords',
        queueSize = 6,
        blip = { name = 'Guilde des forgerons', sprite = 436, size = 0.8, color = 5 },
        -- camera skipped: camera = {              x = 1652.7919921875,              y = 4843.65625,              z = 42.993984222412,             
    },
    {
        id = 'reparation_forgeron_crafting',
        label = 'Reparation Forgeron',
        station = 'reparation_forgeron',
        category = 'reparation_forgeron', -- craftsId / station
        coords = vec3(1648.259521484375, 4839.451171875, 41.81690979003906),
        heading = 0.0,
        type = 'coords',
        queueSize = 6,
        -- camera skipped: camera = {              x = 1649.3793945312,              y = 4839.5620117188,              z = 42.132911682128,        
    },
    {
        id = 'medical_crafting',
        label = 'Table Medicale',
        station = 'medical',
        category = 'medical', -- craftsId / station
        coords = vec3(-449.9554748535156, 1101.87646484375, 326.6813049316406),
        heading = 40.57464981079101,
        model = 'marimonstore_bancada_medica', -- prop name (joaat côté client si besoin)
        prop = 'marimonstore_bancada_medica',
        queueSize = 6,
        -- camera skipped: camera = {              x = -451.73944091796,              y = 1102.3679199218,              z = 328.29345703125,       
    },
    {
        id = 'agriculture_crafting',
        label = 'Table d\'agriculture',
        station = 'agriculture',
        category = 'agriculture', -- craftsId / station
        coords = vec3(2562.765625, 4891.05322265625, 36.79680252075195),
        heading = 114.25697326660156,
        model = 'marimonstore_bancada_comida', -- prop name (joaat côté client si besoin)
        prop = 'marimonstore_bancada_comida',
        queueSize = 6,
        blip = { name = 'Guilde des agriculteurs', sprite = 141, size = 0.8, color = 5 },
        -- camera skipped: camera = {              x = 2564.1147460938,              y = 4889.4584960938,              z = 38.958374023438,        
    },
    {
        id = 'boucherie_crafting',
        label = 'Table de Boucherie',
        station = 'boucherie',
        category = 'boucherie', -- craftsId / station
        coords = vec3(-450.0009765625, 1148.059326171875, 324.9497375488281),
        heading = -15.91645240783691,
        model = 'prop_ff_counter_03', -- prop name (joaat côté client si besoin)
        prop = 'prop_ff_counter_03',
        queueSize = 6,
        -- camera skipped: camera = {              x = -450.42111206054,              y = 1146.5998535156,              z = 326.42526245118,       
    },
    {
        id = 'ingenieur_crafting',
        label = 'Table d\'Ingenieur',
        station = 'ingenieur',
        category = 'ingenieur', -- craftsId / station
        coords = vec3(1656.01171875, -54.11123657226562, 167.32650756835938),
        heading = 178.67283630371097,
        model = 'marimonstore_bancada_eletrica', -- prop name (joaat côté client si besoin)
        prop = 'marimonstore_bancada_eletrica',
        queueSize = 6,
        blip = { name = 'Guilde des ingénieurs', sprite = 446, size = 0.8, color = 5 },
        -- camera skipped: camera = {              x = 1656.0209960938,              y = -52.47258758545,              z = 169.06639099122,        
    },
    {
        id = 'mecano_crafting',
        label = 'Table de Mecano',
        station = 'mecano',
        category = 'mecano', -- craftsId / station
        coords = vec3(1139.938354, -785.998535, 53.510117),
        heading = 0.0,
        type = 'coords',
        queueSize = 6,
        -- camera skipped: camera = {              x = 1140.0041503906,              y = -787.6430053711,              z = 54.545497894288,        
    },
    {
        id = 'cuisine_crafting',
        label = 'Table de Cuisine',
        station = 'cuisine',
        category = 'cuisine', -- craftsId / station
        coords = vec3(-445.8781127929688, 1146.7489013671875, 324.9638366699219),
        heading = -13.94884777069091,
        model = 'gulag_cookingbench', -- prop name (joaat côté client si besoin)
        prop = 'gulag_cookingbench',
        queueSize = 6,
        -- camera skipped: camera = {              x = -446.29946899414,              y = 1145.0256347656,              z = 326.61920166016,       
    },
    {
        id = 'fonderie_forgeron_crafting',
        label = 'Fonderie Forgeron',
        station = 'fonderie_forgeron',
        category = 'fonderie_forgeron', -- craftsId / station
        coords = vec3(1649.0458984375, 4841.4736328125, 41.70168304443359),
        heading = 0.0,
        type = 'coords',
        queueSize = 6,
        -- camera skipped: camera = {              x = 1650.3717041016,              y = 4841.6928710938,              z = 42.508152008056,        
    },
    {
        id = 'manche_forgeron_crafting',
        label = 'Fabrication de Manche',
        station = 'manche_forgeron',
        category = 'manche_forgeron', -- craftsId / station
        coords = vec3(1651.084716796875, 4844.80615234375, 42.2778091430664),
        heading = 0.0,
        type = 'coords',
        queueSize = 6,
        -- camera skipped: camera = {              x = 1651.3255615234,              y = 4843.486328125,              z = 43.15050125122,          
    },
    {
        id = 'construction_crafting',
        label = 'Table de Construction',
        station = 'construction',
        category = 'construction', -- craftsId / station
        coords = vec3(-407.8563232421875, 1138.9432373046875, 324.9209899902344),
        heading = -156.4651031494141,
        model = 'prop_crosssaw_01', -- prop name (joaat côté client si besoin)
        prop = 'prop_crosssaw_01',
        queueSize = 6,
        -- camera skipped: camera = {              x = -408.3671875,              y = 1140.3515625,              z = 326.58432006836,              
    },
    {
        id = 'decoration_crafting',
        label = 'Table de Decoration',
        station = 'decoration',
        category = 'decoration', -- craftsId / station
        coords = vec3(-407.1329040527344, 1147.4578857421875, 324.9083557128906),
        heading = -106.65638732910156,
        model = 'prop_tool_bench02', -- prop name (joaat côté client si besoin)
        prop = 'prop_tool_bench02',
        queueSize = 6,
        -- camera skipped: camera = {              x = -407.4610900879,              y = 1146.2536621094,              z = 326.46887207032,        
    },
    {
        id = 'crafting_Schema',
        label = 'Construction de Schéma',
        station = 'schema',
        category = 'schema', -- craftsId / station
        coords = vec3(260.43621826171875, 3034.290771484375, 43.22333145141601),
        heading = 0.0,
        type = 'coords',
        queueSize = 8,
        -- camera skipped: camera = {              x = 262.48593139648,              y = 3034.4379882812,              z = 44.07922744751,         
    },
    {
        id = 'crafting_accessoires',
        label = 'Table Fabrication Accessoires',
        station = 'accessoires',
        category = 'accessoires', -- craftsId / station
        coords = vec3(4884.3916015625, -5198.630859375, 2.51432633399963),
        heading = 134.67758178710938,
        model = 'diamond_table_7dtd', -- prop name (joaat côté client si besoin)
        prop = 'diamond_table_7dtd',
        queueSize = 6,
        -- camera skipped: camera = {              x = 4885.73046875,              y = -5197.4638671875,              z = 4.3073468208312,         
    },
}
