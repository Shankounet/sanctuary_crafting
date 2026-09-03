--[[
    systems/follow.lua — notify when a FOLLOWED/pinned recipe becomes faisable
    RAM last-seen craftable set. Sparse: no SQL. Uses ox labels.
]]

FollowNotify = FollowNotify or {}

local lastCraftable = {} -- [src] = { [recipeId] = true }
local lastScan = {} -- [src] = GetGameTimer()

local function enabled()
    return Config.Follow and Config.Follow.NotifyWhenCraftable ~= false
end

local function pinIds(src)
    local ids = {}
    if not SurvivalBook or not SurvivalBook.ListPins then return ids end
    local pins = SurvivalBook.ListPins(src) or {}
    for i = 1, #pins do
        local pin = pins[i]
        local rid = pin.recipeId or pin
        if type(rid) == 'string' and rid ~= '' and not (pin.kind == 'resource') then
            if rid:sub(1, 4) ~= 'res:' then
                ids[#ids + 1] = rid
            end
        end
    end
    return ids
end

local function recipeIsCraftable(src, recipe)
    if not recipe then return false end
    if CraftingPipeline and CraftingPipeline.BuildRecipeEntry then
        local entry = CraftingPipeline.BuildRecipeEntry(src, recipe, { includeHints = false })
        return entry and entry.canCraft == true
    end
    local ings = recipe.ingredients or {}
    if Validation and Validation.HasIngredients and not Validation.HasIngredients(src, ings) then
        return false
    end
    if CraftingSkills and CraftingSkills.CheckRecipeGates then
        local ok = CraftingSkills.CheckRecipeGates(src, recipe)
        if not ok then return false end
    end
    return true
end

function FollowNotify.Scan(src)
    if not enabled() then return end
    if not src or src < 1 then return end
    local now = GetGameTimer()
    if lastScan[src] and (now - lastScan[src]) < 750 then return end
    lastScan[src] = now

    local prev = lastCraftable[src] or {}
    local nextSet = {}
    local ids = pinIds(src)
    for i = 1, #ids do
        local rid = ids[i]
        local recipe = Config.RecipeById and Config.RecipeById[rid]
        if recipe then
            local can = recipeIsCraftable(src, recipe)
            nextSet[rid] = can or nil
            if can and not prev[rid] then
                local label = (OxItemCatalog and OxItemCatalog.RecipeLabel and OxItemCatalog.RecipeLabel(recipe))
                    or recipe.label
                    or rid
                TriggerClientEvent('ox_lib:notify', src, {
                    type = 'success',
                    description = _('craft_now_craftable', label),
                })
            end
        end
    end
    lastCraftable[src] = nextSet
end

AddEventHandler('playerDropped', function()
    local src = source
    lastCraftable[src] = nil
    lastScan[src] = nil
end)

RegisterNetEvent('sanctuary_crafting:server:invChanged', function()
    local src = source
    FollowNotify.Scan(src)
end)

if CraftingCore and CraftingCore.On then
    CraftingCore.On('craftCompleted', function(src)
        if src then FollowNotify.Scan(src) end
    end)
    CraftingCore.On('queueCollected', function(src)
        if src then FollowNotify.Scan(src) end
    end)
end
