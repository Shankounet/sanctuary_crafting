--[[
    Menu craft — NUI prioritaire, fallback ox_lib context
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

    if OpenCraftNui and Config.UI and Config.UI.UseNui ~= false then
        if OpenCraftNui(data) then return end
    end

    -- Fallback ox_lib
    if not data.recipes or #data.recipes == 0 then
        lib.notify({ type = 'inform', description = 'Aucune recette configurée pour cet atelier.' })
        return
    end

    local options = {}
    for i = 1, #data.recipes do
        local r = data.recipes[i]
        local descParts = {
            _('ingredients') .. ': ' .. formatIngredients(r.ingredients),
            _('duration', math.floor((r.duration or 0) / 1000)),
        }
        if r.xp then descParts[#descParts + 1] = _('xp_reward', r.xp.amount, r.skillCategoryLabel or r.xp.category) end
        local reqLvl = (r.skillTree and r.skillTree.requiredLevel) or r.requireLevel
        if reqLvl then descParts[#descParts + 1] = _('req_level', reqLvl) end
        local talent = r.requiredSkillLabel
        if talent then descParts[#descParts + 1] = _('req_skill', talent) end
        if r.locked and r.lockReason then descParts[#descParts + 1] = _(r.lockReason, table.unpack(r.lockArgs or {})) end

        options[#options + 1] = {
            title = r.label,
            description = table.concat(descParts, '\n'),
            icon = r.locked and 'fa-solid fa-lock' or 'fa-solid fa-wrench',
            disabled = r.locked or r.missingItems,
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

function StartCraft(recipeId, benchKey, batch)
    if crafting then return end
    local start = lib.callback.await('sanctuary_crafting:startCraft', false, recipeId, benchKey, batch or 1)
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
    local anim = start.anim or (Config.Animations and Config.Animations.Default) or {
        dict = 'mini@repair', clip = 'fixing_a_ped',
    }
    local success = lib.progressBar({
        duration = start.duration,
        label = _('craft_progress', start.label or recipeId),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim,
    })

    if success and start.benchCoords then
        local ped = cache.ped or PlayerPedId()
        if Dist3(GetEntityCoords(ped), start.benchCoords) > (start.cancelDistance or 3.0) then
            success = false
        end
    end

    if not success then
        TriggerServerEvent('sanctuary_crafting:server:cancelCraft', start.craftId)
        crafting = false
        lib.notify({ type = 'error', description = _('craft_cancelled') })
        return
    end

    local result = lib.callback.await('sanctuary_crafting:completeCraft', false, start.craftId)
    crafting = false

    if result and result.ok then
        local res = result.result or {}
        lib.notify({
            type = 'success',
            description = _('craft_success', res.count or 1, result.label or res.item or '?'),
        })
    else
        lib.notify({ type = 'error', description = _(result and result.reason or 'craft_failed') })
    end
end
