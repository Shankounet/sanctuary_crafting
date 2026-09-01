--[[
    integrations/power.lua
    Si Config.Power.Enabled == false → toujours true.

    Ordre de résolution (Enabled=true) :
      1. Pont externe Config.Power.ExternalBridge (export ou event) — si configuré
      2. Fallback local : station.modules contient 'power_cell' ou 'generator'
      3. Bancs monde : powered ~= false par défaut

    Pont externe (au choix, premier non-nil gagne) :
      Config.Power.ExternalBridge = {
          -- Export d'une autre ressource : exports[resource][export](station, recipe?) → boolean
          resource = 'my_power_grid',
          export   = 'HasStationPower',
          -- OU event serveur synchrone via export wrapper (préférer export)
          -- event = 'my_power:hasPower',  -- non bloquant ; préférer export
      }
]]

CraftingPower = CraftingPower or {}

---@param station table|nil
---@param recipe table|nil
---@return boolean|nil  nil = bridge not configured / soft-fail → fallback
local function queryExternalBridge(station, recipe)
    local cfg = Config.Power and Config.Power.ExternalBridge
    if not cfg or type(cfg) ~= 'table' then return nil end

    local resource = cfg.resource
    local exportName = cfg.export
    if type(resource) == 'string' and resource ~= '' and type(exportName) == 'string' and exportName ~= '' then
        if GetResourceState(resource) ~= 'started' then
            DebugPrint('CraftingPower bridge resource down:', resource)
            return nil
        end
        local ok, result = pcall(function()
            return exports[resource][exportName](station, recipe)
        end)
        if not ok then
            DebugPrint('CraftingPower bridge export error:', result)
            return nil
        end
        if type(result) == 'boolean' then return result end
        return result and true or false
    end

    -- Optional: custom function hook registered at runtime
    if type(cfg.fn) == 'function' then
        local ok, result = pcall(cfg.fn, station, recipe)
        if ok and type(result) == 'boolean' then return result end
        if ok then return result and true or false end
        DebugPrint('CraftingPower bridge fn error:', result)
        return nil
    end

    return nil
end

---@param station table|nil
---@return boolean
local function localPowerFallback(station)
    if not station then return false end
    if station.kind == 'world' then
        return station.powered ~= false
    end
    local mods = station.modules or {}
    local required = (Config.Power and Config.Power.FallbackModules)
        or { 'power_cell', 'generator' }
    for i = 1, #mods do
        for j = 1, #required do
            if mods[i] == required[j] then
                return true
            end
        end
    end
    return false
end

---@param station table|nil
---@param recipe table|nil
---@return boolean
function CraftingPower.HasPower(station, recipe)
    if not Config.Power or not Config.Power.Enabled then
        return true
    end
    if not station then return false end

    local bridged = queryExternalBridge(station, recipe)
    if bridged ~= nil then
        return bridged
    end

    -- Keep power_cell / generator module fallback when bridge absent or soft-failed
    return localPowerFallback(station)
end

---@param station table
---@param recipe table
---@return boolean
function CraftingPower.CanRunRecipe(station, recipe)
    if not recipe then return CraftingPower.HasPower(station) end
    if not recipe.powerCost or recipe.powerCost <= 0 then
        return true
    end
    return CraftingPower.HasPower(station, recipe)
end

--- Register a runtime bridge function (from another resource via export).
---@param fn function
function CraftingPower.SetExternalBridge(fn)
    Config.Power = Config.Power or {}
    Config.Power.ExternalBridge = Config.Power.ExternalBridge or {}
    Config.Power.ExternalBridge.fn = fn
end

exports('SetPowerBridge', function(fn)
    CraftingPower.SetExternalBridge(fn)
end)

exports('HasStationPower', function(station, recipe)
    return CraftingPower.HasPower(station, recipe)
end)
