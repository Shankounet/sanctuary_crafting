--[[
    systems/admin_logs.lua — sanctuary_admin_logs + Discord webhooks (OFF by default)
    Pipeline is HTTP-unaware: this module registers via AddCraftingHook / CraftingCore.On.
]]

AdminLogs = AdminLogs or {}

local function craftHistoryOn()
    local ch = Config.CraftHistory
    if ch == true then return true end
    if type(ch) == 'table' then return ch.Enabled == true end
    return false
end

function AdminLogs.PurgeOld()
    if not MySQL or not MySQL.query or not MySQL.query.await then return end
    local days = math.floor((Config.AdminLogs and tonumber(Config.AdminLogs.RetentionDays)) or 14)
    if days < 1 then return end
    pcall(function()
        MySQL.query.await(
            ('DELETE FROM sanctuary_admin_logs WHERE created_at < (NOW() - INTERVAL %d DAY)'):format(days)
        )
    end)
end

function AdminLogs.EnsureTable()
    if not MySQL or not MySQL.query or not MySQL.query.await then return end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `sanctuary_admin_logs` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `event_type` VARCHAR(32) NOT NULL,
            `actor` VARCHAR(60) NULL,
            `source` INT NULL,
            `payload` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_event_time` (`event_type`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function identOf(src)
    if not src or src == 0 then return 'console' end
    if GetPlayerIdentifierSafe then
        return GetPlayerIdentifierSafe(src) or ('src:' .. tostring(src))
    end
    return 'src:' .. tostring(src)
end

local function encode(payload)
    if payload == nil then return nil end
    local ok, s = pcall(json.encode, payload)
    if ok then return s end
    return tostring(payload)
end

function AdminLogs.Record(eventType, src, payload)
    eventType = tostring(eventType or 'unknown'):sub(1, 32)
    local actor = identOf(src)
    pcall(function()
        MySQL.insert.await(
            'INSERT INTO sanctuary_admin_logs (event_type, actor, source, payload) VALUES (?, ?, ?, ?)',
            { eventType, actor, src, encode(payload) }
        )
    end)
    AdminLogs.MaybeDiscord(eventType, src, payload)
end

local function webhookCfg(eventType)
    local d = Config.Discord
    if not d or d.Enabled == true then
        -- master default is OFF; Enabled must be explicitly true
    end
    if not d or d.Enabled ~= true then
        return nil
    end
    local hooks = d.Webhooks or {}
    local h = hooks[eventType]
    if type(h) ~= 'table' or h.Enabled ~= true then return nil end
    if type(h.Url) ~= 'string' or h.Url == '' then return nil end
    return h
end

function AdminLogs.MaybeDiscord(eventType, src, payload)
    local h = webhookCfg(eventType)
    if not h then return end
    local name = src and GetPlayerName and GetPlayerName(src) or 'console'
    local body = {
        username = 'Sanctuary Crafting',
        embeds = {{
            title = eventType,
            description = ('src=%s name=%s'):format(tostring(src), tostring(name)),
            color = 10061902,
            fields = {
                { name = 'payload', value = ('```json\n%s\n```'):format((encode(payload) or '{}'):sub(1, 900)), inline = false },
            },
        }},
    }
    PerformHttpRequest(h.Url, function() end, 'POST', json.encode(body), {
        ['Content-Type'] = 'application/json',
    })
end

local function rarityOf(recipe)
    if type(recipe) ~= 'table' then return '' end
    return tostring(recipe.rarity or ''):lower()
end

local function hookCompleted(src, craft, given)
    local recipe = RecipeSnapshot and RecipeSnapshot.Of(craft) or (craft and craft.snapshot)
    local rarity = rarityOf(recipe)
    local batch = craft and (craft.batch or 1) or 1
    local station = recipe and (recipe.station or recipe.category)
    local payload = {
        recipeId = craft and craft.recipeId,
        batch = batch,
        rarity = rarity,
        station = station,
        given = given,
        version = craft and craft.recipeVersion,
    }
    -- skip unbounded every-craft rows when CraftHistory is off; keep rare/suspicious
    if craftHistoryOn() then
        AdminLogs.Record('craftCompleted', src, payload)
    end
    if rarity == 'legendary' then
        AdminLogs.Record('legendaryCraft', src, payload)
    elseif rarity == 'epic' then
        AdminLogs.Record('epicCraft', src, payload)
    end
    if station == 'weapons' or station == 'armurier' or station == 'munition'
        or (recipe and recipe.category == 'weapons') then
        AdminLogs.Record('weaponCraft', src, payload)
    end
    local cap = (CraftBatch and CraftBatch.HardCap and CraftBatch.HardCap()) or 100
    if batch >= 10 or (cap > 0 and batch >= math.floor(cap * 0.5)) then
        AdminLogs.Record('unusualBatch', src, payload)
    end
end

local function registerHooks()
    if not CraftingCore or not CraftingCore.On then return end
    CraftingCore.On('craftCompleted', hookCompleted)
    CraftingCore.On('blueprintLearned', function(src, bpId)
        AdminLogs.Record('rareBlueprint', src, { blueprintId = bpId })
    end)
    CraftingCore.On('recipeLearned', function(src, recipeId)
        AdminLogs.Record('recipeLearned', src, { recipeId = recipeId })
    end)
    CraftingCore.On('adminRecipeEdit', function(src, recipeId, version, disabled)
        AdminLogs.Record('adminRecipeEdit', src, { recipeId = recipeId, version = version, disabled = disabled })
    end)
    CraftingCore.On('validationFail', function(src, kind, extra)
        AdminLogs.Record('validationFail', src, { kind = kind, extra = extra })
    end)
    CraftingCore.On('suspicious', function(src, kind, extra)
        AdminLogs.Record('suspicious', src, { kind = kind, extra = extra })
    end)
    CraftingCore.On('anomaly', function(kind, src, extra)
        AdminLogs.Record('anomaly', src, { kind = kind, extra = extra })
    end)
end

CreateThread(function()
    if MySQL and MySQL.ready then
        MySQL.ready.await()
        AdminLogs.EnsureTable()
        AdminLogs.PurgeOld()
    end
    registerHooks()
    local interval = (Config.AdminLogs and tonumber(Config.AdminLogs.PurgeIntervalMs)) or 21600000
    if interval < 60000 then interval = 21600000 end
    while true do
        Wait(interval)
        AdminLogs.PurgeOld()
    end
end)
