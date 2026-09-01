--[[
    hooks/exports.lua — exports / events publics
]]

exports('AddCraftingHook', function(name, fn)
    CraftingCore.On(name, fn)
end)

exports('HasBlueprint', function(src, bpId)
    return Blueprints and Blueprints.Has(src, bpId)
end)

exports('LearnBlueprint', function(src, bpId)
    return Blueprints and Blueprints.Learn(src, bpId)
end)

exports('GetMastery', function(src, recipeId)
    return Mastery and Mastery.Get(src, recipeId) or 0
end)

exports('GetStation', function(key)
    return Benches and Benches.Resolve(key)
end)

exports('OpenCraftingForPlayer', function(src, benchKey)
    TriggerClientEvent('sanctuary_crafting:client:openBench', src, benchKey)
end)

-- Noise re-export
AddEventHandler('sanctuary_crafting:noise', function(src, level, coords, recipeId)
    DebugPrint('noise', src, level, recipeId)
end)
