--[[
    integrations/permissions.lua
    Bridge permissions stations : public / owner / admin / ACE optionnel
]]

CraftingPermissions = CraftingPermissions or {}

---@param src number
---@param station table
---@return boolean, string|nil
function CraftingPermissions.CanUseStation(src, station)
    if not station then return false, 'craft_invalid' end

    -- ACL optionnelle par catégorie
    local ace = Config.StationAce and Config.StationAce[station.category]
    if ace and not IsPlayerAceAllowed(src, ace) then
        return false, 'craft_denied'
    end

    if station.kind == 'world' then
        return true
    end

    if station.kind == 'placed' then
        -- public craft by default; set Config.Place.requireOwnerToCraft = true to lock
        if Config.Place and Config.Place.requireOwnerToCraft then
            local id = GetPlayerIdentifierSafe(src)
            if id == station.owner then return true end
            if Validation and Validation.IsAdmin and Validation.IsAdmin(src) then return true end
            return false, 'craft_denied'
        end
        return true
    end

    return true
end

---@param src number
---@param station table
---@param identifier string|nil
---@return boolean
function CraftingPermissions.CanPickupStation(src, station, identifier)
    if not station or station.kind ~= 'placed' then return false end
    local isOwner = Config.Place.allowPickupOwner and identifier and identifier == station.owner
    if isOwner then return true end
    if Config.Place.allowPickupAdmin and Validation and Validation.IsAdmin and Validation.IsAdmin(src) then
        return true
    end
    return false
end

---@param src number
---@param station table
---@return boolean
function CraftingPermissions.CanUpgradeStation(src, station)
    if not station or station.kind ~= 'placed' then return false end
    local id = GetPlayerIdentifierSafe(src)
    if id == station.owner then return true end
    return Validation.IsAdmin(src)
end
