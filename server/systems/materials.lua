--[[
    systems/materials.lua — ONE helper consume / reserve for pipeline + queue
    Default: consume (anti-dupe). ReserveOnQueue escrows mats so they cannot be spent elsewhere.
]]

CraftingMaterials = CraftingMaterials or {}

local function copyList(list)
    local out = {}
    for i = 1, #(list or {}) do
        local it = list[i]
        out[i] = { item = it.item, count = math.max(0, math.floor(tonumber(it.count) or 0)) }
    end
    return out
end

function CraftingMaterials.ConsumeOnStart()
    local c = Config.Crafting or {}
    if c.ConsumeOnStart ~= nil then return c.ConsumeOnStart ~= false end
    return c.RemoveIngredientsOnStart ~= false
end

function CraftingMaterials.ReserveOnQueue()
    return Config.Crafting and Config.Crafting.ReserveOnQueue == true
end

--- Physical take (remove from inventory). Rollback on partial failure.
---@return boolean ok, table|nil taken
function CraftingMaterials.Take(src, ingredients)
    local list = copyList(ingredients)
    for i = 1, #list do
        if list[i].count > 0 then
            if not exports.ox_inventory:RemoveItem(src, list[i].item, list[i].count) then
                for j = 1, i - 1 do
                    if list[j].count > 0 then
                        exports.ox_inventory:AddItem(src, list[j].item, list[j].count)
                    end
                end
                return false, nil
            end
        end
    end
    return true, list
end

--- 1:1 give-back (cancel / failed reserve). Never duplicates: only items previously taken.
function CraftingMaterials.Give(src, ingredients)
    for i = 1, #(ingredients or {}) do
        local it = ingredients[i]
        local n = math.floor(tonumber(it.count) or 0)
        if n > 0 then
            exports.ox_inventory:AddItem(src, it.item, n)
        end
    end
    return true
end

function CraftingMaterials.Has(src, ingredients)
    return Validation and Validation.HasIngredients and Validation.HasIngredients(src, ingredients)
end

--- Queue refund policy: never after finishAt (race). Reserve = 1:1 before finish. Consume = RefundOnCancel.
function CraftingMaterials.ShouldRefundQueue(entry)
    if not entry then return false end
    local finishAt = tonumber(entry.finishAt) or 0
    if finishAt > 0 and os.time() >= finishAt then
        return false
    end
    if CraftingMaterials.ReserveOnQueue() then
        return true
    end
    return not Config.Crafting or Config.Crafting.RefundOnCancel ~= false
end
