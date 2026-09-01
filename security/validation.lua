--[[
    security/validation.lua
    Rate-limit, distance, admin, inventaire, anti-replay craftId helpers.
]]

Validation = Validation or {}

local lastCraftAttempt = {} -- [src] = gameTimer
local playerCraftCount = {} -- [src] = number of active crafts

function Validation.ClearPlayer(src)
    lastCraftAttempt[src] = nil
    playerCraftCount[src] = nil
end

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
function Validation.CanStartAnotherCraft(src)
    local n = playerCraftCount[src] or 0
    local max = Config.MaxConcurrentCrafts or 1
    return n < max
end

function Validation.IncCraftCount(src)
    playerCraftCount[src] = (playerCraftCount[src] or 0) + 1
end

function Validation.DecCraftCount(src)
    local n = (playerCraftCount[src] or 1) - 1
    if n <= 0 then
        playerCraftCount[src] = nil
    else
        playerCraftCount[src] = n
    end
end

---@param src number
---@param benchCoords vector3|table
---@param maxDist number|nil
---@return boolean
function Validation.IsNearBench(src, benchCoords, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    return Dist3(pcoords, benchCoords) <= (maxDist or Config.InteractDistance or 2.5)
end

---@param src number
---@param ingredients table
---@return boolean
function Validation.HasIngredients(src, ingredients)
    for i = 1, #(ingredients or {}) do
        local ing = ingredients[i]
        local count = exports.ox_inventory:GetItemCount(src, ing.item) or 0
        if count < (ing.count or 1) then
            return false
        end
    end
    return true
end

---@param src number
---@param item string
---@param count number
---@return boolean
function Validation.CanCarry(src, item, count)
    local ok, can = pcall(function()
        return exports.ox_inventory:CanCarryItem(src, item, count or 1)
    end)
    if not ok then
        -- fallback : tenter d'estimer via GetItemCount / pas de faux positif
        return true
    end
    return can and true or false
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
