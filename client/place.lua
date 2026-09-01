--[[
    Placement de bancs via item ox_inventory
]]

local placing = false

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function raycastFromCamera(dist)
    local camCoord = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local dir = rotationToDirection(camRot)
    local dest = camCoord + dir * dist
    local handle = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, -1, cache.ped or PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(handle)
    return hit == 1, endCoords
end

RegisterNetEvent('sanctuary_crafting:client:startPlace', function(category, itemName)
    if placing then return end
    if not IsValidBenchCategory(category) then return end

    placing = true
    local model = GetBenchModel(category) or `prop_tool_bench02`
    lib.requestModel(model, 5000)

    local ped = cache.ped or PlayerPedId()
    local preview = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(preview, 180, false)
    SetEntityCollision(preview, false, false)
    FreezeEntityPosition(preview, true)

    lib.showTextUI('[E] ' .. _('place_bench') .. '  |  [X] Annuler')

    CreateThread(function()
        while placing do
            Wait(0)
            local hit, coords = raycastFromCamera(Config.Place.maxDistance or 5.0)
            local heading = GetEntityHeading(ped)

            if hit then
                SetEntityCoords(preview, coords.x, coords.y, coords.z, false, false, false, false)
                PlaceObjectOnGroundProperly(preview)
                SetEntityHeading(preview, heading)
            end

            if IsControlJustPressed(0, 38) then -- E
                local final = GetEntityCoords(preview)
                local pcoords = GetEntityCoords(ped)
                if Dist3(pcoords, final) > (Config.Place.maxDistance or 5.0) + 1.0 then
                    lib.notify({ type = 'error', description = _('no_space') })
                else
                    placing = false
                    lib.hideTextUI()
                    DeleteEntity(preview)
                    SetModelAsNoLongerNeeded(model)
                    TriggerServerEvent(
                        'sanctuary_crafting:server:placeBench',
                        category,
                        { x = final.x, y = final.y, z = final.z },
                        heading
                    )
                    return
                end
            end

            if IsControlJustPressed(0, 73) then -- X
                placing = false
                lib.hideTextUI()
                DeleteEntity(preview)
                SetModelAsNoLongerNeeded(model)
                lib.notify({ type = 'inform', description = _('place_cancelled') })
                return
            end
        end
    end)
end)

