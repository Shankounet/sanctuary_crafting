--[[
    tests/recipe_state_spec.lua — priority of global recipeState
    savoir → niveau → plan → spécialité → atelier → outil → matériaux → prêt
]]

local function assertEq(a, b, msg)
    if a ~= b then
        error((msg or 'assertEq') .. (' failed: %s ~= %s'):format(tostring(a), tostring(b)), 2)
    end
end

local function resolve(opts)
    opts = opts or {}
    local skillOk = opts.skillOk ~= false
    local levelOk = opts.levelOk ~= false
    local blueprintOk = opts.blueprintOk ~= false
    local specOk = opts.specOk ~= false
    local stationOk = opts.stationOk ~= false
    local toolOk = opts.toolOk ~= false
    local materialsOk = opts.materialsOk ~= false
    if not skillOk then return 'skill_locked' end
    if not levelOk then return 'level_required' end
    if not blueprintOk then return 'blueprint_required' end
    if not specOk then return 'spec_required' end
    if not stationOk then return 'station_incompatible' end
    if not toolOk then return 'tool_required' end
    if not materialsOk then return 'materials_missing' end
    return 'ready'
end

assertEq(resolve({ skillOk = false, stationOk = false }), 'skill_locked', 'A')
assertEq(resolve({ skillOk = true, levelOk = false, materialsOk = false }), 'level_required', 'B')
assertEq(resolve({ skillOk = true, blueprintOk = false, stationOk = false }), 'blueprint_required', 'Bp')
assertEq(resolve({ skillOk = true, specOk = false, stationOk = true, materialsOk = false }), 'spec_required', 'Spec')
assertEq(resolve({ skillOk = true, stationOk = false, materialsOk = false }), 'station_incompatible', 'C')
assertEq(resolve({ skillOk = true, stationOk = true, toolOk = false, materialsOk = false }), 'tool_required', 'D')
assertEq(resolve({ skillOk = true, stationOk = true, materialsOk = false }), 'materials_missing', 'E')
assertEq(resolve({}), 'ready', 'F')

print('recipe_state_spec: ok')
