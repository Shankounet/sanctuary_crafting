--[[
    reverse/reverse.lua — reverse engineering (item → chance learn blueprint / recipe hint)
]]

ReverseEng = ReverseEng or {}

---@param src number
---@param itemName string
---@return boolean, string|nil
function ReverseEng.Analyze(src, itemName)
    if not Config.ReverseEngineering or not Config.ReverseEngineering.Enabled then
        return false, 'reverse_disabled'
    end
    if (exports.ox_inventory:GetItemCount(src, itemName) or 0) < 1 then
        return false, 'craft_no_ingredients'
    end
    -- Find recipe that results in this item
    local matched
    for _, r in pairs(Config.RecipeById) do
        if r.result and r.result.item == itemName then
            matched = r
            break
        end
    end
    if not matched then return false, 'reverse_unknown' end

    if not exports.ox_inventory:RemoveItem(src, itemName, 1) then
        return false, 'craft_no_ingredients'
    end

    local chance = 0.35
    local bonus = CraftingSkills.GetCategoryBonus(Config.Skills.craftingCategory or 'crafting', src)
    chance = math.min(0.9, chance + (bonus or 0) / 200)

    if math.random() > chance then
        TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = _('reverse_fail') })
        CraftingCore.Emit('reverseFailed', src, itemName)
        return true, 'fail'
    end

    local bpId = matched.blueprintId or matched.requireBlueprint or ('bp_rev_' .. matched.id)
    if Config.Blueprints and Config.Blueprints.Enabled then
        Blueprints.Learn(src, bpId)
    end
    CraftingCore.Emit('reverseSuccess', src, matched.id, bpId)
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = _('reverse_success', matched.label) })
    return true, matched.id
end

lib.callback.register('sanctuary_crafting:reverseEngineer', function(src, itemName)
    local ok, extra = ReverseEng.Analyze(src, itemName)
    return { ok = ok, result = extra }
end)
