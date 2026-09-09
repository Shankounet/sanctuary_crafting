--[[
    server/crafting/mystery_view.lua — player recipe visual states + secure UNKNOWN view.

    States (player-facing):
      unknown            — mystery_until_unlocked while skill locked
      discovered_locked  — real label/image, cannot craft
      unlocked           — APPRIS / craftable if other gates ok

    BuildRecipeViewForPlayer strips secrets for UNKNOWN (no true name/ings/duration/XP/output).
    Skill→recipe index: categoryUid:skillUid → recipeIds (refresh on skillUnlocked).
]]

MysteryView = MysteryView or {}

local skillRecipeIndex = {} -- ["categoryUid:skillUid"] = { recipeId, ... }
local indexBuilt = false

local VIS = {
    VISIBLE_LOCKED = 'visible_locked',
    HIDDEN = 'hidden_until_unlocked',
    MYSTERY = 'mystery_until_unlocked',
    DISCOVERED = 'discovered_locked',
}

local function cfgMystery()
    return (Config and Config.Mystery) or {}
end

function MysteryView.NormalizeVisibility(raw, recipe)
    if type(raw) == 'string' and raw ~= '' then
        local v = raw:lower()
        if v == 'mystery' then return VIS.MYSTERY end
        if v == 'hidden' then return VIS.HIDDEN end
        if v == 'discovered' then return VIS.DISCOVERED end
        return v
    end
    if recipe and recipe.hideIfSkillLocked then
        return VIS.HIDDEN
    end
    return VIS.VISIBLE_LOCKED
end

--- Default: full for mystery secrets; recipe_only for normal progression modes.
function MysteryView.ResolveMysteryMode(recipe, visibility)
    local mode = recipe and recipe.mysteryMode
    if type(mode) == 'string' and mode ~= '' then
        local m = mode:lower()
        if m == 'recipe_only' or m == 'recipe-only' or m == 'recipeonly' then
            return 'recipe_only'
        end
        return 'full'
    end
    local vis = visibility or MysteryView.NormalizeVisibility(recipe and recipe.skillVisibility, recipe)
    if vis == VIS.MYSTERY then
        return (cfgMystery().defaultModeForSecrets) or 'full'
    end
    return (cfgMystery().defaultModeForProgression) or 'recipe_only'
end

local function skillLockedFromEntry(entry, facing)
    if not entry then return false end
    if entry.lockReason == 'craft_skill_required'
        or entry.lockReason == 'skill_locked'
        or entry.lockReason == 'craft_recipe_locked'
        or entry.lockKind == 'ml_skill' then
        return true
    end
    if facing and facing.recipeLocked == true then return true end
    if entry.skillState and entry.skillState.unlocked == false
        and (entry.requiredSkill or entry.requireSkill or entry.skilltreeSkillUid) then
        return true
    end
    return false
end

local function skillUnlockedFromEntry(entry, facing)
    if facing and facing.hasRequiredSkill == true then return true end
    if entry and entry.hasRequiredSkill == true then return true end
    if entry and entry.skillState and entry.skillState.unlocked == true then return true end
    -- No skill gate → treated as unlocked for visibility
    local needs = entry and (entry.requiredSkill or entry.requireSkill or entry.skilltreeSkillUid
        or (entry.skillState and entry.skillState.skillUid))
    if not needs and facing and not facing.requireSkill then
        return true
    end
    if not needs then return true end
    return false
end

--- Resolve player visual state for a gated recipe entry.
---@return string 'unknown'|'discovered_locked'|'unlocked'
function MysteryView.ResolvePlayerState(recipe, entry, facing)
    local vis = MysteryView.NormalizeVisibility(
        (entry and entry.skillVisibility) or (facing and facing.skillVisibility) or (recipe and recipe.skillVisibility),
        recipe
    )
    local locked = skillLockedFromEntry(entry, facing)
    local unlocked = skillUnlockedFromEntry(entry, facing)

    if unlocked and not locked then
        return 'unlocked'
    end

    -- Skill gate locked (or failClosed unavailable)
    if locked or (not unlocked) then
        if vis == VIS.MYSTERY then
            return 'unknown'
        end
        if vis == VIS.DISCOVERED or vis == VIS.VISIBLE_LOCKED then
            return 'discovered_locked'
        end
        -- hidden_until_unlocked is omitted from menu; if somehow present, treat as discovered_locked
        return 'discovered_locked'
    end

    return 'unlocked'
end

function MysteryView.ShouldOmitFromMenu(recipe, entry, facing, skillsLoading)
    if skillsLoading then return false end
    local vis = MysteryView.NormalizeVisibility(
        (entry and entry.skillVisibility) or (recipe and recipe.skillVisibility),
        recipe
    )
    if vis ~= VIS.HIDDEN then return false end
    return skillLockedFromEntry(entry, facing)
end

local function categoryUidOf(recipe, entry, facing)
    if facing and facing.categoryUid then return facing.categoryUid end
    if entry and entry.skillState and entry.skillState.categoryUid then
        return entry.skillState.categoryUid
    end
    if entry and entry.skilltreeCategoryUid then return entry.skilltreeCategoryUid end
    if entry and entry.openSkillsCategory then return entry.openSkillsCategory end
    if SkillTree and SkillTree.CategoryUid and recipe then
        local g = SkillTree.RecipeGate and SkillTree.RecipeGate(recipe)
        local key = g and g.category or (recipe.requiredSkill and recipe.requiredSkill.category)
        return SkillTree.CategoryUid(key)
    end
    return nil
end

local function categoryLabelOf(recipe, entry, facing)
    if facing and facing.categoryLabel then return facing.categoryLabel end
    if entry and entry.skillCategoryLabel then return entry.skillCategoryLabel end
    if entry and entry.skillState and entry.skillState.categoryLabel then
        return entry.skillState.categoryLabel
    end
    if SkillTree and SkillTree.CategoryLabel and recipe then
        local g = SkillTree.RecipeGate and SkillTree.RecipeGate(recipe)
        return SkillTree.CategoryLabel(g and g.category)
    end
    return nil
end

--- Mutate entry in place into a secure UNKNOWN player view (no secret payload).
function MysteryView.ApplyUnknownView(entry, recipe, facing)
    if type(entry) ~= 'table' then return entry end
    local vis = MysteryView.NormalizeVisibility(
        entry.skillVisibility or (recipe and recipe.skillVisibility),
        recipe
    )
    local mode = MysteryView.ResolveMysteryMode(recipe, vis)
    local catUid = categoryUidOf(recipe, entry, facing)
    local catLabel = categoryLabelOf(recipe, entry, facing)

    entry.state = 'unknown'
    entry.playerVisualState = 'unknown'
    entry.mysteryMode = mode
    entry.displayLabel = '???'
    entry.label = '???'
    entry.displayImage = 'mystery'
    entry.canCraft = false
    entry.locked = true
    entry.missingItems = false
    entry.almostCraftable = false
    entry.almostReason = nil
    entry.canOpenSkillTree = type(catUid) == 'string' and catUid ~= ''
    entry.openSkilltree = entry.canOpenSkillTree
    entry.openSkillsCategory = catUid
    entry.skilltreeCategoryUid = catUid
    entry.skillCategoryLabel = catLabel
    entry.description = 'Cette fabrication reste inconnue.'
    entry.lockHint = 'Connaissance inconnue'
    entry.blockReason = 'Connaissance inconnue'
    entry.lockReason = entry.lockReason or 'craft_skill_required'
    entry.lockKind = 'ml_skill'

    -- Strip secrets — do NOT send true name / ings / duration / XP / output metadata
    entry.ingredients = {}
    entry.steps = nil
    entry.tools = nil
    entry.requireTool = nil
    entry.duration = nil
    entry.xp = nil
    entry.skillXp = nil
    entry.result = { item = nil, count = nil, label = '???', mystery = true }
    entry.byproducts = nil
    entry.primaryMissing = nil
    entry.missingCount = 0
    entry.maxCraftable = 0
    entry.toolDurability = nil
    entry.rarity = nil
    entry.powerCost = nil
    entry.noiseLevel = nil
    entry.heat = nil
    entry.stationLevel = nil
    entry.compareWith = nil
    entry.relatedRecipeId = nil
    entry.pathHints = nil
    entry.artisanHints = nil
    entry.blueprintMeta = nil
    entry.trueLabel = nil
    entry.trueDescription = nil
    entry.labelOverride = nil
    entry.descriptionOverride = nil

    -- skill display: FULL hides skill name; RECIPE_ONLY keeps category for SAVOIR REQUIS
    if mode == 'full' then
        entry.requiredSkillLabel = nil
        entry.skilltreeSkillLabel = nil
        entry.skilltreeSkillUid = nil -- no invented node focus; category open only
        if entry.skillState then
            entry.skillState.label = nil
            entry.skillState.skillLabel = nil
            entry.skillState.skillUid = nil
            entry.skillState.visualStatus = 'MYSTERY'
            entry.skillState.skills = nil
            entry.skillState.categoryUid = catUid
            entry.skillState.categoryLabel = catLabel
            entry.skillState.unlocked = false
        end
        entry.requiredSkill = entry.requiredSkill and {
            category = entry.requiredSkill.category,
            -- uid omitted in full mystery (no focus)
        } or nil
        entry.requireSkill = nil
    else
        -- recipe_only: show category as SAVOIR REQUIS, still no skill name/uid focus
        entry.requiredSkillLabel = catLabel and ('Savoir · %s'):format(catLabel) or 'Savoir requis'
        entry.skilltreeSkillLabel = nil
        entry.skilltreeSkillUid = nil
        if entry.skillState then
            entry.skillState.label = entry.requiredSkillLabel
            entry.skillState.skillLabel = nil
            entry.skillState.skillUid = nil
            entry.skillState.visualStatus = 'MYSTERY'
            entry.skillState.categoryUid = catUid
            entry.skillState.categoryLabel = catLabel
            entry.skillState.unlocked = false
            -- keep skills list stripped of labels/uids for security
            if type(entry.skillState.skills) == 'table' then
                local stripped = {}
                for i = 1, #entry.skillState.skills do
                    local sk = entry.skillState.skills[i]
                    stripped[i] = {
                        provider = sk.provider,
                        category = sk.category,
                        categoryLabel = sk.categoryLabel,
                        categoryUid = sk.categoryUid,
                        unlocked = false,
                        skillUid = nil,
                        skillLabel = nil,
                    }
                end
                entry.skillState.skills = stripped
            end
        end
        entry.requireSkill = nil
    end

    -- Search: only public display fields (never true names)
    local hay = { '???', 'connaissance inconnue', 'inconnue', 'mystery' }
    if mode == 'recipe_only' and catLabel then
        hay[#hay + 1] = catLabel:lower()
    end
    entry.searchHaystack = table.concat(hay, ' ')

    -- Favorites discouraged while fully unknown
    entry.favoriteAllowed = false
    entry.followLabel = 'Savoir inconnu'
    entry.knowledge = 'unknown'
    entry.adminMysteryBadge = nil -- never on player UI

    return entry
end

function MysteryView.ApplyDiscoveredLocked(entry)
    if type(entry) ~= 'table' then return entry end
    entry.state = 'discovered_locked'
    entry.playerVisualState = 'discovered_locked'
    entry.displayLabel = entry.label
    entry.canCraft = false
    entry.locked = true
    entry.favoriteAllowed = true
    entry.followLabel = entry.label
    if entry.skillState then
        entry.skillState.visualStatus = entry.skillState.visualStatus or 'LOCKED_SKILL'
    end
    return entry
end

function MysteryView.ApplyUnlocked(entry)
    if type(entry) ~= 'table' then return entry end
    entry.state = 'unlocked'
    entry.playerVisualState = 'unlocked'
    entry.displayLabel = entry.label
    entry.favoriteAllowed = true
    entry.followLabel = entry.label
    entry.mysteryMode = nil
    return entry
end

--- Apply player visual state + secure stripping. Call after full entry build.
function MysteryView.FinalizePlayerEntry(entry, recipe, facing)
    if type(entry) ~= 'table' then return entry end
    local state = MysteryView.ResolvePlayerState(recipe, entry, facing)
    entry.skillVisibility = MysteryView.NormalizeVisibility(
        entry.skillVisibility or (recipe and recipe.skillVisibility),
        recipe
    )
    if state == 'unknown' then
        return MysteryView.ApplyUnknownView(entry, recipe, facing)
    elseif state == 'discovered_locked' then
        return MysteryView.ApplyDiscoveredLocked(entry)
    end
    return MysteryView.ApplyUnlocked(entry)
end

--------------------------------------------------------------------------------
-- Skill → recipe index (categoryUid:skillUid → recipeIds)
--------------------------------------------------------------------------------

local function indexKey(categoryUid, skillUid)
    return tostring(categoryUid or '') .. ':' .. tostring(skillUid or '')
end

local function pushIndex(categoryUid, skillUid, recipeId)
    if type(skillUid) ~= 'string' or skillUid == '' then return end
    if type(recipeId) ~= 'string' or recipeId == '' then return end
    local key = indexKey(categoryUid, skillUid)
    local list = skillRecipeIndex[key]
    if not list then
        list = {}
        skillRecipeIndex[key] = list
    end
    for i = 1, #list do
        if list[i] == recipeId then return end
    end
    list[#list + 1] = recipeId
end

function MysteryView.RebuildSkillRecipeIndex()
    skillRecipeIndex = {}
    for id, recipe in pairs(Config.RecipeById or {}) do
        if type(recipe) == 'table' then
            local rid = recipe.id or id
            if CraftingSkills and CraftingSkills.normalizeSkillRequirements then
                local req = CraftingSkills.normalizeSkillRequirements(recipe, nil)
                if req and type(req.skills) == 'table' then
                    for i = 1, #req.skills do
                        local sk = req.skills[i]
                        if type(sk) == 'table' and sk.uid then
                            pushIndex(sk.categoryUid or sk.category, sk.uid, rid)
                        end
                    end
                end
            elseif SkillTree and SkillTree.RecipeGate then
                local g = SkillTree.RecipeGate(recipe)
                if g and g.requiredSkill then
                    local catUid = SkillTree.CategoryUid and SkillTree.CategoryUid(g.category) or g.category
                    pushIndex(catUid, g.requiredSkill, rid)
                end
            end
            -- also index legacy requireSkill
            if type(recipe.requireSkill) == 'string' then
                local cat = recipe.requireSkillCategory
                    or (recipe.requiredSkill and recipe.requiredSkill.category)
                    or (recipe.xp and recipe.xp.category)
                local catUid = (SkillTree and SkillTree.CategoryUid and SkillTree.CategoryUid(cat)) or cat
                pushIndex(catUid, recipe.requireSkill, rid)
            end
        end
    end
    indexBuilt = true
    return skillRecipeIndex
end

function MysteryView.RecipeIdsForSkill(categoryUid, skillUid)
    if not indexBuilt then MysteryView.RebuildSkillRecipeIndex() end
    local out = {}
    local seen = {}
    local function take(key)
        local list = skillRecipeIndex[key]
        if not list then return end
        for i = 1, #list do
            local rid = list[i]
            if not seen[rid] then
                seen[rid] = true
                out[#out + 1] = rid
            end
        end
    end
    take(indexKey(categoryUid, skillUid))
    -- also match by skillUid alone if category omitted / alias mismatch
    if type(skillUid) == 'string' and skillUid ~= '' then
        for key, list in pairs(skillRecipeIndex) do
            if key:sub(-(#skillUid + 1)) == (':' .. skillUid) then
                for i = 1, #list do
                    local rid = list[i]
                    if not seen[rid] then
                        seen[rid] = true
                        out[#out + 1] = rid
                    end
                end
            end
        end
    end
    return out
end

--- Secure public API — build player-safe recipe view.
function MysteryView.BuildRecipeViewForPlayer(src, recipe, ctx)
    if not recipe then return nil end
    local entry
    if CraftingPipeline and CraftingPipeline.BuildRecipeEntryRaw then
        entry = CraftingPipeline.BuildRecipeEntryRaw(src, recipe, ctx)
    elseif CraftingPipeline and CraftingPipeline.BuildRecipeEntry then
        -- Fallback before Raw is wired: BuildRecipeEntry already finalizes
        entry = CraftingPipeline.BuildRecipeEntry(src, recipe, ctx)
        return entry
    else
        return nil
    end
    local facing = nil
    if CraftingSkills and CraftingSkills.FacingSkill then
        facing = CraftingSkills.FacingSkill(src, recipe, ctx and ctx.skillSnap)
    end
    return MysteryView.FinalizePlayerEntry(entry, recipe, facing)
end

-- Alias expected by task brief
function BuildRecipeViewForPlayer(src, recipe, ctx)
    return MysteryView.BuildRecipeViewForPlayer(src, recipe, ctx)
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(2000)
        MysteryView.RebuildSkillRecipeIndex()
    end)
end)

return MysteryView
