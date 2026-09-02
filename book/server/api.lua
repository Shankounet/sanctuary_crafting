--[[
    book/server/api.lua — callbacks NUI lazy-load (intents only)
]]

local function guard(src)
    if not BookDB.Enabled() then return false, { ok = false, reason = 'book_disabled' } end
    return true
end

lib.callback.register('sanctuary_crafting:book:shell', function(src)
    if not guard(src) then return { ok = false, reason = 'book_disabled' } end
    return { ok = true, meta = SurvivalBook.ShellMeta(src) }
end)

lib.callback.register('sanctuary_crafting:book:dashboard', function(src)
    if not guard(src) then return { ok = false, reason = 'book_disabled' } end
    if not BookDB.Mod('Dashboard') then return { ok = false, reason = 'book_disabled' } end
    return { ok = true, data = SurvivalBook.Dashboard(src) }
end)

lib.callback.register('sanctuary_crafting:book:module', function(src, moduleName, payload)
    if not guard(src) then return { ok = false, reason = 'book_disabled' } end
    payload = type(payload) == 'table' and payload or {}
    local m = tostring(moduleName or '')

    if m == 'progression' then
        return { ok = true, data = SurvivalBook.GetProgression(src) }
    elseif m == 'nextUnlocks' then
        return { ok = true, data = SurvivalBook.NextUnlocks(src, payload.limit or 12) }
    elseif m == 'objectives' then
        return { ok = true, data = SurvivalBook.ListObjectives(src) }
    elseif m == 'pins' then
        return { ok = true, data = SurvivalBook.ListPins(src) }
    elseif m == 'shopping' then
        if (not payload.recipeId or payload.recipeId == '') and ShoppingList and ShoppingList.BuildFromPins then
            local list, err = ShoppingList.BuildFromPins(src)
            if not list then return { ok = false, reason = err } end
            return { ok = true, data = list, fromPins = true }
        end
        local list, err = SurvivalBook.SmartShopping(src, payload.recipeId, payload.batch, payload.depth)
        if not list then return { ok = false, reason = err } end
        return { ok = true, data = list }
    elseif m == 'tree' then
        local tree, err = SurvivalBook.CraftTreeMasked(src, payload.recipeId, payload.depth or 3)
        if not tree then return { ok = false, reason = err } end
        return { ok = true, data = tree }
    elseif m == 'resources' then
        return { ok = true, data = SurvivalBook.ListResources(src) }
    elseif m == 'discoveries' or m == 'history' then
        return { ok = true, data = SurvivalBook.ListHistory(src, payload.limit or 40) }
    elseif m == 'blueprints' then
        return { ok = true, data = SurvivalBook.ListBlueprints(src) }
    elseif m == 'artisans' then
        return { ok = true, data = SurvivalBook.ListArtisans(src) }
    elseif m == 'network' then
        return { ok = true, data = SurvivalBook.NetworkBySpecialty(src) }
    elseif m == 'orders' then
        return { ok = true, data = SurvivalBook.ListOrders(src) }
    elseif m == 'projects' or m == 'productions' then
        return { ok = true, data = SurvivalBook.Productions(src) }
    elseif m == 'notes' then
        return { ok = true, data = SurvivalBook.ListNotes(src) }
    elseif m == 'search' then
        return { ok = true, data = SurvivalBook.Search(src, payload.q) }
    elseif m == 'suggestions' then
        return { ok = true, data = SurvivalBook.Suggestions(src) }
    elseif m == 'canCraft' then
        return { ok = true, data = SurvivalBook.CanCraftNow(src, payload.limit or 40) }
    elseif m == 'workshop' then
        return { ok = true, data = SurvivalBook.MyWorkshop(src) }
    elseif m == 'maintenance' then
        return { ok = true, data = SurvivalBook.MaintenanceHints(src) }
    elseif m == 'stats' then
        return { ok = true, data = SurvivalBook.Stats(src) }
    elseif m == 'prefs' then
        return { ok = true, data = SurvivalBook.GetPrefs(src) }
    end
    return { ok = false, reason = 'craft_invalid' }
end)

-- Mutations
lib.callback.register('sanctuary_crafting:book:action', function(src, action, payload)
    if not guard(src) then return { ok = false, reason = 'book_disabled' } end
    payload = type(payload) == 'table' and payload or {}
    action = tostring(action or '')

    if action == 'addObjective' then
        local obj, err = SurvivalBook.AddObjective(src, payload.title, payload.kind, payload.payload)
        if not obj then return { ok = false, reason = err } end
        return { ok = true, data = obj }
    elseif action == 'addObjectiveRecipe' then
        local obj, err = SurvivalBook.AddObjectiveFromRecipe(src, payload.recipeId, {
            withMissing = payload.withMissing ~= false,
        })
        if not obj then return { ok = false, reason = err } end
        return { ok = true, data = obj }
    elseif action == 'completeObjective' then
        return { ok = SurvivalBook.CompleteObjective(src, payload.id) }
    elseif action == 'removeObjective' then
        return { ok = SurvivalBook.RemoveObjective(src, payload.id) }
    elseif action == 'pin' then
        local ok, err = SurvivalBook.PinRecipe(src, payload.recipeId)
        return { ok = ok and true or false, reason = err, pins = SurvivalBook.ListPins(src) }
    elseif action == 'unpin' then
        SurvivalBook.UnpinRecipe(src, payload.recipeId)
        return { ok = true, pins = SurvivalBook.ListPins(src) }
    elseif action == 'saveNote' then
        local note, err = SurvivalBook.SaveNote(src, payload)
        if not note then return { ok = false, reason = err } end
        return { ok = true, data = note }
    elseif action == 'deleteNote' then
        return { ok = SurvivalBook.DeleteNote(src, payload.id) }
    elseif action == 'discover' then
        local ok, err = SurvivalBook.DiscoverResource(src, payload.item, payload.label, payload.reason or 'manual')
        return { ok = ok and true or false, reason = err }
    elseif action == 'addArtisan' then
        local ok, err = SurvivalBook.AddArtisanContact(src, payload)
        return { ok = ok and true or false, reason = err }
    elseif action == 'createOrder' then
        local order, err = SurvivalBook.CreateOrder(src, payload)
        if not order then return { ok = false, reason = err } end
        return { ok = true, data = order }
    elseif action == 'orderStatus' then
        return { ok = SurvivalBook.SetOrderStatus(src, payload.orderUid, payload.status) }
    elseif action == 'setPrefs' then
        return { ok = SurvivalBook.SetPrefs(src, payload.prefs or payload) }
    end
    return { ok = false, reason = 'craft_invalid' }
end)
