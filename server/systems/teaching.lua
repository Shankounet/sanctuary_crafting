--[[
    systems/teaching.lua — enseignement de recettes (serveur autoritaire)
    Client envoie recipeId + target. Le serveur revalide tout. Le client ne décide jamais le succès.
]]

Teaching = Teaching or {}

local sessions = {} -- [teacherSrc] = { student, recipeId, startedAt, cancelled }

local function cfg()
    return Config.Teaching or {}
end

local function recipeFacingLabel(recipe)
    if OxItemCatalog and OxItemCatalog.RecipeLabel then
        return OxItemCatalog.RecipeLabel(recipe)
    end
    return recipe and recipe.label
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function isDead(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    if GetEntityHealth then
        return GetEntityHealth(ped) <= 0
    end
    return false
end

local function distBetween(a, b)
    if not a or not b then return 9999 end
    return Dist3(a, b)
end

local function isSecretFamily(recipe)
    if not recipe then return false end
    if recipe.secret or recipe.military or recipe.event or recipe.unique then return true end
    local tags = recipe.tags or {}
    for i = 1, #tags do
        local tl = tostring(tags[i] or ""):lower()
        if tl == "secret" or tl == "military" or tl == "militaire" or tl == "event" or tl == "unique" then
            return true
        end
    end
    local meta = recipe.blueprintMeta
    local tier = meta and (meta.tier or meta.type) or recipe.blueprintTier or recipe.blueprintType
    if type(tier) == "string" then
        local tl = tier:lower()
        if tl == "military" or tl == "militaire" or tl == "secret" or tl == "event" or tl == "unique" then
            return true
        end
    end
    return false
end

function Teaching.IsTeachable(recipe)
    local c = cfg()
    if c.Enabled == false then return false end
    if not recipe then return false end
    if recipe.teachable == true then return true end
    if recipe.teachable == false then return false end
    if isSecretFamily(recipe) then return false end
    return c.DefaultTeachable == true
end

local function playerName(src)
    local name = GetPlayerName(src)
    if type(name) == "string" and name ~= "" then return name end
    return ("Joueur #%s"):format(src)
end

local function checkTeacherKnown(src, recipe)
    if Blueprints and Blueprints.KnowsRecipe then
        return Blueprints.KnowsRecipe(src, recipe)
    end
    local bpId = recipe.requireBlueprint or recipe.blueprintId
    if bpId and Blueprints and Blueprints.Has then
        return Blueprints.Has(src, bpId)
    end
    return true
end

local function checkStudentKnown(src, recipe)
    return checkTeacherKnown(src, recipe)
end

local function checkSpec(src, recipe)
    if Specializations and Specializations.CanCraftRecipe then
        return Specializations.CanCraftRecipe(src, recipe)
    end
    return true
end

local function checkLevel(src, recipe)
    if not recipe.requireLevel then return true end
    if not CraftingSkills or not CraftingSkills.HasRequiredLevel then return false end
    local cat = CraftingSkills.LevelCategoryForRecipe and CraftingSkills.LevelCategoryForRecipe(recipe)
    return CraftingSkills.HasRequiredLevel(cat, recipe.requireLevel, src)
end

local function checkMastery(src, recipe)
    local need = tonumber(cfg().RequireTeacherMastery) or 0
    if need <= 0 then return true end
    if not Mastery or not Mastery.Get then return false end
    return (Mastery.Get(src, recipe.id) or 0) >= need
end

--- Preview conditions (serveur) — NUI affiche ✓/✕
function Teaching.Preview(teacher, recipeId, student)
    local c = cfg()
    if c.Enabled == false then return nil, "teach_disabled" end
    local recipe = Config.RecipeById and Config.RecipeById[recipeId]
    if not recipe then return nil, "craft_invalid" end

    local teachable = Teaching.IsTeachable(recipe)
    local teacherKnown = checkTeacherKnown(teacher, recipe)
    local teacherSpec = true
    local teacherSpecReason
    if c.RequireTeacherSpec ~= false then
        teacherSpec, teacherSpecReason = checkSpec(teacher, recipe)
    end
    local teacherLevel = true
    if c.RequireTeacherLevel ~= false then
        teacherLevel = checkLevel(teacher, recipe)
    end
    local teacherMastery = checkMastery(teacher, recipe)

    local studentOk = student and GetPlayerName(student) ~= nil
    local studentKnown = studentOk and checkStudentKnown(student, recipe) or false
    local studentSpec = true
    if studentOk and c.RequireStudentSpec ~= false then
        studentSpec = select(1, checkSpec(student, recipe))
    end
    local studentLevel = true
    if studentOk and c.RequireStudentLevel == true then
        studentLevel = checkLevel(student, recipe)
    end

    local proximity = false
    local dist = nil
    if studentOk then
        dist = distBetween(pedCoords(teacher), pedCoords(student))
        proximity = dist <= (c.Distance or 2.5)
    end

    local conds = {
        teachable = teachable,
        teacherKnown = teacherKnown,
        teacherSpec = teacherSpec and true or false,
        teacherLevel = teacherLevel and true or false,
        teacherMastery = teacherMastery and true or false,
        studentSpec = (not studentOk) and nil or (studentSpec and true or false),
        studentKnown = (not studentOk) and nil or studentKnown,
        studentAlreadyKnown = studentKnown,
        proximity = proximity,
        distance = dist,
    }

    local can = teachable and teacherKnown and teacherSpec and teacherLevel and teacherMastery
    if studentOk then
        can = can and (not studentKnown) and studentSpec and proximity and studentLevel
    end

    return {
        ok = true,
        canStart = can and studentOk and true or false,
        recipeId = recipe.id,
        label = recipeFacingLabel(recipe),
        teachable = teachable,
        conditions = conds,
        student = studentOk and { id = student, name = playerName(student) } or nil,
        reason = (not teachable and "teach_not_teachable")
            or (not teacherKnown and "teach_teacher_unknown")
            or (not teacherSpec and (teacherSpecReason or "craft_spec_required"))
            or (not teacherLevel and "craft_level_required")
            or (studentKnown and "teach_already_known")
            or (studentOk and not studentSpec and "craft_spec_required")
            or (studentOk and not proximity and "teach_too_far")
            or nil,
    }
end

function Teaching.Nearby(src)
    local c = cfg()
    local maxDist = c.Distance or 2.5
    local origin = pedCoords(src)
    if not origin then return {} end
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local other = tonumber(sid)
        if other and other ~= src then
            local d = distBetween(origin, pedCoords(other))
            if d <= maxDist + 0.5 then
                out[#out + 1] = {
                    id = other,
                    name = playerName(other),
                    distance = math.floor(d * 10 + 0.5) / 10,
                }
            end
        end
    end
    table.sort(out, function(a, b) return (a.distance or 99) < (b.distance or 99) end)
    return out
end

local function abortSession(teacher, reason)
    local ses = sessions[teacher]
    if not ses then return end
    sessions[teacher] = nil
    local student = ses.student
    TriggerClientEvent("sanctuary_crafting:client:teachCancel", teacher, reason or "teach_cancelled")
    if student then
        TriggerClientEvent("sanctuary_crafting:client:teachCancel", student, reason or "teach_cancelled")
    end
end

function Teaching.Start(teacher, recipeId, student)
    local c = cfg()
    student = tonumber(student)
    if not student then return nil, "craft_invalid" end
    local preview = Teaching.Preview(teacher, recipeId, student)
    if not preview or not preview.canStart then
        return nil, (preview and preview.reason) or "teach_refused"
    end
    if sessions[teacher] or sessions[student] then
        return nil, "craft_busy"
    end

    local duration = tonumber(c.DurationMs) or 30000
    local recipe = Config.RecipeById[recipeId]
    local label = recipeFacingLabel(recipe)
    local ses = {
        teacher = teacher,
        student = student,
        recipeId = recipeId,
        startedAt = GetGameTimer(),
        duration = duration,
        cancelled = false,
    }
    sessions[teacher] = ses
    sessions[student] = ses

    TriggerClientEvent("sanctuary_crafting:client:teachProgress", teacher, {
        role = "teacher", duration = duration, label = label, recipeId = recipeId, peer = playerName(student),
    })
    TriggerClientEvent("sanctuary_crafting:client:teachProgress", student, {
        role = "student", duration = duration, label = label, recipeId = recipeId, peer = playerName(teacher),
    })

    CreateThread(function()
        local maxDist = c.Distance or 2.5
        while sessions[teacher] == ses and not ses.cancelled do
            Wait(400)
            if ses.cancelled then break end
            if not GetPlayerName(teacher) or not GetPlayerName(student) then
                ses.cancelled = true
                abortSession(teacher, "teach_cancelled")
                sessions[student] = nil
                return
            end
            if isDead(teacher) or isDead(student) then
                ses.cancelled = true
                abortSession(teacher, "teach_cancelled")
                sessions[student] = nil
                return
            end
            local d = distBetween(pedCoords(teacher), pedCoords(student))
            if d > maxDist + 0.35 then
                ses.cancelled = true
                abortSession(teacher, "teach_too_far")
                sessions[student] = nil
                return
            end
            if GetGameTimer() - ses.startedAt >= duration then
                break
            end
        end
        if ses.cancelled or sessions[teacher] ~= ses then
            sessions[student] = nil
            sessions[teacher] = nil
            return
        end
        -- re-check all gates at success
        local again = Teaching.Preview(teacher, recipeId, student)
        sessions[teacher] = nil
        sessions[student] = nil
        if not again or not again.canStart then
            TriggerClientEvent("sanctuary_crafting:client:teachCancel", teacher, again and again.reason or "teach_refused")
            TriggerClientEvent("sanctuary_crafting:client:teachCancel", student, again and again.reason or "teach_refused")
            return
        end
        local okGrant = false
        if Blueprints and Blueprints.GrantKnowledge then
            okGrant = Blueprints.GrantKnowledge(student, recipe, "teach")
        elseif Blueprints and Blueprints.Learn then
            local bpId = recipe.requireBlueprint or recipe.blueprintId or recipe.id
            okGrant = Blueprints.Learn(student, bpId)
        end
        if NewlyLearned and NewlyLearned.Mark then
            NewlyLearned.Mark(student, recipe.id, "teach")
        end
        local id = GetPlayerIdentifierSafe(student)
        if id and SurvivalBook and SurvivalBook.PushHistory then
            SurvivalBook.PushHistory(id, "recipe_taught", { recipeId = recipe.id, teacher = GetPlayerIdentifierSafe(teacher) })
        end
        local tid = GetPlayerIdentifierSafe(teacher)
        if tid and SurvivalBook and SurvivalBook.PushHistory then
            SurvivalBook.PushHistory(tid, "recipe_taught_by_me", { recipeId = recipe.id, student = id })
        end
        CraftingCore.Emit("recipeTaught", teacher, student, recipe.id)
        TriggerClientEvent("sanctuary_crafting:client:teachSuccess", teacher, { recipeId = recipe.id, label = label, role = "teacher" })
        TriggerClientEvent("sanctuary_crafting:client:teachSuccess", student, { recipeId = recipe.id, label = label, role = "student" })
        TriggerClientEvent("ox_lib:notify", teacher, { type = "success", description = _("teach_success_teacher", label, playerName(student)) })
        TriggerClientEvent("ox_lib:notify", student, { type = "success", description = _("teach_success_student", label, playerName(teacher)) })
        okGrant = okGrant
    end)

    return { ok = true, duration = duration, label = label }
end

function Teaching.Cancel(src, reason)
    local ses = sessions[src]
    if not ses then return false end
    ses.cancelled = true
    local teacher = ses.teacher
    local student = ses.student
    sessions[teacher] = nil
    sessions[student] = nil
    TriggerClientEvent("sanctuary_crafting:client:teachCancel", teacher, reason or "teach_cancelled")
    TriggerClientEvent("sanctuary_crafting:client:teachCancel", student, reason or "teach_cancelled")
    return true
end

lib.callback.register("sanctuary_crafting:teachPreview", function(src, recipeId, student)
    if type(recipeId) ~= "string" then return { ok = false, reason = "craft_invalid" } end
    local data, err = Teaching.Preview(src, recipeId, tonumber(student))
    if not data then return { ok = false, reason = err or "teach_refused" } end
    return data
end)

lib.callback.register("sanctuary_crafting:teachNearby", function(src)
    return { ok = true, players = Teaching.Nearby(src) }
end)

lib.callback.register("sanctuary_crafting:teachStart", function(src, recipeId, student)
    if type(recipeId) ~= "string" then return { ok = false, reason = "craft_invalid" } end
    local data, err = Teaching.Start(src, recipeId, student)
    if not data then return { ok = false, reason = err or "teach_refused" } end
    return data
end)

lib.callback.register("sanctuary_crafting:teachCancel", function(src)
    Teaching.Cancel(src, "teach_cancelled")
    return { ok = true }
end)

AddEventHandler("playerDropped", function()
    Teaching.Cancel(source, "teach_cancelled")
end)
