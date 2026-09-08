--[[
    integrations/crafting_skills.lua
    Compatibility facade → Skills (server/integrations/ml_skills.lua).

    ml_skills is the SOLE unlock / XP / level provider.
    sanctuary_skilltree and DevHub are NOT used for recipe unlock checks.
]]

CraftingSkills = CraftingSkills or {}

function CraftingSkills.ShouldBypassRequirements(src)
    return Skills.ShouldBypassRequirements(src)
end

function CraftingSkills.NotifyBypassIfNeeded(src)
    return Skills.NotifyBypassIfNeeded(src)
end

function CraftingSkills.Provider()
    return Skills.Provider()
end

function CraftingSkills.IsAvailable()
    return Skills.IsAvailable()
end

function CraftingSkills.SkillLabel(skillUid, catKey)
    return Skills.SkillLabel(skillUid, catKey)
end

function CraftingSkills.CategoryLabel(catKey)
    return Skills.CategoryLabel(catKey)
end

function CraftingSkills.Invalidate(src)
    return Skills.Invalidate(src)
end

function CraftingSkills.Load(src)
    return Skills.RebuildCache(src)
end

function CraftingSkills.Snapshot(src, force)
    return Skills.Snapshot(src, force)
end

function CraftingSkills.LevelCategoryForRecipe(recipe)
    return Skills.LevelCategoryForRecipe(recipe)
end

function CraftingSkills.GetLevel(src, catKey)
    return Skills.GetLevel(src, catKey)
end

function CraftingSkills.GetXp(_src, _catKey)
    return 0
end

function CraftingSkills.GetTotalXp(_src, _catKey)
    return 0
end

function CraftingSkills.HasRequiredLevel(src, catKey, requiredLevel)
    if not requiredLevel then return true end
    if Skills.ShouldBypassRequirements(src) then return true end
    return Skills.GetLevel(src, catKey) >= requiredLevel
end

function CraftingSkills.HasSkill(src, catKey, skillUid)
    return Skills.HasUnlockedSkill(src, catKey, skillUid)
end

function CraftingSkills.GetCategoryBonus(_catKey, _src)
    return 0
end

function CraftingSkills.ApplyCraftTimeBonus(baseDuration, _src)
    return baseDuration
end

--- SERVER ONLY. amount from recipe.xp / Config — never from NUI / client.
function CraftingSkills.AddCraftXp(src, catKey, amount)
    return Skills.AddXp(src, catKey, amount)
end

--- Recipe unlocks: ml_skills only (no SST hasUnlockedRecipe / DevHub).
function CraftingSkills.HasUnlockedRecipe(_src, _recipeId)
    return true
end

function CraftingSkills.CanAccessRecipe(_src, _recipeId)
    return true
end

function CraftingSkills.GetSkillForRecipe(_recipeId)
    return nil
end

function CraftingSkills.CheckRecipeGates(src, recipe)
    return Skills.CheckRecipeRequirement(src, recipe)
end

function CraftingSkills.FacingSkill(src, recipe, snap)
    return Skills.FacingSkill(src, recipe, snap)
end

function CraftingSkills.ParseRecipeRequirement(recipe)
    return Skills.ParseRecipeRequirement(recipe)
end

function CraftingSkills.normalizeSkillRequirements(recipe, src)
    return Skills.normalizeSkillRequirements(recipe, src)
end

function CraftingSkills.HealthReport()
    return Skills.HealthReport()
end

lib.callback.register('sanctuary_crafting:skillSnapshot', function(src)
    local snap = CraftingSkills.Snapshot(src)
    local cats = {}
    for key, cat in pairs(snap.categories or {}) do
        cats[key] = {
            key = key,
            label = cat.label,
            level = cat.level,
            xp = cat.xp,
            totalXp = cat.totalXp,
        }
    end
    local talents = {}
    for i = 1, #(snap.unlocked or {}) do
        local u = snap.unlocked[i]
        if u.label then
            talents[#talents + 1] = { label = u.label, category = u.categoryKey }
        end
    end
    return {
        ok = true,
        available = snap.available == true,
        loading = snap.loading == true,
        provider = 'ml_skills',
        categories = cats,
        talents = talents,
    }
end)

lib.callback.register('sanctuary_crafting:mlSkillTrees', function(src)
    if not Validation or not Validation.IsAdmin or not Validation.IsAdmin(src) then
        return { ok = false }
    end
    local trees = Skills.GetSkillTrees()
    return { ok = true, trees = trees, refreshed = Skills.RefreshLabels() }
end)
