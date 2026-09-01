Validation = Validation or {}

local lastCraftAttempt = {} -- [src] = GetGameTimer()
local activeCrafts = {}     -- [src] = { recipeId, benchKey, startedAt, duration }

function Validation.ClearPlayer(src)
    lastCraftAttempt[src] = nil
    activeCrafts[src] = nil
end

AddEventHandler('playerDropped', function()
    Validation.ClearPlayer(source)
end)

---@param src number
---@return boolean, string|nil
function Validation.CheckRateLimit(src)
    local now = GetGameTimer()
    local last = lastCraftAttempt[src] or 0
    if now - last < (Config.RateLimitMs or 1500) then
        return false, 'craft_rate_limited'
    end
    lastCraftAttempt[src] = now
    return true
end

---@param src number
---@return boolean
function Validation.IsCrafting(src)
    return activeCrafts[src] ~= nil
end

function Validation.GetActive(src)
    return activeCrafts[src]
end

function Validation.SetActive(src, data)
    activeCrafts[src] = data
end

function Validation.ClearActive(src)
    activeCrafts[src] = nil
end

---@param src number
---@param benchCoords vector3|table
---@param maxDist number|nil
---@return boolean
function Validation.IsNearBench(src, benchCoords, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    local dist = Dist3(pcoords, benchCoords)
    return dist <= (maxDist or Config.InteractDistance or 2.5)
end

---@param src number
---@param recipe table
---@return boolean, string|nil, any
function Validation.CheckSkillGates(src, recipe)
    if not Config.Skills or not Config.Skills.enabled then
        return true
    end
    -- Soft-fail : si ml_skills absent, on n'applique pas les gates (ou on bloque ?)
    -- Spec: soft-fail exports ; gates only meaningful when resource started
    if GetResourceState(Config.Skills.resource or 'ml_skills') ~= 'started' then
        return true
    end

    if recipe.requireLevel then
        local cat = Skills.LevelCategoryForRecipe(recipe)
        local level = Skills.GetPlayerLevel(cat, src)
        if level < recipe.requireLevel then
            return false, 'craft_level_required', { recipe.requireLevel, level }
        end
    end

    if recipe.requireSkill then
        local cat = Skills.LevelCategoryForRecipe(recipe)
        if not Skills.HasUnlockedSkill(cat, recipe.requireSkill, src) then
            -- fallback scan sans catégorie
            if not Skills.HasUnlockedSkill(nil, recipe.requireSkill, src) then
                return false, 'craft_skill_required', { recipe.requireSkill }
            end
        end
    end

    return true
end

---@param src number
---@param ingredients table
---@return boolean
function Validation.HasIngredients(src, ingredients)
    for i = 1, #ingredients do
        local ing = ingredients[i]
        local count = exports.ox_inventory:GetItemCount(src, ing.item) or 0
        if count < ing.count then
            return false
        end
    end
    return true
end

---@param src number
---@return boolean
function Validation.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.AdminAce or 'sanctuary.crafting.admin') then
        return true
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local group = xPlayer.getGroup and xPlayer.getGroup() or xPlayer.group
    if not group then return false end
    for i = 1, #(Config.AdminGroups or {}) do
        if Config.AdminGroups[i] == group then
            return true
        end
    end
    return false
end
