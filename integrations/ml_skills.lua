--[[
    integrations/ml_skills.lua
    Seule source skill/XP/niveau — wrappers PascalCase autour de l'API ml_skills réelle.
    Soft-fail : pcall + GetResourceState. Pas de faux exports.

    API réelle ml_skills :
      AddXp(categoryUid, amount, source)
      GetPlayerLevel(categoryUid?, source)
      HasUnlockedSkill(categoryUid?, skillUid, source)
      GetTotalCategoryBonus(categoryUid, source)
]]

CraftingSkills = CraftingSkills or {}

local function resourceName()
    return (Config.Skills and Config.Skills.resource) or 'ml_skills'
end

--- Ressource ml_skills démarrée et feature activée
---@return boolean
function CraftingSkills.IsAvailable()
    if not Config.Skills or not Config.Skills.enabled then
        return false
    end
    return GetResourceState(resourceName()) == 'started'
end

---@param categoryUid string
---@param amount number
---@param source number
---@return boolean
function CraftingSkills.AddXP(categoryUid, amount, source)
    if not CraftingSkills.IsAvailable() then return false end
    if not categoryUid or not amount or amount <= 0 then return false end
    local ok, granted = pcall(function()
        return exports[resourceName()]:AddXp(categoryUid, amount, source)
    end)
    if not ok then
        DebugPrint('CraftingSkills.AddXP pcall failed:', granted)
        return false
    end
    return granted and true or false
end

---@param categoryUid string|nil
---@param source number
---@return number
function CraftingSkills.GetLevel(categoryUid, source)
    if not CraftingSkills.IsAvailable() then return 0 end
    local ok, level = pcall(function()
        return exports[resourceName()]:GetPlayerLevel(categoryUid, source)
    end)
    if not ok or type(level) ~= 'number' then return 0 end
    return level
end

---@param categoryUid string|nil
---@param requiredLevel number
---@param source number
---@return boolean
function CraftingSkills.HasRequiredLevel(categoryUid, requiredLevel, source)
    if not requiredLevel then return true end
    return CraftingSkills.GetLevel(categoryUid, source) >= requiredLevel
end

---@param categoryUid string|nil
---@param skillUid string
---@param source number
---@return boolean
function CraftingSkills.HasSkill(categoryUid, skillUid, source)
    if not CraftingSkills.IsAvailable() then return false end
    if not skillUid then return false end
    local ok, has = pcall(function()
        return exports[resourceName()]:HasUnlockedSkill(categoryUid, skillUid, source)
    end)
    if not ok then return false end
    if has then return true end
    -- fallback sans catégorie
    if categoryUid ~= nil then
        local ok2, has2 = pcall(function()
            return exports[resourceName()]:HasUnlockedSkill(nil, skillUid, source)
        end)
        if ok2 and has2 then return true end
    end
    return false
end

---@param categoryUid string
---@param source number
---@return number
function CraftingSkills.GetCategoryBonus(categoryUid, source)
    if not CraftingSkills.IsAvailable() then return 0 end
    local ok, bonus = pcall(function()
        return exports[resourceName()]:GetTotalCategoryBonus(categoryUid, source)
    end)
    if not ok or type(bonus) ~= 'number' then return 0 end
    return bonus
end

---@param recipe table
---@return string
function CraftingSkills.LevelCategoryForRecipe(recipe)
    if recipe.xp and recipe.xp.category then
        return recipe.xp.category
    end
    return (Config.Skills and Config.Skills.craftingCategory) or 'crafting'
end

--- Réduction durée craft via GetTotalCategoryBonus (plafond maxCraftTimeReduction)
---@param baseDuration number ms
---@param source number
---@return number
function CraftingSkills.ApplyCraftTimeBonus(baseDuration, source)
    if not Config.Skills or not Config.Skills.craftTimeBonus then
        return baseDuration
    end
    local cat = Config.Skills.craftingCategory or 'crafting'
    local bonus = CraftingSkills.GetCategoryBonus(cat, source)
    local maxRed = Config.Skills.maxCraftTimeReduction or 0.40
    local reduction = math.min((bonus or 0) / 100.0, maxRed)
    local duration = math.floor(baseDuration * (1.0 - reduction))
    return math.max(duration, 500)
end

--[[
    Gates serveur : si la recette exige level/skill et ml_skills est down → refuse.
    Pas de bypass silencieux.
    @return ok boolean, reason string|nil, args table|nil
]]
function CraftingSkills.CheckRecipeGates(src, recipe)
    local needsGate = (recipe.requireLevel ~= nil) or (recipe.requireSkill ~= nil)
    if not needsGate then
        return true
    end

    if not Config.Skills or not Config.Skills.enabled then
        return false, 'craft_skills_unavailable'
    end

    if not CraftingSkills.IsAvailable() then
        return false, 'craft_skills_unavailable'
    end

    local cat = CraftingSkills.LevelCategoryForRecipe(recipe)

    if recipe.requireLevel then
        if not CraftingSkills.HasRequiredLevel(cat, recipe.requireLevel, src) then
            local level = CraftingSkills.GetLevel(cat, src)
            return false, 'craft_level_required', { recipe.requireLevel, level }
        end
    end

    if recipe.requireSkill then
        if not CraftingSkills.HasSkill(cat, recipe.requireSkill, src) then
            return false, 'craft_skill_required', { recipe.requireSkill }
        end
    end

    return true
end
