--[[
    shopping/shopping.lua — liste d'achats serveur (ingrédients manquants)
]]

ShoppingList = ShoppingList or {}
local lists = {} -- [src] = { [item]=count }

function ShoppingList.BuildFromRecipe(src, recipeId, batch)
    if not Config.ShoppingList or not Config.ShoppingList.Enabled then
        return nil, 'shopping_disabled'
    end
    local recipe = Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end
    batch = math.max(1, math.floor(tonumber(batch) or 1))
    local missing = {}
    for i = 1, #recipe.ingredients do
        local ing = recipe.ingredients[i]
        local need = (ing.count or 1) * batch
        local have = exports.ox_inventory:GetItemCount(src, ing.item) or 0
        if have < need then
            missing[ing.item] = (missing[ing.item] or 0) + (need - have)
        end
    end
    lists[src] = lists[src] or {}
    for item, count in pairs(missing) do
        lists[src][item] = (lists[src][item] or 0) + count
    end
    return lists[src]
end

function ShoppingList.Get(src)
    return lists[src] or {}
end

function ShoppingList.Clear(src)
    lists[src] = {}
    return true
end


local function invCount(src, item)
    if GetResourceState("ox_inventory") ~= "started" then return 0 end
    return exports.ox_inventory:GetItemCount(src, item) or 0
end

local function producerFor(item)
    for id, rr in pairs(Config.RecipeById or {}) do
        if rr.result and rr.result.item == item and not rr.dismantle then
            return id, rr
        end
    end
end

local function recipeIngredients(r)
    if type(r.steps) == "table" and #r.steps > 0 then
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

local function facingLabel(recipe)
    if OxItemCatalog and OxItemCatalog.RecipeLabel then
        return OxItemCatalog.RecipeLabel(recipe)
    end
    return recipe and recipe.label
end

local function itemLab(item)
    if OxItemCatalog and OxItemCatalog.Label then
        return OxItemCatalog.Label(item)
    end
    return item
end

--- Shared-pool expansion across jobs. 5+8+2=15, owned subtracted once.
function ShoppingList.ExpandNeeds(src, jobs, depth)
    depth = depth or ((Config.Book and Config.Book.Shopping and Config.Book.Shopping.MaxDepth) or 5)
    local pool = {}
    local need = {}
    local sources = {} -- [item] = { {recipeId,label,count}, ... }
    local visiting = {}

    local function poolHave(item)
        if pool[item] == nil then pool[item] = invCount(src, item) end
        return pool[item]
    end

    local function poolTake(item, amount)
        local have = poolHave(item)
        local take = math.min(have, amount)
        pool[item] = have - take
        return amount - take
    end

    local function addSource(item, recipeId, label, count)
        if count <= 0 then return end
        sources[item] = sources[item] or {}
        local list = sources[item]
        for i = 1, #list do
            if list[i].recipeId == recipeId then
                list[i].count = (list[i].count or 0) + count
                return
            end
        end
        list[#list + 1] = { recipeId = recipeId, label = label, count = count }
    end

    local function ensureRecipeOutput(rid, qty, d, rootId, rootLabel)
        if qty <= 0 or d < 0 then return end
        local r = Config.RecipeById and Config.RecipeById[rid]
        if not r or not r.result then return end
        if visiting[rid] then
            need[r.result.item] = (need[r.result.item] or 0) + qty
            addSource(r.result.item, rootId, rootLabel, qty)
            return
        end
        visiting[rid] = true
        local perCraft = math.max(r.result.count or 1, 1)
        local crafts = math.ceil(qty / perCraft)
        for _, ing in ipairs(recipeIngredients(r)) do
            local req = (ing.count or 1) * crafts
            addSource(ing.item, rootId, rootLabel, req)
            local missing = poolTake(ing.item, req)
            if missing > 0 then
                local prodId = select(1, producerFor(ing.item))
                if prodId and d > 0 then
                    ensureRecipeOutput(prodId, missing, d - 1, rootId, rootLabel)
                else
                    need[ing.item] = (need[ing.item] or 0) + missing
                end
            end
        end
        pool[r.result.item] = (poolHave(r.result.item)) + crafts * perCraft
        poolTake(r.result.item, qty)
        visiting[rid] = nil
    end

    for _, job in ipairs(jobs or {}) do
        local rid = job.recipeId or job.id
        local recipe = Config.RecipeById and Config.RecipeById[rid]
        if recipe then
            local batch = math.max(1, math.floor(tonumber(job.batch) or 1))
            local per = math.max((recipe.result and recipe.result.count) or 1, 1)
            local lab = job.label or facingLabel(recipe) or rid
            ensureRecipeOutput(rid, batch * per, depth, rid, lab)
        end
    end

    local list = {}
    local seen = {}
    for item, srcs in pairs(sources) do
        local gross = 0
        for i = 1, #srcs do gross = gross + (srcs[i].count or 0) end
        local owned = invCount(src, item)
        local remaining = need[item] or math.max(0, gross - owned)
        list[#list + 1] = {
            item = item,
            label = itemLab(item),
            need = gross,
            owned = owned,
            remaining = remaining,
            count = remaining,
            sources = srcs,
        }
        seen[item] = true
    end
    for item, missing in pairs(need) do
        if not seen[item] then
            local owned = invCount(src, item)
            list[#list + 1] = {
                item = item,
                label = itemLab(item),
                need = missing + owned,
                owned = owned,
                remaining = missing,
                count = missing,
                sources = {},
            }
        end
    end
    table.sort(list, function(a, b) return (a.label or a.item) < (b.label or b.item) end)
    return list
end

function ShoppingList.BuildFromPins(src)
    if not Config.ShoppingList or not Config.ShoppingList.Enabled then
        return nil, "shopping_disabled"
    end
    local jobs = {}
    local extraItems = {}
    if SurvivalBook and SurvivalBook.ListPins then
        local pins = SurvivalBook.ListPins(src) or {}
        for i = 1, #pins do
            local pin = pins[i]
            local rid = pin.recipeId or pin
            if pin.kind == 'resource' or (type(rid) == 'string' and rid:sub(1, 4) == 'res:') then
                local item = pin.item
                if (not item or item == '') and type(rid) == 'string' then
                    item = rid:sub(5)
                end
                if type(item) == 'string' and item ~= '' then
                    extraItems[#extraItems + 1] = item
                end
            elseif type(rid) == 'string' then
                jobs[#jobs + 1] = { recipeId = rid, batch = 1, label = pin.label }
            end
        end
    end
    local list = ShoppingList.ExpandNeeds(src, jobs) or {}
    local haveIdx = {}
    for i = 1, #list do
        if list[i].item then haveIdx[list[i].item] = i end
    end
    for i = 1, #extraItems do
        local item = extraItems[i]
        if not haveIdx[item] then
            local owned = invCount(src, item)
            local remaining = math.max(0, 1 - owned)
            if remaining > 0 then
                list[#list + 1] = {
                    item = item,
                    label = itemLab(item),
                    need = 1,
                    owned = owned,
                    remaining = remaining,
                    count = remaining,
                    sources = {},
                }
                haveIdx[item] = #list
            end
        end
    end
    -- also keep a flat map for legacy NUI shop panel
    local map = {}
    for i = 1, #list do
        local row = list[i]
        map[row.item] = {
            count = row.remaining,
            need = row.need,
            owned = row.owned,
            remaining = row.remaining,
            label = row.label,
            sources = row.sources,
        }
    end
    lists[src] = map
    return list, nil, map
end

function ShoppingList.Remove(src, item)
    if lists[src] then lists[src][item] = nil end
end

AddEventHandler('playerDropped', function()
    lists[source] = nil
end)

local function enrichShopMap(map)
    local out = {}
    for item, count in pairs(map or {}) do
        out[item] = {
            count = count,
            need = count,
            label = (OxItemCatalog and OxItemCatalog.Label and OxItemCatalog.Label(item)) or item,
        }
    end
    return out
end

lib.callback.register('sanctuary_crafting:shoppingBuild', function(src, recipeId, batch)
    local list, err = ShoppingList.BuildFromRecipe(src, recipeId, batch)
    if not list then return { ok = false, reason = err } end
    return { ok = true, list = enrichShopMap(list) }
end)

lib.callback.register('sanctuary_crafting:shoppingGet', function(src)
    local list = ShoppingList.BuildFromPins(src)
    if type(list) == "table" and #list > 0 then
        return { ok = true, list = list, fromPins = true }
    end
    return { ok = true, list = enrichShopMap(ShoppingList.Get(src)), fromPins = false }
end)

lib.callback.register('sanctuary_crafting:shoppingFromPins', function(src)
    local list, err = ShoppingList.BuildFromPins(src)
    if not list then return { ok = false, reason = err } end
    return { ok = true, list = list, fromPins = true }
end)

lib.callback.register('sanctuary_crafting:shoppingClear', function(src)
    ShoppingList.Clear(src)
    return { ok = true }
end)
