--[[
    systems/locks.lua — short mutex on player + station around validate/consume
    Held only for the start/queue critical section, NOT the whole craft duration.
    FinalizeCraft keeps its own completing-lock.
]]

CraftLocks = CraftLocks or {}

local TTL_MS = 8000
local playerLock = {}  -- [src] = expiry (GetGameTimer)
local stationLock = {} -- [benchKey] = { src, expiry }

local function nowMs()
    return GetGameTimer()
end

function CraftLocks.Acquire(src, benchKey)
    local now = nowMs()
    local pExp = playerLock[src]
    if pExp and pExp > now then
        return false, 'craft_busy'
    end
    if type(benchKey) == 'string' and benchKey ~= '' then
        local s = stationLock[benchKey]
        if s and s.expiry > now and s.src ~= src then
            return false, 'craft_busy'
        end
        stationLock[benchKey] = { src = src, expiry = now + TTL_MS }
    end
    playerLock[src] = now + TTL_MS
    return true
end

function CraftLocks.Release(src, benchKey)
    playerLock[src] = nil
    if type(benchKey) == 'string' and stationLock[benchKey] then
        if stationLock[benchKey].src == src then
            stationLock[benchKey] = nil
        end
    end
end

function CraftLocks.IsHeld(src)
    local exp = playerLock[src]
    return exp and exp > nowMs()
end

AddEventHandler('playerDropped', function()
    local src = source
    playerLock[src] = nil
    for key, s in pairs(stationLock) do
        if s and s.src == src then
            stationLock[key] = nil
        end
    end
end)
