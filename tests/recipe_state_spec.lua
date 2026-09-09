--[[
    tests/recipe_state_spec.lua — priority of global recipeState (A–E)
]]
local function assertEq(a, b, msg)
    if a ~= b then
        error((msg or 'assertEq') .. (' failed: %s ~= %s'):format(tostring(a), tostring(b)), 2)
    end
end

local function resolve(opts)
    local skillOk = opts.skillOk ~= false
    local levelOk = opts.levelOk ~= false
    local blueprintOk = opts.blueprintOk ~= false
    local stationOk = opts.stationOk ~= false
    local toolOk = opts.toolOk ~= false
    local materialsOk = opts.materialsOk ~= false
    local mystery = opts.mystery == true
    local almost = opts.almost == true
    if mystery then return 'mystery' end
    if not skillOk then return 'skill_locked' end
    if not levelOk then return 'level_required' end
    if not blueprintOk then return 'blueprint_required' end
    if not stationOk then return 'station_incompatible' end
    if not toolOk then return 'tool_required' end
    if not materialsOk then return almost and 'almost' or 'materials_missing' end
    return 'ready'
end

assertEq(resolve({ skillOk = false, stationOk = true, materialsOk = false }), 'skill_locked', 'A')
assertEq(resolve({ skillOk = true, materialsOk = false }), 'materials_missing', 'B')
assertEq(resolve({ skillOk = true, stationOk = false, materialsOk = false }), 'station_incompatible', 'C')
assertEq(resolve({}), 'ready', 'D')
assertEq(resolve({ mystery = true, skillOk = false }), 'mystery', 'E')
assertEq(resolve({ skillOk = true, levelOk = false }), 'level_required', 'level')
assertEq(resolve({ skillOk = true, levelOk = true, blueprintOk = false }), 'blueprint_required', 'blueprint')
assertEq(resolve({ stationOk = true, toolOk = false, materialsOk = false }), 'tool_required', 'tool')
print('recipe_state_spec: ok')
