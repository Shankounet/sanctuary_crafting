--[[
    systems/specializations.lua — spec principale (SQL > job ESX > survie)
    Identité ≠ niveau skill tree. BypassRequirements ne saute PAS ces gates.
]]

Specializations = Specializations or {}

local cache = {} -- [identifier] = spec_id|false (false = loaded empty)

local function cfg()
    return Config.Specializations or {}
end

local function ident(src)
    return GetPlayerIdentifierSafe(src)
end

function Specializations.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_player_spec` (
            `identifier` VARCHAR(60) NOT NULL,
            `spec_id` VARCHAR(32) NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

local function mainDef(specId)
    local main = cfg().Main or {}
    return specId and main[specId] or nil
end

local function isSurvivalStation(station)
    if not station then return false end
    for _, s in ipairs(cfg().SurvivalStations or {}) do
        if s == station then return true end
    end
    return false
end

local function exclusiveOwner(station)
    if not station then return nil end
    local main = cfg().Main or {}
    for specId, def in pairs(main) do
        for _, st in ipairs(def.stations or {}) do
            if st == station then return specId end
        end
    end
    return nil
end

local function jobNameOf(src)
    if not ESX or not ESX.GetPlayerFromId then return nil end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local job = xPlayer.job
    if type(job) == "table" then return job.name end
    if xPlayer.getJob then
        local j = xPlayer.getJob()
        return j and j.name or nil
    end
    return nil
end

local function specFromJob(src)
    local job = jobNameOf(src)
    if not job then return nil end
    local map = cfg().FromJob or {}
    return map[job]
end

function Specializations.Get(src)
    local id = ident(src)
    if not id then return nil end
    if cache[id] == nil then
        local row = MySQL.single.await("SELECT spec_id FROM sanctuary_player_spec WHERE identifier = ?", { id })
        cache[id] = (row and row.spec_id) or false
    end
    if cache[id] == false then return nil end
    return cache[id]
end

function Specializations.Set(src, specId)
    local id = ident(src)
    if not id then return false, "craft_invalid" end
    local survivalId = cfg().SurvivalId or "survie"
    if specId == nil or specId == "" or specId == "clear" or specId == survivalId then
        MySQL.query.await("DELETE FROM sanctuary_player_spec WHERE identifier = ?", { id })
        cache[id] = false
        return true
    end
    if not mainDef(specId) then return false, "craft_invalid" end
    MySQL.query.await([[
        INSERT INTO sanctuary_player_spec (identifier, spec_id) VALUES (?,?)
        ON DUPLICATE KEY UPDATE spec_id = VALUES(spec_id)
    ]], { id, specId })
    cache[id] = specId
    return true
end

--- SQL override else FromJob else survival-only
function Specializations.Resolve(src)
    local c = cfg()
    local survivalId = c.SurvivalId or "survie"
    local survivalLabel = c.SurvivalLabel or "Survie"
    local specId, source = nil, "survival"
    local sqlId = Specializations.Get(src)
    if sqlId and mainDef(sqlId) then
        specId, source = sqlId, "sql"
    else
        local fromJob = specFromJob(src)
        if fromJob and mainDef(fromJob) then
            specId, source = fromJob, "job"
        end
    end

    local skills = {
        { id = survivalId, label = survivalLabel },
    }
    local label = survivalLabel
    if specId then
        local def = mainDef(specId)
        label = def.label or specId
        if def.skillCategory then
            skills[#skills + 1] = { id = def.skillCategory, label = def.label or specId }
        end
    end
    return {
        id = specId or survivalId,
        mainId = specId,
        label = label,
        source = source,
        skills = skills,
        survival = true,
    }
end

function Specializations.Describe(src)
    return Specializations.Resolve(src)
end

function Specializations.CanUseStation(src, stationCategory)
    if cfg().Enabled == false then return true end
    local station = stationCategory
    if type(station) == "table" then
        station = station.category or station.station
    end
    if not station then return true end
    if isSurvivalStation(station) then return true end
    local owner = exclusiveOwner(station)
    if not owner then return true end
    local resolved = Specializations.Resolve(src)
    if resolved.mainId == owner then return true end
    local def = mainDef(owner)
    return false, "craft_spec_required", { (def and def.label) or owner }
end

function Specializations.InferRequireSpec(recipe)
    if not recipe then return nil end
    if type(recipe.requireSpec) == "string" and recipe.requireSpec ~= "" then
        return recipe.requireSpec
    end
    local station = recipe.station or recipe.category
    if isSurvivalStation(station) then
        return cfg().SurvivalId or "survie"
    end
    return exclusiveOwner(station)
end

function Specializations.CanCraftRecipe(src, recipe)
    if cfg().Enabled == false then return true end
    if not recipe then return false, "craft_invalid" end
    local req = Specializations.InferRequireSpec(recipe)
    local survivalId = cfg().SurvivalId or "survie"
    if not req or req == survivalId then
        return true
    end
    if not mainDef(req) then
        return true
    end
    local resolved = Specializations.Resolve(src)
    if resolved.mainId == req then return true end
    local def = mainDef(req)
    return false, "craft_spec_required", { (def and def.label) or req, resolved.label }
end

function Specializations.HasMain(src, specId)
    local resolved = Specializations.Resolve(src)
    return resolved.mainId == specId
end

CreateThread(function()
    MySQL.ready.await()
    Specializations.EnsureTable()
end)

AddEventHandler("esx:playerLoaded", function(playerId)
    local src = type(playerId) == "number" and playerId or source
    if src then Specializations.Get(src) end
end)

AddEventHandler("playerDropped", function()
    local id = ident(source)
    if id then cache[id] = nil end
end)

local function isStaff(src)
    if src == 0 then return true end
    if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then return true end
    if IsPlayerAceAllowed(src, "command.crafting:setspec") then return true end
    return false
end

RegisterCommand("crafting:setspec", function(src, args)
    if not isStaff(src) then
        if src > 0 then
            TriggerClientEvent("ox_lib:notify", src, { type = "error", description = _("admin_denied") })
        end
        return
    end
    local target, specId
    if src == 0 then
        target = tonumber(args[1])
        specId = args[2]
    elseif args[2] then
        target = tonumber(args[1]) or src
        specId = args[2]
    else
        target = src
        specId = args[1]
    end
    if not target or not specId then
        local usage = "crafting:setspec [id] [spec] — spec: medecin|ingenieur|mecano|armurier|survie"
        if src == 0 then print(usage) else
            TriggerClientEvent("ox_lib:notify", src, { type = "inform", description = usage })
        end
        return
    end
    local ok, err = Specializations.Set(target, specId)
    if src == 0 then
        print(ok and ("spec=" .. tostring(specId) .. " src=" .. tostring(target)) or tostring(err))
        return
    end
    TriggerClientEvent("ox_lib:notify", src, {
        type = ok and "success" or "error",
        description = ok and _("spec_set_ok", specId) or _(err or "craft_invalid"),
    })
    if ok and target ~= src then
        TriggerClientEvent("ox_lib:notify", target, { type = "inform", description = _("spec_assigned", specId) })
    end
end, false)
