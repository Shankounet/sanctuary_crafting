--[[
    admin/admin.lua — /craftadmin NUI backend
    Perm: ACE, ESX group, optional Config.Admin.CustomCallback.
    Preview via CraftingPipeline.BuildRecipeEntry + RecipeRegistry.Validate.
    OX selector searches OxItemCatalog — never dumps the full item table to NUI.
]]

CraftAdmin = CraftAdmin or {}

local function cfgAdmin()
    return Config.Admin or {}
end

function CraftAdmin.IsAllowed(src)
    if not src or src == 0 then return false end
    local c = cfgAdmin()
    if type(c.CustomCallback) == 'function' then
        local ok, res = pcall(c.CustomCallback, src)
        if ok and res == true then return true end
    end
    if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then
        return true
    end
    return false
end

local function deny()
    return { ok = false, reason = 'admin_denied' }
end

local function slimRecipe(r)
    if type(r) ~= 'table' then return nil end
    local resultItem = r.result and r.result.item
    local oxLabel, oxDesc
    if OxItemCatalog then
        oxLabel = OxItemCatalog.Label and OxItemCatalog.Label(resultItem, r.labelOverride, r.label)
        oxDesc = OxItemCatalog.Description and OxItemCatalog.Description(resultItem, r.descriptionOverride)
    end
    return {
        id = r.id,
        label = oxLabel or r.label,
        description = r.description or oxDesc,
        category = r.category,
        station = r.station or r.category,
        rarity = r.rarity,
        result = r.result,
        ingredients = r.ingredients,
        tools = r.tools,
        requireTool = r.requireTool,
        duration = r.duration,
        xp = r.xp,
        requireLevel = r.requireLevel,
        requireSkill = r.requireSkill,
        requireSpec = r.requireSpec,
        requireBlueprint = r.requireBlueprint or r.blueprintId,
        blueprintId = r.requireBlueprint or r.blueprintId,
        teachable = r.teachable,
        batchMax = r.batchMax or r.maxQuantity,
        maxQuantity = r.maxQuantity or r.batchMax,
        signatureMode = r.signatureMode,
        discovery = r.discovery or r.requiresLearn,
        noiseLevel = r.noiseLevel,
        heat = r.heat,
        powerCost = r.powerCost,
        energy = r.energy or r.powerCost,
        stationLevel = r.stationLevel,
        queueable = r.queueable,
        tags = r.tags,
        steps = r.steps,
        chain = r.chain,
        _version = r._version or 0,
        _disabled = r._disabled == true,
        _overlay = r._overlay == true,
        _sqlOnly = r._sqlOnly == true,
        _updatedAt = r._updatedAt,
        _updatedBy = r._updatedBy,
        oxLabel = oxLabel,
        oxDescription = oxDesc,
    }
end

local function metaPayload()
    local stations = {}
    for id, _ in pairs(BenchTypes or {}) do
        stations[#stations + 1] = { id = id, label = (Config.BenchLabels and _(Config.BenchLabels[id] or id)) or id }
    end
    table.sort(stations, function(a, b) return a.id < b.id end)
    local categories = {}
    for id, def in pairs(Config.RecipeCategories or {}) do
        if id ~= 'all' then
            categories[#categories + 1] = { id = id, label = def.label or id, order = def.order or 99 }
        end
    end
    table.sort(categories, function(a, b) return (a.order or 99) < (b.order or 99) end)
    return {
        stations = stations,
        categories = categories,
        rarities = { 'common', 'uncommon', 'rare', 'epic', 'legendary' },
        signatureModes = { 'none', 'batch', 'individual' },
        version = Config.Version,
    }
end

lib.callback.register('sanctuary_crafting:craftadminMeta', function(src)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    return { ok = true, meta = metaPayload() }
end)

lib.callback.register('sanctuary_crafting:craftadminList', function(src, filter)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    filter = type(filter) == 'table' and filter or {}
    local q = type(filter.q) == 'string' and filter.q:lower() or ''
    local list = RecipeOverlay and RecipeOverlay.ListForAdmin and RecipeOverlay.ListForAdmin() or {}
    local out = {}
    for i = 1, #list do
        local r = list[i]
        if filter.station and filter.station ~= '' and (r.station or r.category) ~= filter.station then
            goto continue
        end
        if filter.category and filter.category ~= '' and r.category ~= filter.category then
            goto continue
        end
        if filter.rarity and filter.rarity ~= '' and tostring(r.rarity or '') ~= filter.rarity then
            goto continue
        end
        if filter.disabled == true and r._disabled ~= true then goto continue end
        if filter.disabled == false and r._disabled == true then goto continue end
        if q ~= '' then
            local hay = (tostring(r.id) .. ' ' .. tostring(r.label or '') .. ' ' .. tostring(r.result and r.result.item or '')):lower()
            if not hay:find(q, 1, true) then goto continue end
        end
        out[#out + 1] = slimRecipe(r)
        ::continue::
    end
    return { ok = true, recipes = out, total = #out }
end)

lib.callback.register('sanctuary_crafting:craftadminGet', function(src, recipeId)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    if type(recipeId) ~= 'string' then return { ok = false, reason = 'craft_invalid' } end
    local list = RecipeOverlay and RecipeOverlay.ListForAdmin and RecipeOverlay.ListForAdmin() or {}
    for i = 1, #list do
        if list[i].id == recipeId then
            return { ok = true, recipe = slimRecipe(list[i]) }
        end
    end
    local live = RecipeRegistry and RecipeRegistry.Get and RecipeRegistry.Get(recipeId)
    if live then return { ok = true, recipe = slimRecipe(live) } end
    return { ok = false, reason = 'craft_invalid' }
end)

local function draftToRecipe(draft)
    if type(draft) ~= 'table' then return nil end
    local id = draft.id
    if type(id) ~= 'string' or id == '' then return nil end
    local resultItem = draft.result
    local resultCount = tonumber(draft.qty) or 1
    if type(resultItem) == 'table' then
        resultCount = tonumber(resultItem.count or resultCount) or 1
        resultItem = resultItem.item
    end
    local ings = {}
    for i = 1, #(draft.ingredients or {}) do
        local ing = draft.ingredients[i]
        if type(ing) == 'table' and type(ing.item) == 'string' and ing.item ~= '' then
            ings[#ings + 1] = {
                item = ing.item,
                count = math.max(1, math.floor(tonumber(ing.count or ing.qty) or 1)),
                consumed = ing.consumed ~= false,
                optional = ing.optional == true,
                altGroup = ing.altGroup or ing.alt_group,
                substitutes = ing.substitutes,
            }
        end
    end
    local tools = {}
    for i = 1, #(draft.tools or {}) do
        local t = draft.tools[i]
        if type(t) == 'string' and t ~= '' then
            tools[#tools + 1] = { item = t, count = 1 }
        elseif type(t) == 'table' and type(t.item) == 'string' then
            tools[#tools + 1] = {
                item = t.item,
                count = math.max(1, math.floor(tonumber(t.count) or 1)),
                consume = t.consume == true,
                durabilityCost = tonumber(t.durabilityCost) or 0,
            }
        end
    end
    local xpAmount = tonumber(draft.xp)
    local xpCat = draft.xpCategory or draft.requireSkill
    if type(draft.xp) == 'table' then
        xpAmount = tonumber(draft.xp.amount)
        xpCat = draft.xp.category or xpCat
    end
    local recipe = {
        id = id,
        label = draft.label or draft.oxLabel or id,
        labelOverride = draft.labelOverride or draft.oxLabel,
        description = draft.description,
        descriptionOverride = draft.descriptionOverride,
        category = draft.category or 'scrap',
        station = draft.station or draft.category,
        rarity = draft.rarity,
        ingredients = ings,
        result = { item = resultItem, count = math.max(1, math.floor(resultCount)) },
        duration = math.max(500, math.floor(tonumber(draft.duration) or 5000)),
        requireLevel = tonumber(draft.requireLevel),
        requireSkill = draft.requireSkill,
        requireSpec = draft.requireSpec,
        requireBlueprint = draft.blueprint or draft.requireBlueprint or draft.blueprintId,
        blueprintId = draft.blueprint or draft.blueprintId or draft.requireBlueprint,
        teachable = draft.teachable == true,
        batchMax = tonumber(draft.batchMax),
        maxQuantity = tonumber(draft.batchMax),
        signatureMode = draft.signatureMode,
        discovery = draft.discovery == true,
        requiresLearn = draft.discovery == true,
        noiseLevel = tonumber(draft.noise or draft.noiseLevel),
        heat = tonumber(draft.heat),
        powerCost = tonumber(draft.energy or draft.powerCost),
        stationLevel = tonumber(draft.stationLevel),
        tools = #tools > 0 and tools or nil,
        tags = draft.tags,
        queueable = draft.queueable,
    }
    if xpAmount and xpCat then
        recipe.xp = { category = xpCat, amount = xpAmount }
    end
    return recipe
end

lib.callback.register('sanctuary_crafting:craftadminPreview', function(src, draft)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    local recipe = draftToRecipe(draft)
    if not recipe then return { ok = false, reason = 'craft_invalid' } end
    local valid = RecipeRegistry and RecipeRegistry.Validate and RecipeRegistry.Validate(recipe)
    local entry = nil
    if CraftingPipeline and CraftingPipeline.BuildRecipeEntry then
        entry = CraftingPipeline.BuildRecipeEntry(src, recipe, { includeHints = false })
    end
    local ox
    local item = recipe.result and recipe.result.item
    if item and OxItemCatalog then
        ox = {
            name = item,
            label = OxItemCatalog.Label and OxItemCatalog.Label(item, recipe.labelOverride, recipe.label),
            description = OxItemCatalog.Description and OxItemCatalog.Description(item, recipe.descriptionOverride),
        }
    end
    return { ok = true, valid = valid == true, entry = entry, ox = ox, recipe = slimRecipe(recipe) }
end)

lib.callback.register('sanctuary_crafting:craftadminValidate', function(src, draft)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    local recipe = draftToRecipe(draft)
    if not recipe then return { ok = false, reason = 'craft_invalid' } end
    local ok = RecipeRegistry.Validate(recipe)
    return { ok = ok == true, reason = ok and nil or 'craft_invalid', recipe = slimRecipe(recipe) }
end)

lib.callback.register('sanctuary_crafting:craftadminSave', function(src, draft, confirm)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    if confirm ~= true then return { ok = false, reason = 'admin_confirm_required' } end
    local recipe = draftToRecipe(draft)
    if not recipe then return { ok = false, reason = 'craft_invalid' } end
    if not RecipeRegistry.Validate(recipe) then
        return { ok = false, reason = 'craft_invalid' }
    end
    local ok, version = RecipeOverlay.Save(recipe, src, { disabled = draft._disabled == true })
    if not ok then return { ok = false, reason = version or 'craft_failed' } end
    return { ok = true, version = version, recipe = slimRecipe(recipe) }
end)

lib.callback.register('sanctuary_crafting:craftadminDisable', function(src, recipeId, disabled)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    local ok, version = RecipeOverlay.SetDisabled(recipeId, disabled ~= false, src)
    if not ok then return { ok = false, reason = version or 'craft_invalid' } end
    return { ok = true, version = version, disabled = disabled ~= false }
end)

lib.callback.register('sanctuary_crafting:craftadminDelete', function(src, recipeId)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    -- soft-delete
    local ok, version = RecipeOverlay.SetDisabled(recipeId, true, src)
    if not ok then return { ok = false, reason = version or 'craft_invalid' } end
    return { ok = true, version = version, disabled = true }
end)

lib.callback.register('sanctuary_crafting:craftadminDuplicate', function(src, recipeId, newId)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    if type(recipeId) ~= 'string' or type(newId) ~= 'string' or newId == '' then
        return { ok = false, reason = 'craft_invalid' }
    end
    local srcRecipe = RecipeRegistry.Get(recipeId)
    if not srcRecipe then
        local list = RecipeOverlay.ListForAdmin()
        for i = 1, #list do
            if list[i].id == recipeId then srcRecipe = list[i] break end
        end
    end
    if not srcRecipe then return { ok = false, reason = 'craft_invalid' } end
    local clone = RecipeSnapshot.Clone(srcRecipe)
    clone.id = newId
    clone._disabled = false
    clone._version = nil
    local ok, version = RecipeOverlay.Save(clone, src)
    if not ok then return { ok = false, reason = version or 'craft_failed' } end
    return { ok = true, version = version, recipe = slimRecipe(clone) }
end)

lib.callback.register('sanctuary_crafting:craftadminSearchOx', function(src, query, limit)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    limit = math.min(math.max(tonumber(limit) or 20, 1), 40)
    local q = type(query) == 'string' and query:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
    if q == '' or #q < 2 then
        return { ok = true, items = {} }
    end
    if not OxItemCatalog or not OxItemCatalog.Search then
        return { ok = true, items = {} }
    end
    return { ok = true, items = OxItemCatalog.Search(q, limit) }
end)

lib.callback.register('sanctuary_crafting:craftadminTest', function(src, recipeId, benchKey, batch, real)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    batch = math.max(1, math.floor(tonumber(batch) or 1))
    if real == true then
        -- explicit opt-in: real start (consumes items)
        if not CraftingPipeline or not CraftingPipeline.Start then
            return { ok = false, reason = 'craft_invalid' }
        end
        return CraftingPipeline.Start(src, recipeId, benchKey, batch)
    end
    -- dry-run: validate without RemoveItem
    if not CraftingPipeline or not CraftingPipeline.ValidateStart then
        return { ok = false, reason = 'craft_invalid' }
    end
    local ctx, reason, args = CraftingPipeline.ValidateStart(src, recipeId, benchKey, batch)
    if not ctx then
        return { ok = false, dryRun = true, reason = reason, args = args }
    end
    return {
        ok = true,
        dryRun = true,
        recipeId = ctx.recipe and ctx.recipe.id,
        batch = ctx.batch,
        ingredients = ctx.ingredients,
        label = ctx.recipe and ((OxItemCatalog and OxItemCatalog.RecipeLabel and OxItemCatalog.RecipeLabel(ctx.recipe)) or ctx.recipe.label),
    }
end)

lib.callback.register('sanctuary_crafting:craftadminVersions', function(src, recipeId)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    return { ok = true, versions = RecipeOverlay.Versions(recipeId) }
end)

lib.callback.register('sanctuary_crafting:craftadminRestore', function(src, recipeId, version)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    local ok, ver = RecipeOverlay.Restore(recipeId, version, src)
    if not ok then return { ok = false, reason = ver or 'craft_invalid' } end
    return { ok = true, version = ver }
end)

lib.callback.register('sanctuary_crafting:craftadminCreate', function(src, draft, confirm)
    if not CraftAdmin.IsAllowed(src) then return deny() end
    if confirm ~= true then return { ok = false, reason = 'admin_confirm_required' } end
    local recipe = draftToRecipe(draft)
    if not recipe then return { ok = false, reason = 'craft_invalid' } end
    if RecipeRegistry.Get(recipe.id) then
        return { ok = false, reason = 'admin_id_exists' }
    end
    if not RecipeRegistry.Validate(recipe) then
        return { ok = false, reason = 'craft_invalid' }
    end
    local ok, version = RecipeOverlay.Save(recipe, src)
    if not ok then return { ok = false, reason = version or 'craft_failed' } end
    return { ok = true, version = version, recipe = slimRecipe(recipe) }
end)
