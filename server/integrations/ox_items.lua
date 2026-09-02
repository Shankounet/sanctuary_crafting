--[[
    integrations/ox_items.lua
    Cache unique de exports.ox_inventory:Items().
    Source de vérité labels / descriptions. Jamais la table complète au NUI.
]]

OxItemCatalog = OxItemCatalog or {}

local EMPTY_DESC = 'Aucune description disponible.'
local cache = nil -- [name] = { label, description, image, weight }
local missingWarned = {}

local function nonempty(s)
    return type(s) == 'string' and s:match('%S') ~= nil
end

local function prettyName(name)
    if type(name) ~= 'string' or name == '' then return 'Objet' end
    local s = name:gsub('[_%-]+', ' ')
    s = (s:gsub('(%a)([%w]*)', function(a, rest)
        return a:upper() .. rest:lower()
    end))
    return s
end

local function looksLikeSpawnName(s, spawn)
    if not nonempty(s) then return true end
    if spawn and s == spawn then return true end
    return s:match('^[%l%d_]+$') ~= nil and not s:find(' ', 1, true)
end

function OxItemCatalog.Refresh()
    cache = {}
    if GetResourceState('ox_inventory') ~= 'started' then
        return
    end
    local ok, items = pcall(function()
        return exports.ox_inventory:Items()
    end)
    if not ok or type(items) ~= 'table' then
        print('[^3sanctuary_crafting^0] [CRAFT WARNING] ox_inventory:Items() indisponible')
        return
    end
    local n = 0
    for name, data in pairs(items) do
        if type(name) == 'string' and type(data) == 'table' then
            local desc = data.description
            if type(desc) ~= 'string' or desc == '' then desc = nil end
            local image = name .. '.png'
            if type(data.client) == 'table' and type(data.client.image) == 'string' and data.client.image ~= '' then
                image = data.client.image
            end
            cache[name] = {
                label = nonempty(data.label) and data.label or nil,
                description = desc,
                image = image,
                weight = data.weight,
                stack = data.stack ~= false,
            }
            n = n + 1
        end
    end
    print(('[sanctuary_crafting] ox items cache: %d'):format(n))
end

local function ensure()
    if cache == nil then
        OxItemCatalog.Refresh()
    end
    if cache == nil then
        cache = {}
    end
end

function OxItemCatalog.Get(name)
    ensure()
    if type(name) ~= 'string' then return nil end
    return cache[name]
end

--- override (labelOverride) > ox.label > fallbackLabel (si pas un spawn name) > pretty
function OxItemCatalog.Label(name, override, fallbackLabel)
    if nonempty(override) then
        return override
    end
    local data = OxItemCatalog.Get(name)
    if data and nonempty(data.label) then
        return data.label
    end
    if nonempty(fallbackLabel) and not looksLikeSpawnName(fallbackLabel, name) then
        return fallbackLabel
    end
    if name and not missingWarned[name] then
        missingWarned[name] = true
        print(('[^3sanctuary_crafting^0] [CRAFT WARNING] Item introuvable dans ox_inventory : %s'):format(tostring(name)))
    end
    return prettyName(name)
end

function OxItemCatalog.Description(name, override)
    if nonempty(override) then
        return override
    end
    local data = OxItemCatalog.Get(name)
    if data and nonempty(data.description) then
        return data.description
    end
    return EMPTY_DESC
end

function OxItemCatalog.RecipeLabel(recipe)
    if type(recipe) ~= 'table' then
        return prettyName(tostring(recipe))
    end
    local item = recipe.result and recipe.result.item
    return OxItemCatalog.Label(item, recipe.labelOverride, recipe.label)
end

function OxItemCatalog.RecipeDescription(recipe)
    if type(recipe) ~= 'table' then
        return EMPTY_DESC
    end
    local item = recipe.result and recipe.result.item
    return OxItemCatalog.Description(item, recipe.descriptionOverride)
end

function OxItemCatalog.Slim(name, extra)
    extra = extra or {}
    local data = OxItemCatalog.Get(name)
    return {
        name = name,
        label = extra.label or OxItemCatalog.Label(name, extra.override, extra.fallback),
        description = extra.description or OxItemCatalog.Description(name, extra.descriptionOverride),
        image = (data and data.image) or ((name or 'item') .. '.png'),
        weight = extra.weight or (data and data.weight) or nil,
    }
end

function OxItemCatalog.IsStackable(name)
    local data = OxItemCatalog.Get(name)
    if not data then return true end
    if data.stack == false then return false end
    return true
end

--- Dictionnaire { [item] = label } des items réellement utilisés par les recettes.
function OxItemCatalog.UsedLabels()
    ensure()
    local out = {}
    local function add(name)
        if type(name) == 'string' and name ~= '' and not out[name] then
            out[name] = OxItemCatalog.Label(name)
        end
    end
    for _, r in pairs(Config.RecipeById or {}) do
        if r.result then add(r.result.item) end
        for i = 1, #(r.ingredients or {}) do
            add(r.ingredients[i].item)
        end
        if type(r.tools) == 'table' then
            for i = 1, #r.tools do
                local t = r.tools[i]
                add(type(t) == 'table' and t.item or t)
            end
        end
        if type(r.requireTool) == 'string' then add(r.requireTool) end
        if type(r.steps) == 'table' then
            for si = 1, #r.steps do
                local ings = r.steps[si] and r.steps[si].ingredients
                if type(ings) == 'table' then
                    for i = 1, #ings do add(ings[i].item) end
                end
            end
        end
    end
    return out
end

CreateThread(function()
    local tries = 0
    while GetResourceState('ox_inventory') ~= 'started' and tries < 80 do
        Wait(250)
        tries = tries + 1
    end
    OxItemCatalog.Refresh()
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'ox_inventory' or res == GetCurrentResourceName() then
        CreateThread(function()
            Wait(400)
            OxItemCatalog.Refresh()
        end)
    end
end)
