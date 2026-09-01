--[[
    book/server/bridge.lua — hooks craft / blueprints → DiscoverResource
]]

local function discoverItem(src, item, reason)
    if not item or not BookDB.Enabled() then return end
    SurvivalBook.DiscoverResource(src, item, nil, reason)
end

CraftingCore.On('craftCompleted', function(src, craft, given)
    if not BookDB.Enabled() then return end
    -- Discover result + any byproducts given
    if type(given) == 'table' then
        if given.item then
            discoverItem(src, given.item, 'craft')
        end
        for i = 1, #given do
            if given[i] and given[i].item then
                discoverItem(src, given[i].item, 'craft')
            end
        end
    end
    if craft and craft.recipeId then
        local recipe = Config.RecipeById and Config.RecipeById[craft.recipeId]
        if recipe and recipe.result and recipe.result.item then
            discoverItem(src, recipe.result.item, 'craft')
        end
        -- Discover consumed ingredients the player must have known
        if craft.ingredients then
            for i = 1, #craft.ingredients do
                discoverItem(src, craft.ingredients[i].item, 'craft_ingredient')
            end
        end
        local id = BookDB.Ident(src)
        if id then
            SurvivalBook.PushHistory(id, 'craft_completed', { recipeId = craft.recipeId })
        end
        -- Auto-complete recipe objectives
        local objs = SurvivalBook.ListObjectives(src)
        for _, o in ipairs(objs) do
            if not o.done and o.kind == 'recipe' and o.payload and o.payload.recipeId == craft.recipeId then
                SurvivalBook.CompleteObjective(src, o.id)
            end
        end
    end
end)

CraftingCore.On('blueprintLearned', function(src, blueprintId)
    if not BookDB.Enabled() then return end
    local id = BookDB.Ident(src)
    if id then
        SurvivalBook.PushHistory(id, 'blueprint_learned', { blueprintId = blueprintId })
    end
    SurvivalBook.Notify(src, 'book_bp_logged', 'inform', { tostring(blueprintId) })
end)

CraftingCore.On('queueCollected', function(src, entry)
    if not BookDB.Enabled() or not entry then return end
    local recipe = Config.RecipeById and Config.RecipeById[entry.recipeId]
    if recipe and recipe.result then
        discoverItem(src, recipe.result.item, 'queue')
    end
end)

CraftingCore.On('projectFinished', function(src, project)
    if not BookDB.Enabled() or not project then return end
    local recipe = Config.RecipeById and Config.RecipeById[project.recipeId]
    if recipe and recipe.result then
        discoverItem(src, recipe.result.item, 'project')
    end
end)

-- ox_inventory: when player uses artisan_card item (optional)
exports('useArtisanCard', function(event, item, inventory, slot, data)
    if event ~= 'usingItem' then return end
    if not BookDB.Enabled() then return false end
    local src = inventory.id
    local meta = item.metadata or {}
    local ok = SurvivalBook.AddArtisanContact(src, {
        contactId = meta.contactId or meta.id or ('card:' .. tostring(slot)),
        displayName = meta.displayName or meta.name or 'Artisan',
        specialty = meta.specialty,
        tier = meta.tier or 'unknown',
        source = 'artisan_card',
        note = meta.note,
    })
    if ok then
        -- consume card optional
        return
    end
    return false
end)
