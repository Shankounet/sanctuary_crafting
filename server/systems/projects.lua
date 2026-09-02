--[[
    projects/projects.lua — projets multi-contributeurs
]]

Projects = Projects or {}

local projects = {} -- [projectId] = data

function Projects.EnsureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_projects` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `project_uid` VARCHAR(64) NOT NULL,
            `recipe_id` VARCHAR(64) NOT NULL,
            `bench_key` VARCHAR(64) NOT NULL,
            `owner` VARCHAR(60) NOT NULL,
            `contributors` LONGTEXT NOT NULL,
            `deposited` LONGTEXT NOT NULL,
            `required` LONGTEXT NOT NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'open',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), UNIQUE KEY `uniq_uid` (`project_uid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

local function ident(src) return GetPlayerIdentifierSafe(src) end

--- Rebuild required ingredients from live recipe. Never persist a copy.
local function requiredOf(recipeId)
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return {} end
    local required = {}
    for i = 1, #(recipe.ingredients or {}) do
        local ing = recipe.ingredients[i]
        if ing and ing.item then
            required[#required + 1] = { item = ing.item, count = ing.count or 1 }
        end
    end
    return required
end

function Projects.Create(src, recipeId, benchKey)
    if not Config.Projects or not Config.Projects.Enabled then
        return nil, 'projects_disabled'
    end
    local recipe = Config.RecipeById[recipeId]
    if not recipe then return nil, 'craft_invalid' end
    local uid = GenerateCraftId()
    local required = requiredOf(recipeId)
    local owner = ident(src)
    local data = {
        projectUid = uid, recipeId = recipeId, benchKey = benchKey,
        owner = owner, contributors = { owner },
        deposited = {}, required = required, status = 'open',
    }
    for i = 1, #required do data.deposited[required[i].item] = 0 end
    projects[uid] = data
    -- required column kept NOT NULL for old schema; persist empty — rebuilt from recipe at load
    MySQL.insert.await(
        'INSERT INTO sanctuary_projects (project_uid, recipe_id, bench_key, owner, contributors, deposited, required, status) VALUES (?,?,?,?,?,?,?,?)',
        { uid, recipeId, benchKey, owner, json.encode(data.contributors), json.encode(data.deposited), '[]', 'open' }
    )
    CraftingCore.Emit('projectCreated', src, data)
    return data
end

function Projects.Deposit(src, projectUid, item, count)
    local p = projects[projectUid]
    if not p or p.status ~= 'open' then return false, 'project_invalid' end
    local id = ident(src)
    local maxC = Config.Projects.MaxContributors or 4
    local isContrib = false
    for _, c in ipairs(p.contributors) do if c == id then isContrib = true break end end
    if not isContrib then
        if #p.contributors >= maxC then return false, 'project_full' end
        p.contributors[#p.contributors + 1] = id
    end
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'craft_invalid' end
    if (exports.ox_inventory:GetItemCount(src, item) or 0) < count then
        return false, 'craft_no_ingredients'
    end
    local needed = 0
    for _, r in ipairs(p.required) do
        if r.item == item then needed = r.count break end
    end
    if needed <= 0 then return false, 'craft_invalid' end
    local have = p.deposited[item] or 0
    local space = needed - have
    if space <= 0 then return false, 'project_item_full' end
    local take = math.min(space, count)
    if not exports.ox_inventory:RemoveItem(src, item, take) then return false, 'craft_no_ingredients' end
    p.deposited[item] = have + take
    MySQL.update.await('UPDATE sanctuary_projects SET contributors=?, deposited=? WHERE project_uid=?', {
        json.encode(p.contributors), json.encode(p.deposited), projectUid
    })
    return true, take
end

function Projects.IsComplete(p)
    for _, r in ipairs(p.required) do
        if (p.deposited[r.item] or 0) < r.count then return false end
    end
    return true
end

function Projects.Finish(src, projectUid)
    local p = projects[projectUid]
    if not p or p.status ~= 'open' then return false, 'project_invalid' end
    if not Projects.IsComplete(p) then return false, 'project_incomplete' end
    local recipe = Config.RecipeById[p.recipeId]
    if not recipe then return false, 'craft_invalid' end
    local meta = { craftUID = projectUid, project = true, craftedBy = ident(src) }
    if not Validation.CanCarry(src, recipe.result.item, recipe.result.count or 1) then
        return false, 'craft_inventory_full'
    end
    exports.ox_inventory:AddItem(src, recipe.result.item, recipe.result.count or 1, meta)
    if recipe.xp and recipe.xp.category then
        CraftingSkills.AddXP(recipe.xp.category, recipe.xp.amount or 0, src)
    end
    p.status = 'done'
    projects[projectUid] = nil
    MySQL.query.await('DELETE FROM sanctuary_projects WHERE project_uid=?', { projectUid })
    CraftingCore.Emit('projectFinished', src, p)
    return true, recipe
end

function Projects.ListOpenFor(identifier)
    local out = {}
    if not identifier then return out end
    for _, p in pairs(projects) do
        if p.status == 'open' then
            local hit = p.owner == identifier
            if not hit then
                for _, c in ipairs(p.contributors or {}) do
                    if c == identifier then hit = true break end
                end
            end
            if hit then out[#out + 1] = p end
        end
    end
    return out
end

CreateThread(function()
    MySQL.ready.await()
    Projects.EnsureTable()
    pcall(function()
        MySQL.query.await("DELETE FROM sanctuary_projects WHERE status='done'")
    end)
    local rows = MySQL.query.await("SELECT * FROM sanctuary_projects WHERE status='open'") or {}
    for i = 1, #rows do
        local r = rows[i]
        local required = requiredOf(r.recipe_id)
        -- ignore persisted required (D copy of recipe.ingredients)
        if #required == 0 then
            required = json.decode(r.required) or {}
        end
        projects[r.project_uid] = {
            projectUid = r.project_uid, recipeId = r.recipe_id, benchKey = r.bench_key,
            owner = r.owner, contributors = json.decode(r.contributors) or {},
            deposited = json.decode(r.deposited) or {}, required = required,
            status = r.status,
        }
    end
end)

lib.callback.register('sanctuary_crafting:projectCreate', function(src, recipeId, benchKey)
    local data, err = Projects.Create(src, recipeId, benchKey)
    if not data then return { ok = false, reason = err } end
    return { ok = true, project = data }
end)

lib.callback.register('sanctuary_crafting:projectDeposit', function(src, uid, item, count)
    local ok, extra = Projects.Deposit(src, uid, item, count)
    return { ok = ok, reason = extra, amount = ok and extra or nil }
end)

lib.callback.register('sanctuary_crafting:projectFinish', function(src, uid)
    local ok, extra = Projects.Finish(src, uid)
    if not ok then return { ok = false, reason = extra } end
    return { ok = true, label = extra.label }
end)

lib.callback.register('sanctuary_crafting:projectGet', function(src, uid)
    return { ok = projects[uid] ~= nil, project = projects[uid] }
end)
