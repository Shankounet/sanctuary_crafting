--[[
    client/teaching.lua — progress ox_lib ; le client ne décide jamais le succès
]]

local teaching = false

local function stopProgress()
    if lib and lib.cancelProgress then
        pcall(lib.cancelProgress)
    end
end

RegisterNetEvent("sanctuary_crafting:client:teachProgress", function(payload)
    payload = type(payload) == "table" and payload or {}
    teaching = true
    local duration = tonumber(payload.duration) or 30000
    local label = payload.label or ""
    local role = payload.role or "teacher"
    local title = role == "student" and _("teach_progress_student", label) or _("teach_progress_teacher", label)

    CreateThread(function()
        local ok = false
        if lib and lib.progressBar then
            ok = lib.progressBar({
                duration = duration,
                label = title,
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = (Config.Animations and Config.Animations.Default) or { dict = "mini@repair", clip = "fixing_a_ped" },
            })
        else
            Wait(duration)
            ok = teaching
        end
        if not teaching then return end
        if not ok then
            teaching = false
            lib.callback.await("sanctuary_crafting:teachCancel", false)
        end
    end)
end)

RegisterNetEvent("sanctuary_crafting:client:teachCancel", function(reason)
    teaching = false
    stopProgress()
    if reason then
        lib.notify({ type = "error", description = _(reason) })
    end
end)

RegisterNetEvent("sanctuary_crafting:client:teachSuccess", function(payload)
    teaching = false
    stopProgress()
    payload = type(payload) == "table" and payload or {}
    SendNUIMessage({ action = "teachSuccess", recipeId = payload.recipeId, label = payload.label, role = payload.role })
end)
