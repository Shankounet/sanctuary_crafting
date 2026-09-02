--[[
    systems/anomaly.lua — fail-closed warnings (double-complete, bad qty, …)
    Logs to console + sanctuary_admin_logs via hook. Never grants extra items.
]]

CraftingAnomaly = CraftingAnomaly or {}

local KINDS = {
    double_complete = true,
    bad_qty = true,
    unknown_recipe = true,
    missing_ox_item = true,
    incoherent_queue = true,
    bad_timestamp = true,
    batch_over_cap = true,
    learn_bypass = true,
    forget_bypass = true,
}

function CraftingAnomaly.Warn(kind, src, extra)
    extra = extra or {}
    kind = tostring(kind or 'unknown')
    local ident = nil
    if src and GetPlayerIdentifierSafe then
        ident = GetPlayerIdentifierSafe(src)
    end
    local bits = {}
    for k, v in pairs(extra) do
        bits[#bits + 1] = ('%s=%s'):format(tostring(k), tostring(v))
    end
    table.sort(bits)
    print(('[^3sanctuary_crafting^0] [CRAFT WARNING] anomaly=%s src=%s ident=%s %s'):format(
        kind, tostring(src), tostring(ident or '-'), table.concat(bits, ' ')
    ))
    if CraftingCore and CraftingCore.Emit then
        CraftingCore.Emit('anomaly', kind, src, extra)
        if kind == 'double_complete' or kind == 'learn_bypass' or kind == 'forget_bypass'
            or kind == 'incoherent_queue' or kind == 'bad_timestamp' then
            CraftingCore.Emit('suspicious', src, kind, extra)
        end
        if kind == 'unknown_recipe' or kind == 'bad_qty' or kind == 'batch_over_cap'
            or kind == 'missing_ox_item' then
            CraftingCore.Emit('validationFail', src, kind, extra)
        end
    end
    return kind
end

function CraftingAnomaly.Known(kind)
    return KINDS[kind] == true
end
