--[[
    recipes/snapshot.lua — freeze the MINIMUM recipe fields at craft/queue start
    Finalize and collect MUST use this snapshot, never live Config.RecipeById.

    Slim shape (v2.17+): id, _version, result, ingredients, duration, xp,
    tools/requireTool, blueprint gates, min identity/skill fields used at
    finalize/collect, quality/signature/byproducts if granted from snapshot,
    slim steps (ingredients+duration only — no UI labels).

    Fat blobs from older queue rows still decode and collect.
]]

RecipeSnapshot = RecipeSnapshot or {}

local function isArray(t)
    if type(t) ~= 'table' then return false end
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    return true
end

local function clone(v, seen)
    local tv = type(v)
    if tv ~= 'table' then
        if tv == 'function' or tv == 'userdata' or tv == 'thread' then
            return nil
        end
        return v
    end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    if isArray(v) then
        for i = 1, #v do
            out[i] = clone(v[i], seen)
        end
    else
        for k, val in pairs(v) do
            if type(k) == 'string' and k:sub(1, 1) == '_' then
                if k == '_version' or k == '_updatedAt' or k == '_updatedBy' or k == '_overlay' then
                    out[k] = clone(val, seen)
                end
            else
                local ck = clone(k, seen)
                if ck ~= nil then
                    out[ck] = clone(val, seen)
                end
            end
        end
    end
    return out
end

local function slimIngredients(ings)
    local out = {}
    if type(ings) ~= 'table' then return out end
    for i = 1, #ings do
        local ing = ings[i]
        if type(ing) == 'table' and ing.item then
            out[#out + 1] = { item = ing.item, count = ing.count or 1 }
        end
    end
    return out
end

local function slimTools(tools)
    if type(tools) ~= 'table' then return nil end
    local out = {}
    for i = 1, #tools do
        local t = tools[i]
        if type(t) == 'string' then
            out[#out + 1] = { item = t, consume = false, durabilityCost = 1 }
        elseif type(t) == 'table' and t.item then
            out[#out + 1] = {
                item = t.item,
                count = t.count,
                consume = t.consume,
                durabilityCost = t.durabilityCost,
            }
        end
    end
    return out
end

function RecipeSnapshot.Clone(recipe)
    if type(recipe) ~= 'table' then return nil end
    return clone(recipe)
end

--- Persist only fields required so an in-flight craft cannot change after a recipe update.
--- Dropped: label, description, image, category, rarity, steps UI, heat def, noise, powerCost.
function RecipeSnapshot.Capture(recipe)
    if type(recipe) ~= 'table' then return nil, 0 end
    local version = tonumber(recipe._version) or 0
    local snap = {
        id = recipe.id,
        _version = version,
        duration = recipe.duration,
        ingredients = slimIngredients(recipe.ingredients),
    }
    if type(recipe.result) == 'table' and recipe.result.item then
        snap.result = { item = recipe.result.item, count = recipe.result.count or 1 }
    end
    if type(recipe.xp) == 'table' and recipe.xp.category then
        snap.xp = { category = recipe.xp.category, amount = recipe.xp.amount or 0 }
    end
    local tools = slimTools(recipe.tools)
    if tools and #tools > 0 then
        snap.tools = tools
    end
    if type(recipe.requireTool) == 'table' and recipe.requireTool.item then
        snap.requireTool = {
            item = recipe.requireTool.item,
            durabilityCost = recipe.requireTool.durabilityCost,
            consume = recipe.requireTool.consume,
        }
    elseif type(recipe.requireTool) == 'string' then
        snap.requireTool = { item = recipe.requireTool, durabilityCost = 1 }
    end
    -- identity / knowledge at collect + finalize (CheckIdentityGates, KnowsRecipe)
    if recipe.blueprintId then snap.blueprintId = recipe.blueprintId end
    if recipe.requireBlueprint then snap.requireBlueprint = recipe.requireBlueprint end
    if recipe.requiresLearn then snap.requiresLearn = true end
    if recipe.requireSpec then snap.requireSpec = recipe.requireSpec end
    -- finalize re-checks skill gates FROM the snapshot (not live Config)
    if recipe.requireLevel then snap.requireLevel = recipe.requireLevel end
    if recipe.requireSkill then snap.requireSkill = recipe.requireSkill end
    -- collect/finalize grant
    if recipe.quality then snap.quality = recipe.quality end
    if recipe.signatureMode then snap.signatureMode = recipe.signatureMode end
    if recipe.trackCrafter ~= nil then snap.trackCrafter = recipe.trackCrafter end
    if recipe.trackLot ~= nil then snap.trackLot = recipe.trackLot end
    if type(recipe.byproducts) == 'table' then
        snap.byproducts = clone(recipe.byproducts)
    end
    -- multi-step: keep ingredients+duration only (no UI labels)
    if type(recipe.steps) == 'table' and #recipe.steps > 0 then
        snap.steps = {}
        for i = 1, #recipe.steps do
            local st = recipe.steps[i]
            snap.steps[i] = {
                ingredients = slimIngredients(st and st.ingredients),
                duration = st and st.duration,
            }
        end
    end
    return snap, version
end

function RecipeSnapshot.Encode(snap)
    if type(snap) ~= 'table' then return nil end
    local ok, encoded = pcall(json.encode, snap)
    if not ok or type(encoded) ~= 'string' then return nil end
    return encoded
end

function RecipeSnapshot.Decode(encoded)
    if type(encoded) ~= 'string' or encoded == '' then return nil end
    local ok, decoded = pcall(json.decode, encoded)
    if not ok or type(decoded) ~= 'table' then return nil end
    return decoded
end

function RecipeSnapshot.Of(craft)
    if type(craft) ~= 'table' then return nil end
    if type(craft.snapshot) == 'table' then
        return craft.snapshot
    end
    if type(craft.recipeSnapshot) == 'table' then
        return craft.recipeSnapshot
    end
    return nil
end

--- In-memory label for NUI/notify. Never persisted. Works for slim and fat snaps.
function RecipeSnapshot.FacingLabel(snap)
    if type(snap) ~= 'table' then return nil end
    if type(snap.label) == 'string' and snap.label ~= '' then return snap.label end
    if OxItemCatalog and OxItemCatalog.RecipeLabel then
        local lab = OxItemCatalog.RecipeLabel(snap)
        if lab then return lab end
    end
    if snap.result and snap.result.item then
        if OxItemCatalog and OxItemCatalog.Label then
            return OxItemCatalog.Label(snap.result.item)
        end
        return snap.result.item
    end
    return snap.id
end
