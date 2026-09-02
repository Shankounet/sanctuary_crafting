--[[
    core/registry.lua — registre global resource (hooks / exports lookup)
]]

CraftingCore = CraftingCore or {}
CraftingCore.Hooks = CraftingCore.Hooks or {}

---@param name string
---@param fn function
function CraftingCore.On(name, fn)
    CraftingCore.Hooks[name] = CraftingCore.Hooks[name] or {}
    local list = CraftingCore.Hooks[name]
    list[#list + 1] = fn
end

---@param name string
---@param ... any
function CraftingCore.Emit(name, ...)
    local list = CraftingCore.Hooks[name]
    if list then
        for i = 1, #list do
            local ok, err = pcall(list[i], ...)
            if not ok then
                DebugPrint('hook error', name, err)
            end
        end
    end
    -- Public resource events (pipeline stays HTTP-unaware)
    TriggerEvent('sanctuary_crafting:' .. tostring(name), ...)
end
