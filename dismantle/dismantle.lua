--[[
    dismantle/dismantle.lua — helpers démontage (logique principale dans pipeline)
]]
Dismantle = Dismantle or {}

function Dismantle.Enabled()
    return Config.Dismantling and Config.Dismantling.Enabled
end

function Dismantle.IsDismantleRecipe(recipe)
    return recipe and recipe.dismantle == true
end
