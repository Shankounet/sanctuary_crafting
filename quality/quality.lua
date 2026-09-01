--[[
    quality/quality.lua — helpers qualité + metadata craftedBy
]]

Quality = Quality or {}

function Quality.Enabled()
    return Config.Quality and Config.Quality.Enabled
end

function Quality.Tiers()
    return (Config.Quality and Config.Quality.Tiers) or { 'poor', 'normal', 'good', 'excellent', 'masterwork' }
end

---@param quality string
---@return number index 1-based
function Quality.Index(quality)
    local tiers = Quality.Tiers()
    for i = 1, #tiers do
        if tiers[i] == quality then return i end
    end
    return 2
end

exports('GetItemQuality', function(metadata)
    if not metadata then return nil end
    return metadata.quality
end)
