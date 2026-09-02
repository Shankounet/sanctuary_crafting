--[[
    tools/tools.lua — durabilité outils (ox metadata only, no second durability)
    Has requires durability > 0. Wear on complete/collect (not start).
]]

Tools = Tools or {}

local function durKey()
    return (Config.Tools and Config.Tools.DurabilityKey) or 'durability'
end

local function defaultDur()
    return (Config.Tools and Config.Tools.DefaultDurability) or 100
end

local function slotsOf(src, itemName)
    if GetResourceState('ox_inventory') ~= 'started' then return {} end
    local items = exports.ox_inventory:Search(src, 'slots', itemName) or {}
    if type(items) ~= 'table' then return {} end
    return items
end

local function slotDur(it)
    if not it then return 0 end
    local meta = it.metadata or {}
    local dur = meta[durKey()]
    if dur == nil then dur = defaultDur() end
    return tonumber(dur) or 0
end

--- True if player has at least one copy with durability > 0.
function Tools.Has(src, itemName)
    if not itemName then return true end
    if not Config.Tools or not Config.Tools.Enabled then
        return (exports.ox_inventory:GetItemCount(src, itemName) or 0) > 0
    end
    for _, it in pairs(slotsOf(src, itemName)) do
        if it and it.slot and slotDur(it) > 0 then
            return true
        end
    end
    return false
end

function Tools.Durability(src, itemName)
    local best = nil
    for _, it in pairs(slotsOf(src, itemName)) do
        if it and it.slot then
            local d = slotDur(it)
            if d > 0 and (best == nil or d > best) then best = d end
        end
    end
    return best
end

local function recipeToolList(recipe)
    local list = {}
    if not recipe then return list end
    if recipe.tools and type(recipe.tools) == 'table' then
        for i = 1, #recipe.tools do
            local t = recipe.tools[i]
            if type(t) == 'string' then
                list[#list + 1] = { item = t, durabilityCost = 1, consume = false }
            elseif type(t) == 'table' and t.item then
                list[#list + 1] = t
            end
        end
        return list
    end
    if recipe.requireTool then
        if type(recipe.requireTool) == 'string' then
            list[#list + 1] = { item = recipe.requireTool, durabilityCost = 1, consume = false }
        elseif type(recipe.requireTool) == 'table' and recipe.requireTool.item then
            list[#list + 1] = recipe.requireTool
        end
    end
    return list
end

function Tools.HasRecipe(src, recipe)
    if not Config.Tools or not Config.Tools.Enabled then return true end
    local list = recipeToolList(recipe)
    if #list == 0 then return true end
    for i = 1, #list do
        if not Tools.Has(src, list[i].item) then
            return false
        end
    end
    return true
end

--- Wear ox metadata. Removes the item only when durability hits 0.
function Tools.Consume(src, requireTool)
    if not Config.Tools or not Config.Tools.Enabled then return true end
    if not requireTool or not requireTool.item then return true end
    local itemName = requireTool.item
    local cost = tonumber(requireTool.durabilityCost)
    if not cost or cost <= 0 then
        cost = (Config.Tools.WearPerCraft) or 1
    end
    local key = durKey()

    local chosen
    local chosenDur = 1e9
    for _, it in pairs(slotsOf(src, itemName)) do
        if it and it.slot then
            local d = slotDur(it)
            if d > 0 and d < chosenDur then
                chosen = it
                chosenDur = d
            end
        end
    end
    if not chosen then return false end

    local meta = chosen.metadata or {}
    local dur = slotDur(chosen) - cost
    if dur <= 0 then
        exports.ox_inventory:RemoveItem(src, itemName, 1, nil, chosen.slot)
        TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = _('tool_broken', itemName) })
    else
        meta[key] = dur
        exports.ox_inventory:SetMetadata(src, chosen.slot, meta)
    end
    return true
end

Tools.Wear = Tools.Consume

--- Wear all recipe tools (complete / collect). consume=true still only wears unless item must be removed.
function Tools.WearRecipe(src, recipe, batch)
    if not Config.Tools or not Config.Tools.Enabled then return true end
    local list = recipeToolList(recipe)
    if #list == 0 then return true end
    local n = math.max(1, math.floor(tonumber(batch) or 1))
    for i = 1, #list do
        local t = list[i]
        if t.consume == true then
            local c = math.max(1, tonumber(t.count) or 1)
            if not exports.ox_inventory:RemoveItem(src, t.item, c) then
                return false
            end
        else
            local cost = tonumber(t.durabilityCost)
            if not cost or cost <= 0 then cost = Config.Tools.WearPerCraft or 1 end
            for _ = 1, n do
                if not Tools.Consume(src, { item = t.item, durabilityCost = cost }) then
                    return false
                end
            end
        end
    end
    return true
end
