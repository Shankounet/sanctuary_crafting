#!/usr/bin/env lua
-- Minimal stub so normalizeSkillRequirements can run without FiveM.
package.path = package.path .. ';./?.lua;./?/init.lua'

Config = {
    SkillCategories = {
        survival = { categoryUid = 'survie', label = 'Survie' },
        medic = { categoryUid = 'medecin', label = 'Médecin' },
        engineer = { categoryUid = 'ingenieur', label = 'Ingénieur' },
        gunsmith = { categoryUid = 'armurier', label = 'Armurier' },
    },
    SkillLegacyMap = { survie = 'survival', medecin = 'medic' },
    SkillIntegration = { provider = 'ml_skills', debug = false },
    Skills = { defaultCategory = 'survival', resource = 'ml_skills' },
    Debug = false,
}

SkillTree = {}
function SkillTree.ResolveKey(raw)
    if type(raw) ~= 'string' then return nil end
    if Config.SkillCategories[raw] then return raw end
    local legacy = Config.SkillLegacyMap[raw]
    if legacy then return legacy end
    for key, def in pairs(Config.SkillCategories) do
        if def.categoryUid == raw then return key end
    end
    return nil
end
function SkillTree.CategoryUid(catKey)
    local key = SkillTree.ResolveKey(catKey)
    if not key then return catKey end
    return Config.SkillCategories[key].categoryUid
end

-- Load only the normalize function by extracting via a shim Skills table.
-- We require the real file won't load under plain lua (FiveM natives).
-- Instead, inline a copy of the pure normalize logic by loading ml_skills with stubs.

local natives = {
    GetGameTimer = function() return 0 end,
    GetResourceState = function() return 'missing' end,
    GetPlayers = function() return {} end,
    GetCurrentResourceName = function() return 'sanctuary_crafting' end,
    IsPlayerAceAllowed = function() return false end,
    AddEventHandler = function() end,
    TriggerClientEvent = function() end,
    print = print,
}
for k, v in pairs(natives) do _G[k] = v end
lib = { addCommand = function() end, callback = { register = function() end } }
exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
DebugPrint = function() end
_ = function(k) return k end

-- Partial load: read file and exec — will register Skills.*
dofile('server/integrations/ml_skills.lua')

local spec = dofile('tests/skill_normalize_spec.lua')
local n = spec.run(Skills)
print(('OK — %d normalize cases passed'):format(n))
