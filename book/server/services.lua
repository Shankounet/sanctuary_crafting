--[[
    book/server/services.lua — shopping récursif, suggestions, progression (READ-ONLY), dashboard, workshop
]]

SurvivalBook = SurvivalBook or {}

local function invCount(src, item)
    return exports.ox_inventory:GetItemCount(src, item) or 0
end

local function producerFor(item)
    for id, rr in pairs(Config.RecipeById or {}) do
        if rr.result and rr.result.item == item then
            return id, rr
        end
    end
end

--- Smart recursive shopping: no double-count if intermediate owned; cycle guard
function SurvivalBook.SmartShopping(src, recipeId, batch, depth)
    if not BookDB.Mod('Shopping') then return nil, 'shopping_disabled' end
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end
    batch = math.max(1, math.floor(tonumber(batch) or 1))
    depth = depth or ((Config.Book.Shopping and Config.Book.Shopping.MaxDepth) or 5)

    local pool = {} -- mutable remaining inventory credit [item]=count
    local need = {} -- missing raw totals
    local visiting = {}

    local function poolHave(item)
        if pool[item] == nil then pool[item] = invCount(src, item) end
        return pool[item]
    end

    local function poolTake(item, amount)
        local have = poolHave(item)
        local take = math.min(have, amount)
        pool[item] = have - take
        return amount - take -- still missing
    end

    local function recipeIngredients(r)
        if type(r.steps) == 'table' and #r.steps > 0 then
            local ings = {}
            for _, step in ipairs(r.steps) do
                for _, ing in ipairs(step.ingredients or {}) do
                    ings[#ings + 1] = ing
                end
            end
            return ings
        end
        return r.ingredients or {}
    end

    --- Ensure `qty` units of recipe *result* are accounted for (craft or already owned intermediate)
    local function ensureRecipeOutput(rid, qty, d)
        if qty <= 0 or d < 0 then return end
        local r = Config.RecipeById[rid]
        if not r or not r.result then return end
        if visiting[rid] then
            -- cycle: treat as raw need on result item
            need[r.result.item] = (need[r.result.item] or 0) + qty
            return
        end
        visiting[rid] = true
        local perCraft = math.max(r.result.count or 1, 1)
        local crafts = math.ceil(qty / perCraft)
        for _, ing in ipairs(recipeIngredients(r)) do
            local req = (ing.count or 1) * crafts
            local missing = poolTake(ing.item, req)
            if missing > 0 then
                local prodId = select(1, producerFor(ing.item))
                if prodId and d > 0 then
                    ensureRecipeOutput(prodId, missing, d - 1)
                else
                    need[ing.item] = (need[ing.item] or 0) + missing
                end
            end
        end
        -- produced outputs credited to pool (for sibling branches)
        pool[r.result.item] = (poolHave(r.result.item)) + crafts * perCraft
        -- consume the qty we needed from pool
        poolTake(r.result.item, qty)
        visiting[rid] = nil
    end

    -- Top-level: we want `batch` crafts of the target recipe (not result units)
    local per = math.max((recipe.result and recipe.result.count) or 1, 1)
    ensureRecipeOutput(recipeId, batch * per, depth)

    local list = {}
    for item, count in pairs(need) do
        if count > 0 then
            local masked = SurvivalBook.MaskItem(src, item)
            list[#list + 1] = {
                item = item,
                count = count,
                label = masked.label,
                known = masked.known,
                have = invCount(src, item),
            }
        end
    end
    table.sort(list, function(a, b) return a.item < b.item end)
    return list
end

--- Craft tree with ??? for unknown resources
function SurvivalBook.CraftTreeMasked(src, recipeId, depth)
    if not BookDB.Mod('CraftTree') then return nil, 'book_disabled' end
    depth = depth or 3
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end

    local function nodeFor(rid, d)
        local r = Config.RecipeById[rid]
        if not r then return nil end
        local children = {}
        if d > 0 then
            local ings = r.ingredients or {}
            for i = 1, #ings do
                local item = ings[i].item
                local prodId = select(1, producerFor(item))
                if prodId then
                    children[#children + 1] = nodeFor(prodId, d - 1)
                else
                    local m = SurvivalBook.MaskItem(src, item)
                    children[#children + 1] = {
                        type = 'raw', item = item, count = ings[i].count,
                        label = m.label, known = m.known,
                    }
                end
            end
        end
        return {
            type = 'recipe', id = r.id, label = r.label,
            result = r.result, children = children,
        }
    end
    return nodeFor(recipeId, depth)
end

--- Progression READ-ONLY from CraftingSkills (ml_skills)
function SurvivalBook.GetProgression(src)
    if not BookDB.Mod('Progression') then return { available = false } end
    local cats = {
        (Config.Skills and Config.Skills.craftingCategory) or 'crafting',
        (Config.Skills and Config.Skills.survivalCategory) or 'survival',
    }
    local levels = {}
    local available = CraftingSkills and CraftingSkills.IsAvailable and CraftingSkills.IsAvailable()
    for i = 1, #cats do
        local cat = cats[i]
        levels[cat] = {
            level = available and CraftingSkills.GetLevel(cat, src) or 0,
            bonus = available and CraftingSkills.GetCategoryBonus(cat, src) or 0,
        }
    end
    return {
        available = available and true or false,
        levels = levels,
        note = 'ml_skills_readonly',
    }
end

--- Next unlocks from recipes (level/skill gates the player is close to)
function SurvivalBook.NextUnlocks(src, limit)
    if not BookDB.Mod('NextUnlocks') then return {} end
    limit = limit or 12
    local progression = SurvivalBook.GetProgression(src)
    local out = {}
    for id, r in pairs(Config.RecipeById or {}) do
        local req = r.requireLevel
        if req then
            local cat = CraftingSkills and CraftingSkills.LevelCategoryForRecipe and CraftingSkills.LevelCategoryForRecipe(r) or 'crafting'
            local lvl = progression.levels[cat] and progression.levels[cat].level or 0
            if lvl < req and (req - lvl) <= 3 then
                out[#out + 1] = {
                    recipeId = id, label = r.label, requireLevel = req,
                    currentLevel = lvl, category = r.category,
                    delta = req - lvl,
                }
            end
        end
        if r.requireSkill and CraftingSkills and CraftingSkills.IsAvailable and CraftingSkills.IsAvailable() then
            local cat = CraftingSkills.LevelCategoryForRecipe(r)
            if not CraftingSkills.HasSkill(cat, r.requireSkill, src) then
                -- show as locked skill (no other players)
                out[#out + 1] = {
                    recipeId = id, label = r.label, requireSkill = r.requireSkill,
                    category = r.category, kind = 'skill',
                }
            end
        end
    end
    table.sort(out, function(a, b)
        return (a.delta or 99) < (b.delta or 99)
    end)
    while #out > limit do out[#out] = nil end
    return out
end

local function recipeCraftability(src, recipe)
    local missing = {}
    local ings = recipe.ingredients or {}
    if type(recipe.steps) == 'table' and #recipe.steps > 0 then
        ings = {}
        for _, step in ipairs(recipe.steps) do
            for _, ing in ipairs(step.ingredients or {}) do
                ings[#ings + 1] = ing
            end
        end
    end
    local okIngredients = true
    for i = 1, #ings do
        local need = ings[i].count or 1
        local have = invCount(src, ings[i].item)
        if have < need then
            okIngredients = false
            missing[#missing + 1] = { item = ings[i].item, need = need, have = have }
        end
    end

    local gatesOk = true
    local gateReason
    if CraftingSkills and CraftingSkills.CheckRecipeGates then
        local ok, reason = CraftingSkills.CheckRecipeGates(src, recipe)
        if not ok then gatesOk = false; gateReason = reason end
    end

    local bpOk = true
    local bpId = recipe.requireBlueprint or recipe.blueprintId
    if bpId and Blueprints and Blueprints.Has then
        bpOk = Blueprints.Has(src, bpId)
    end

    local can = okIngredients and gatesOk and bpOk
    return can, {
        ingredients = okIngredients,
        gates = gatesOk,
        gateReason = gateReason,
        blueprint = bpOk,
        missing = missing,
        almost = (not okIngredients) and #missing <= 2 and gatesOk and bpOk,
        oneLevelAway = (not gatesOk) and gateReason == 'craft_level_required',
    }
end

function SurvivalBook.CanCraftNow(src, limit)
    if not BookDB.Mod('CanCraft') then return {} end
    limit = limit or 30
    local out = {}
    for id, r in pairs(Config.RecipeById or {}) do
        local can, info = recipeCraftability(src, r)
        if can then
            out[#out + 1] = { recipeId = id, label = r.label, category = r.category }
        end
        if #out >= limit then break end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function SurvivalBook.Suggestions(src)
    if not BookDB.Mod('Suggestions') then return { almost = {}, oneLevel = {} } end
    local almost, oneLevel = {}, {}
    for id, r in pairs(Config.RecipeById or {}) do
        local can, info = recipeCraftability(src, r)
        if not can then
            if info.almost then
                almost[#almost + 1] = {
                    recipeId = id, label = r.label, missing = info.missing, category = r.category,
                }
            elseif info.oneLevelAway then
                oneLevel[#oneLevel + 1] = {
                    recipeId = id, label = r.label, category = r.category,
                }
            end
        end
    end
    while #almost > 15 do almost[#almost] = nil end
    while #oneLevel > 15 do oneLevel[#oneLevel] = nil end
    return { almost = almost, oneLevel = oneLevel }
end

function SurvivalBook.MyWorkshop(src)
    if not BookDB.Mod('Workshop') then return {} end
    local id = BookDB.Ident(src)
    local list = {}
    if Benches and Benches.GetAllForClient then
        for _, b in ipairs(Benches.GetAllForClient()) do
            -- Own placed benches only (no coords leaked beyond category/level for book — still need some location awareness for "my workshop")
            -- Spec: No GPS — omit exact coords from book payload
            if b.kind == 'placed' and b.owner == id then
                list[#list + 1] = {
                    key = b.key,
                    category = b.category,
                    stationLevel = b.stationLevel,
                    modules = b.modules or {},
                    powered = b.powered,
                    kind = 'placed',
                }
            end
        end
    end
    -- World benches: category only (no coords)
    for _, w in ipairs(Config.WorldBenches or {}) do
        list[#list + 1] = {
            key = 'world:' .. (w.id or '?'),
            category = w.category,
            stationLevel = w.stationLevel or 1,
            kind = 'world',
            knownArea = true, -- qualitative, no GPS
        }
    end
    return list
end

function SurvivalBook.MaintenanceHints(src)
    if not BookDB.Mod('Maintenance') then return {} end
    local hints = {}
    -- Tool durability in inventory
    if Config.Tools and Config.Tools.Enabled then
        local key = Config.Tools.DurabilityKey or 'durability'
        -- Best-effort: scan known tools from recipes
        local toolsSeen = {}
        for _, r in pairs(Config.RecipeById or {}) do
            if r.requireTool and r.requireTool.item then
                toolsSeen[r.requireTool.item] = true
            end
        end
        for tool, _ in pairs(toolsSeen) do
            local count = invCount(src, tool)
            if count > 0 then
                hints[#hints + 1] = {
                    kind = 'tool',
                    item = tool,
                    label = SurvivalBook.MaskItem(src, tool).label,
                    hint = 'book_maint_tool',
                }
            end
        end
    end
    for _, st in ipairs(SurvivalBook.MyWorkshop(src)) do
        if st.kind == 'placed' and st.powered == false then
            hints[#hints + 1] = {
                kind = 'power',
                key = st.key,
                hint = 'book_maint_power',
                category = st.category,
            }
        end
    end
    return hints
end

function SurvivalBook.Productions(src)
    if not BookDB.Mod('Productions') then return { queue = {}, projects = {} } end
    local queue = {}
    if CraftQueue and CraftQueue.List then
        for _, e in ipairs(CraftQueue.List(src) or {}) do
            local r = Config.RecipeById and Config.RecipeById[e.recipeId]
            queue[#queue + 1] = {
                craftId = e.craftId,
                recipeId = e.recipeId,
                label = r and r.label or e.recipeId,
                finishAt = e.finishAt,
                batch = e.batch,
            }
        end
    end
    local projects = {}
    if Projects and BookDB.Mod('Projects') then
        -- List open projects where player is owner/contributor (no other inventories)
        local id = BookDB.Ident(src)
        local rows = MySQL.query.await(
            "SELECT project_uid, recipe_id, status, owner FROM sanctuary_projects WHERE status = 'open' AND (owner = ? OR contributors LIKE ?)",
            { id, '%' .. (id or '') .. '%' }
        ) or {}
        for i = 1, #rows do
            local r = Config.RecipeById and Config.RecipeById[rows[i].recipe_id]
            projects[#projects + 1] = {
                projectUid = rows[i].project_uid,
                recipeId = rows[i].recipe_id,
                label = r and r.label or rows[i].recipe_id,
                status = rows[i].status,
                isOwner = rows[i].owner == id,
            }
        end
    end
    return { queue = queue, projects = projects }
end

function SurvivalBook.ListBlueprints(src)
    if not BookDB.Mod('Blueprints') then return {} end
    if not Blueprints or not Blueprints.List then return {} end
    local list = Blueprints.List(src) or {}
    local out = {}
    for i = 1, #list do
        out[i] = { id = list[i], label = list[i] }
    end
    return out
end

function SurvivalBook.Stats(src)
    if not BookDB.Mod('Stats') then return {} end
    local id = BookDB.Ident(src)
    if not id then return {} end
    local function count(sql, ...)
        return MySQL.scalar.await(sql, { ... }) or 0
    end
    return {
        resources = count('SELECT COUNT(*) FROM sanctuary_book_discovered_resources WHERE identifier = ?', id),
        objectivesOpen = count('SELECT COUNT(*) FROM sanctuary_book_objectives WHERE identifier = ? AND done = 0', id),
        objectivesDone = count('SELECT COUNT(*) FROM sanctuary_book_objectives WHERE identifier = ? AND done = 1', id),
        pins = count('SELECT COUNT(*) FROM sanctuary_book_pins WHERE identifier = ?', id),
        notes = count('SELECT COUNT(*) FROM sanctuary_book_notes WHERE identifier = ?', id),
        artisans = count('SELECT COUNT(*) FROM sanctuary_book_artisans WHERE identifier = ?', id),
        orders = count('SELECT COUNT(*) FROM sanctuary_book_orders WHERE owner = ?', id),
        blueprints = #(SurvivalBook.ListBlueprints(src) or {}),
        history = count('SELECT COUNT(*) FROM sanctuary_book_history WHERE identifier = ?', id),
    }
end

function SurvivalBook.Search(src, query)
    if not BookDB.Mod('Search') then return {} end
    query = tostring(query or ''):lower()
    if #query < 2 then return {} end
    local hits = {}
    local function push(kind, id, label, extra)
        if label and label:lower():find(query, 1, true) then
            hits[#hits + 1] = { kind = kind, id = id, label = label, extra = extra }
        end
    end
    for id, r in pairs(Config.RecipeById or {}) do
        push('recipe', id, r.label, { category = r.category })
    end
    for _, res in ipairs(SurvivalBook.ListResources(src)) do
        push('resource', res.item, res.label)
    end
    for _, bp in ipairs(SurvivalBook.ListBlueprints(src)) do
        push('blueprint', bp.id, bp.label)
    end
    for _, a in ipairs(SurvivalBook.ListArtisans(src)) do
        push('artisan', a.contactId, a.displayName, { specialty = a.specialty })
    end
    for _, n in ipairs(SurvivalBook.ListNotes(src)) do
        push('note', tostring(n.id), n.title)
    end
    while #hits > 40 do hits[#hits] = nil end
    return hits
end

function SurvivalBook.Dashboard(src)
    if not BookDB.Mod('Dashboard') then return {} end
    return {
        progression = SurvivalBook.GetProgression(src),
        nextUnlocks = SurvivalBook.NextUnlocks(src, 5),
        pins = SurvivalBook.ListPins(src),
        objectives = (function()
            local all = SurvivalBook.ListObjectives(src)
            local open = {}
            for i = 1, #all do
                if not all[i].done then open[#open + 1] = all[i] end
                if #open >= 5 then break end
            end
            return open
        end)(),
        canCraft = SurvivalBook.CanCraftNow(src, 8),
        suggestions = SurvivalBook.Suggestions(src),
        productions = SurvivalBook.Productions(src),
        stats = SurvivalBook.Stats(src),
        maintenance = SurvivalBook.MaintenanceHints(src),
        modules = SurvivalBook.EnabledModules(),
    }
end

function SurvivalBook.EnabledModules()
    local names = {
        'Dashboard','Progression','NextUnlocks','Objectives','Pins','Shopping','CraftTree',
        'Resources','Discoveries','Blueprints','Artisans','Network','Orders','Projects',
        'Notes','Search','Suggestions','CanCraft','Workshop','Maintenance','Productions',
        'Notifications','History','Stats',
    }
    local m = {}
    for i = 1, #names do
        m[names[i]] = BookDB.Mod(names[i])
    end
    return m
end

function SurvivalBook.ShellMeta(src)
    return {
        accent = (Config.Book and Config.Book.Accent) or '#9a8866',
        theme = (Config.Book and Config.Book.Theme) or 'field_manual',
        modules = SurvivalBook.EnabledModules(),
        locale = Config.Locale or 'fr',
        title = _('book_title'),
        subtitle = _('book_subtitle'),
    }
end
