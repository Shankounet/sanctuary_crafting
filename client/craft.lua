--[[
    Menu craft (ox_lib context) + progress serveur-autoritaire
]]

local crafting = false

local function formatIngredients(ingredients)
    local lines = {}
    for i = 1, #ingredients do
        local ing = ingredients[i]
        lines[#lines + 1] = ('%sx %s'):format(ing.count, ing.item)
    end
    return table.concat(lines, ', ')
end

function OpenCraftMenu(benchKey)
    if crafting then
        lib.notify({ type = 'error', description = _('craft_busy') })
        return
    end

    local data = lib.callback.await('sanctuary_crafting:getMenu', false, benchKey)
    if not data or not data.ok then
        lib.notify({ type = 'error', description = _(data and data.reason or 'craft_failed') })
        return
    end

    if not data.recipes or #data.recipes == 0 then
        lib.notify({
            type = 'inform',
            description = 'Aucune recette configurée pour cet atelier (Config.Recipes).',
        })
        return
    end

    local options = {}
    for i = 1, #data.recipes do
        local r = data.recipes[i]
        local descParts = {
            _('ingredients') .. ': ' .. formatIngredients(r.ingredients),
            _('duration', math.floor((r.duration or 0) / 1000)),
        }
        if r.xp then
            descParts[#descParts + 1] = _('xp_reward', r.xp.amount, r.xp.category)
        end
        if r.requireLevel then
            descParts[#descParts + 1] = _('req_level', r.requireLevel)
        end
        if r.requireSkill then
            descParts[#descParts + 1] = _('req_skill', r.requireSkill)
        end

        local disabled = r.locked or r.missingItems
        local icon = 'fa-solid fa-wrench'
        if r.locked then icon = 'fa-solid fa-lock' end
        if r.missingItems and not r.locked then icon = 'fa-solid fa-box-open' end

        options[#options + 1] = {
            title = r.label,
            description = table.concat(descParts, '\n'),
            icon = icon,
            disabled = disabled,
            onSelect = function()
                StartCraft(r.id, benchKey)
            end,
        }
    end

    lib.registerContext({
        id = 'sanctuary_craft_menu',
        title = _('craft_menu_title', data.label),
        options = options,
    })
    lib.showContext('sanctuary_craft_menu')
end

function StartCraft(recipeId, benchKey)
    if crafting then return end

    local start = lib.callback.await('sanctuary_crafting:startCraft', false, recipeId, benchKey)
    if not start or not start.ok then
        local reason = start and start.reason or 'craft_failed'
        if start and start.args then
            lib.notify({ type = 'error', description = _(reason, table.unpack(start.args)) })
        else
            lib.notify({ type = 'error', description = _(reason) })
        end
        return
    end

    crafting = true
    local benchCoords = start.benchCoords
    local cancelDist = start.cancelDistance or Config.CraftCancelDistance or 3.0

    local success = lib.progressBar({
        duration = start.duration,
        label = _('craft_progress', start.label or recipeId),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
        },
    })

    -- Cancel if moved away during progress (extra check)
    if success and benchCoords then
        local ped = cache.ped or PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        if Dist3(pcoords, benchCoords) > cancelDist then
            success = false
        end
    end

    if not success then
        TriggerServerEvent('sanctuary_crafting:server:cancelCraft')
        crafting = false
        lib.notify({ type = 'error', description = _('craft_cancelled') })
        return
    end

    local result = lib.callback.await('sanctuary_crafting:completeCraft', false, recipeId, benchKey)
    crafting = false

    if result and result.ok then
        local res = result.result
        lib.notify({
            type = 'success',
            description = _('craft_success', res.count or 1, result.label or res.item),
        })
    else
        local reason = result and result.reason or 'craft_failed'
        lib.notify({ type = 'error', description = _(reason) })
    end
end

-- Thread: cancel craft if player walks away while progress runs
-- (ox_lib progress already canCancel; distance enforced on complete)
