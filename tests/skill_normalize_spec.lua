--[[
  Offline-ish specs for Skills.normalizeSkillRequirements (cases A–G).
  Run inside resource context OR with a minimal stub harness:

    lua tests/skill_normalize_harness.lua

  Cases:
    A) single requiredSkill → 1 entry
    B) requiredSkill + skillTree mirror (same uid) → 1 entry, dupesRemoved >= 1
    C) two different uids same category → 2 entries
    D) same skillUid different categoryUid → 2 entries
    E) same label different uid → 2 entries (never dedupe by label)
    F) legacy SST/DevHub field alone → ignored / nil gate (no silent OR)
    G) requiredSkill + requiredSkills same skill → 1 entry
]]

local function assertEq(a, b, msg)
    if a ~= b then
        error((msg or 'assertEq') .. (' failed: %s ~= %s'):format(tostring(a), tostring(b)), 2)
    end
end

local function run(Skills)
    local pass = 0

    -- A
    do
        local r = { id = 'A', requiredSkill = { category = 'survival', uid = 'skill_139' } }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n.normalizedCount, 1, 'A count')
        assertEq(n.skills[1].skillUid or n.skills[1].uid, 'skill_139', 'A uid')
        pass = pass + 1
    end

    -- B
    do
        local r = {
            id = 'B',
            requiredSkill = { category = 'survival', uid = 'skill_139' },
            skillTree = { category = 'survival', requiredSkill = 'skill_139' },
        }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n.normalizedCount, 1, 'B count')
        assertEq(n.duplicatesRemoved >= 1, true, 'B dupes')
        pass = pass + 1
    end

    -- C
    do
        local r = {
            id = 'C',
            requiredSkills = {
                mode = 'all',
                skills = {
                    { category = 'survival', uid = 'skill_139' },
                    { category = 'survival', uid = 'skill_140' },
                },
            },
        }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n.normalizedCount, 2, 'C count')
        pass = pass + 1
    end

    -- D
    do
        local r = {
            id = 'D',
            requiredSkills = {
                skills = {
                    { category = 'survival', uid = 'shared_uid' },
                    { category = 'medic', uid = 'shared_uid' },
                },
            },
        }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n.normalizedCount, 2, 'D count')
        pass = pass + 1
    end

    -- E (labels differ only in SkillLabel — uids differ so 2 entries)
    do
        local r = {
            id = 'E',
            requiredSkills = {
                skills = {
                    { category = 'survival', uid = 'skill_a' },
                    { category = 'survival', uid = 'skill_b' },
                },
            },
        }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n.normalizedCount, 2, 'E count')
        pass = pass + 1
    end

    -- F
    do
        local r = { id = 'F', devhubSkill = 'legacy_only', sanctuarySkill = 'x' }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n, nil, 'F ignored')
        pass = pass + 1
    end

    -- G
    do
        local r = {
            id = 'G',
            requiredSkill = { category = 'survival', uid = 'skill_139' },
            requiredSkills = {
                mode = 'all',
                skills = { { category = 'survival', uid = 'skill_139' } },
            },
        }
        local n = Skills.normalizeSkillRequirements(r)
        assertEq(n.normalizedCount, 1, 'G count')
        pass = pass + 1
    end

    return pass
end

return { run = run }
