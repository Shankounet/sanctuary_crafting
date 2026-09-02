--[[
    recipes/snapshot.lua — freeze recipe+version at craft/queue start
    Finalize and collect MUST use this snapshot, never live Config.RecipeById.
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

function RecipeSnapshot.Clone(recipe)
    if type(recipe) ~= 'table' then return nil end
    return clone(recipe)
end

function RecipeSnapshot.Capture(recipe)
    if type(recipe) ~= 'table' then return nil, 0 end
    local snap = clone(recipe)
    local version = tonumber(recipe._version) or 0
    if snap then
        snap._version = version
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
