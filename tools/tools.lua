--[[
    tools/tools.lua — durabilité outils (metadata)
]]

Tools = Tools or {}

---@param src number
---@param requireTool table { item, durabilityCost }
---@return boolean
function Tools.Consume(src, requireTool)
    if not Config.Tools or not Config.Tools.Enabled then return true end
    if not requireTool or not requireTool.item then return true end
    local itemName = requireTool.item
    local cost = requireTool.durabilityCost or 1
    local key = (Config.Tools.DurabilityKey) or 'durability'

    local items = exports.ox_inventory:Search(src, 'slots', itemName) or {}
    if type(items) ~= 'table' then return false end

    local slotData
    for _, it in pairs(items) do
        if it and it.slot then
            slotData = it
            break
        end
    end
    if not slotData then return false end

    local meta = slotData.metadata or {}
    local dur = meta[key]
    if dur == nil then dur = Config.Tools.DefaultDurability or 100 end
    dur = dur - cost
    if dur <= 0 then
        exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slotData.slot)
        TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = _('tool_broken', itemName) })
    else
        meta[key] = dur
        exports.ox_inventory:SetMetadata(src, slotData.slot, meta)
    end
    return true
end

function Tools.Has(src, itemName)
    return (exports.ox_inventory:GetItemCount(src, itemName) or 0) > 0
end
