--[[
    Bridge ml_skills — soft-fail si la ressource n'est pas démarrée.
    Exports PascalCase, category first, source last.
]]

Skills = Skills or {}

local function resourceOk()
    if not Config.Skills or not Config.Skills.enabled then
        return false
    end
    local name = Config.Skills.resource or 'ml_skills'
    return GetResourceState(name) == 'started'
end

---@param categoryUid string
---@param amount number
---@param source number
---@return boolean
function Skills.AddXp(categoryUid, amount, source)
    if not resourceOk() then return false end
    if not categoryUid or not amount or amount <= 0 then return false end
    local ok, granted = pcall(function()
        return exports.ml_skills:AddXp(categoryUid, amount, source)
    end)
    if not ok then
        DebugPrint('AddXp pcall failed:', granted)
        return false
    end
    return granted and true or false
end

---@param categoryUid string|nil
---@param source number
---@return number
function Skills.GetPlayerLevel(categoryUid, source)
    if not resourceOk() then return 0 end
    local ok, level = pcall(function()
        return exports.ml_skills:GetPlayerLevel(categoryUid, source)
    end)
    if not ok or type(level) ~= 'number' then return 0 end
    return level
end

---@param categoryUid string|nil
---@param skillUid string
---@param source number
---@return boolean
function Skills.HasUnlockedSkill(categoryUid, skillUid, source)
    if not resourceOk() then return false end
    if not skillUid then return false end
    local ok, has = pcall(function()
        return exports.ml_skills:HasUnlockedSkill(categoryUid, skillUid, source)
    end)
    if not ok then return false end
    return has and true or false
end

---@param categoryUid string
---@param source number
---@return number
function Skills.GetTotalCategoryBonus(categoryUid, source)
    if not resourceOk() then return 0 end
    local ok, bonus = pcall(function()
        return exports.ml_skills:GetTotalCategoryBonus(categoryUid, source)
    end)
    if not ok or type(bonus) ~= 'number' then return 0 end
    return bonus
end

--- Réduit la durée de craft selon le bonus catégorie crafting
---@param baseDuration number ms
---@param source number
---@return number
function Skills.ApplyCraftTimeBonus(baseDuration, source)
    if not Config.Skills.craftTimeBonus then
        return baseDuration
    end
    local cat = Config.Skills.craftingCategory or 'crafting'
    local bonus = Skills.GetTotalCategoryBonus(cat, source)
    local maxRed = Config.Skills.maxCraftTimeReduction or 0.40
    local reduction = math.min((bonus or 0) / 100.0, maxRed)
    local duration = math.floor(baseDuration * (1.0 - reduction))
    return math.max(duration, 500)
end

--- Niveau à vérifier pour une recette (catégorie XP de la recette ou crafting)
---@param recipe table
---@return string
function Skills.LevelCategoryForRecipe(recipe)
    if recipe.xp and recipe.xp.category then
        return recipe.xp.category
    end
    return Config.Skills.craftingCategory or 'crafting'
end
