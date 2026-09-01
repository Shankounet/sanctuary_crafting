--[[
    integrations/power.lua
    Si Config.Power.Enabled == false → toujours true.
    Sinon : station.modules contient 'power_cell' OU world benches powered by default.
]]

CraftingPower = CraftingPower or {}

---@param station table|nil
---@return boolean
function CraftingPower.HasPower(station)
    if not Config.Power or not Config.Power.Enabled then
        return true
    end
    if not station then return false end
    if station.kind == 'world' then
        return station.powered ~= false
    end
    local mods = station.modules or {}
    for i = 1, #mods do
        if mods[i] == 'power_cell' or mods[i] == 'generator' then
            return true
        end
    end
    -- recipe without powerCost can still run
    return false
end

---@param station table
---@param recipe table
---@return boolean
function CraftingPower.CanRunRecipe(station, recipe)
    if not recipe.powerCost or recipe.powerCost <= 0 then
        return true
    end
    return CraftingPower.HasPower(station)
end
